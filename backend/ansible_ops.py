import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import threading
import uuid
import time
from pathlib import Path

import db as dbmod

DEFAULT_ANSIBLE_DIR = Path(__file__).resolve().parent.parent / "Ansible"
REMOTE_DIR = "/tmp/kisa_audit"

# ansible's become/stdout capture occasionally drops one backslash of a
# doubled escape (e.g. "\\s" -> "\s"), which is invalid JSON. Re-double any
# backslash not already forming a valid JSON escape before parsing.
_BAD_ESCAPE_RE = re.compile(r'\\(?!["\\/bfnrtu])')


def _sanitize_json(s):
    return _BAD_ESCAPE_RE.sub(r"\\\\", s)


class AnsibleError(Exception):
    pass


class ProvisionPartialError(AnsibleError):
    """provision_host()에서 hostname/OS/그룹까지는 확정됐지만 sudo 설정에서
    실패했을 때 던진다. `.facts`(= {"hostname":..., "os":...})를 호출자가 읽어서
    실패해도 DB에 최신 hostname/OS를 반영할 수 있게 한다."""

    def __init__(self, message, facts):
        super().__init__(message)
        self.facts = facts


# =========================================================
# 설정 페이지(Ansible/SSH 연동 설정) 연동
#
# 설정 화면을 한 번도 안 건드린 배포에서도 동작이 그대로 유지되도록, 값이
# 비어 있으면 전부 기존 하드코딩 기본값으로 떨어진다.
# =========================================================

def _load_app_config():
    try:
        raw = dbmod.get_app_config()
    except Exception:
        return {}
    if not raw:
        return {}
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except json.JSONDecodeError:
            return {}
    return raw or {}


def conn_settings():
    """설정 페이지에 저장된 값으로 실제 ansible/ansible-playbook 호출 파라미터를
    만든다. 반환값은 이 모듈의 다른 함수들에 그대로 넘겨 재사용한다(호출마다
    DB를 다시 읽지 않도록 상위 함수 1곳에서만 계산)."""
    cfg = _load_app_config()

    playbook_dir = str(cfg.get("playbookPath") or "").strip()
    ansible_dir = Path(playbook_dir) if playbook_dir else DEFAULT_ANSIBLE_DIR

    inventory_path = str(cfg.get("inventoryPath") or "").strip()
    if inventory_path:
        inv = Path(inventory_path)
        inventory_file = inv if inv.is_absolute() else (ansible_dir / inventory_path)
        inventory_arg = str(inventory_file)
    else:
        inventory_file = ansible_dir / "hosts.ini"
        inventory_arg = "hosts.ini"

    bin_dir = str(cfg.get("ansiblePath") or "").strip()

    def _bin(name):
        if bin_dir:
            candidate = Path(bin_dir) / name
            if candidate.exists():
                return str(candidate)
        return name

    extra_vars = {}
    default_user = str(cfg.get("defaultUser") or "").strip()
    if default_user:
        extra_vars["ansible_user"] = default_user
    ssh_port = str(cfg.get("sshPort") or "").strip()
    if ssh_port and ssh_port != "22":
        extra_vars["ansible_port"] = ssh_port

    ssh_key = str(cfg.get("sshKeyPath") or "").strip()

    timeout_cfg = cfg.get("timeout")
    try:
        timeout = int(timeout_cfg) if timeout_cfg not in (None, "") else None
    except (TypeError, ValueError):
        timeout = None

    try:
        retries = int(cfg.get("retries"))
        if retries < 1:
            retries = 1
    except (TypeError, ValueError):
        retries = 1

    return {
        "ansible_dir": ansible_dir,
        "inventory_file": inventory_file,   # 실제 파일 경로 (hosts.ini 읽기/쓰기용)
        "inventory_arg": inventory_arg,     # -i 에 넘길 문자열
        "playbook_bin": _bin("ansible-playbook"),
        "ansible_bin": _bin("ansible"),
        "extra_vars": extra_vars,
        "ssh_key": ssh_key,
        "timeout": timeout,                 # None이면 호출부가 자기 기존 기본값을 쓴다
        "retries": retries,
    }


def _extra_var_args(settings):
    args = []
    for k, v in settings["extra_vars"].items():
        args += ["-e", f"{k}={v}"]
    if settings["ssh_key"]:
        args += ["--private-key", settings["ssh_key"]]
    return args


def _run(binary, args, timeout, settings, retries=None):
    """ansible/ansible-playbook 실행 공통 헬퍼.

    settings의 접속 관련 extra-vars/개인키를 자동으로 붙이고, "재시도 횟수"
    설정만큼 실패 시 재시도한다(연결이 잠깐 튀는 경우를 위함). 마지막 시도가
    타임아웃이면 그대로 TimeoutExpired를 던진다 - 호출부가 이미 이를 잡아서
    처리하는 기존 동작을 그대로 유지한다.

    retries=1을 명시하면(예: 이미 그 자체로 "실패=다음 단계로" 판단 로직이 있는
    호출) 설정된 재시도 횟수와 무관하게 한 번만 시도한다.
    """
    full_args = [binary] + list(args) + _extra_var_args(settings)
    attempts = max(1, retries if retries is not None else settings["retries"])

    last_proc = None
    last_exc = None
    for _ in range(attempts):
        try:
            last_proc = subprocess.run(
                full_args,
                cwd=str(settings["ansible_dir"]),
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            last_exc = None
            if last_proc.returncode == 0:
                return last_proc
        except subprocess.TimeoutExpired as e:
            last_exc = e
            last_proc = None

    if last_exc is not None:
        raise last_exc
    return last_proc


def inventory_group(os_name):
    """OS 문자열로 hosts.ini의 대상 그룹([rocky]/[ubuntu])을 판별한다.
    /api/servers가 목록의 '그룹' 표시값으로도 그대로 재사용한다 - 버전 번호(9/24.04)는
    OS 컬럼에 이미 전체 문자열로 나오니, 그룹 배지는 계열만 짧게 보여준다."""
    os_lower = (os_name or "").lower()
    if "ubuntu" in os_lower or "debian" in os_lower:
        return "ubuntu"
    return "rocky"


def _section_bounds(lines, section_header):
    """`section_header`(예: "[rocky]")로 시작하는 섹션의 본문 라인 범위(start, end)를
    돌려준다 - end는 다음 '[...]' 헤더 직전(파일 끝이면 len(lines))의 배타적 인덱스.
    섹션을 못 찾으면 (None, None)."""
    for i, line in enumerate(lines):
        if line.strip() == section_header:
            start = i + 1
            end = start
            while end < len(lines) and not lines[end].strip().startswith("["):
                end += 1
            return start, end
    return None, None


def _is_host_line(line):
    s = line.strip()
    return bool(s) and not s.startswith(("#", "["))


def _hostname_in_inventory(hostname, settings):
    """hostname이 inventory 파일에 alias로 실제 존재하는지 확인한다.
    없으면(=Ansible이 "no hosts to target"으로 실패할 상황) 미리 걸러내는 용도."""
    path = settings["inventory_file"]
    if not path.exists():
        return False
    lines = path.read_text(encoding="utf-8").splitlines()
    return any(_is_host_line(line) and line.split()[0] == hostname for line in lines)


def remove_inventory_host(hostname, settings=None):
    """hosts.ini에서 hostname 줄을 제거한다. 서버 목록에서 삭제할 때 같이 호출해서,
    DB에서만 지워지고 inventory엔 그대로 남아 나중에 IP가 겹치는 중복 항목이 다시
    생기는 걸 막는다. 이미 없으면(등록 실패했던 항목 등) 조용히 넘어간다."""
    settings = settings or conn_settings()
    path = settings["inventory_file"]
    if not path.exists():
        return
    lines = path.read_text(encoding="utf-8").splitlines()
    new_lines = [l for l in lines if not (_is_host_line(l) and l.split()[0] == hostname)]
    if new_lines != lines:
        path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")


def set_inventory_group(hostname, os_name, settings=None):
    """`hostname`이 실려 있는 hosts.ini 라인을, os_name에 맞는 그룹([rocky]/[ubuntu])
    섹션으로 옮긴다. 이미 맞는 그룹이면 아무 것도 하지 않는다 - 등록 시점엔 OS를 몰라
    기본값(rocky)으로 넣어뒀다가, provision_host()에서 실제 OS를 알게 된 뒤 바로잡는 용도."""
    settings = settings or conn_settings()
    target_group = inventory_group(os_name)
    path = settings["inventory_file"]
    lines = path.read_text(encoding="utf-8").splitlines()

    cur_idx = None
    for i, line in enumerate(lines):
        if _is_host_line(line) and line.split()[0] == hostname:
            cur_idx = i
            break
    if cur_idx is None:
        raise AnsibleError(f"'{hostname}'을(를) inventory에서 찾을 수 없습니다.")

    cur_group = None
    for i in range(cur_idx, -1, -1):
        s = lines[i].strip()
        if s.startswith("[") and s.endswith("]") and ":" not in s:
            cur_group = s[1:-1]
            break

    if cur_group == target_group:
        return

    host_line = lines.pop(cur_idx)
    start, end = _section_bounds(lines, f"[{target_group}]")
    if start is None:
        raise AnsibleError(f"inventory에서 [{target_group}] 그룹을 찾을 수 없습니다.")
    # 섹션 본문엔 다음 '[...]' 헤더 전까지의 주석/빈 줄도 다 포함되므로(예: 그룹이
    # 비어 있고 바로 다음이 "# 전체 타겟 그룹" 같은 설명 주석인 경우), end에 그냥
    # insert하면 그 주석 뒤/다음 헤더 바로 앞처럼 엉뚱한 자리에 꽂힌다. 마지막
    # '진짜 호스트' 줄 바로 다음(없으면 헤더 바로 다음)에 넣는다.
    insert_at = start
    for i in range(start, end):
        if _is_host_line(lines[i]):
            insert_at = i + 1
    lines.insert(insert_at, host_line)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def add_inventory_host(hostname, ip, os_name, settings=None):
    settings = settings or conn_settings()
    path = settings["inventory_file"]
    group = inventory_group(os_name)
    header = f"[{group}]"
    lines = path.read_text(encoding="utf-8").splitlines()
    host_lines = [line for line in lines if _is_host_line(line)]

    if any(line.split()[0] == hostname for line in host_lines):
        raise AnsibleError(f"'{hostname}'은(는) 이미 inventory에 등록되어 있습니다.")

    # alias 이름만 다르고 실제 접속 IP(ansible_host=)가 같은 중복도 막는다 - 안
    # 그러면 같은 서버를 "초기 설정"으로 hostname이 바뀐 뒤(예: IP -> autoever1),
    # 그 IP를 다시 등록하면 이름이 다르다는 이유로 통과돼서 물리적으로 같은
    # 서버가 두 alias로 따로 등록되고, 스캔도 두 번 잡혀서 서버 목록에 중복으로
    # 나타난다(실측 확인된 버그).
    for line in host_lines:
        for tok in line.split()[1:]:
            if tok == f"ansible_host={ip}":
                existing_alias = line.split()[0]
                raise AnsibleError(
                    f"이 IP({ip})는 이미 '{existing_alias}'(으)로 inventory에 등록되어 있습니다."
                )

    for i, line in enumerate(lines):
        if line.strip() == header:
            lines.insert(i + 1, f"{hostname}\tansible_host={ip}")
            break
    else:
        raise AnsibleError(f"inventory에서 [{group}] 그룹을 찾을 수 없습니다.")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def rename_inventory_host(old_alias, new_alias, settings=None):
    """IP를 임시 alias로 등록해둔 host를, 나중에 gather_facts로 알아낸 실제
    hostname으로 바꿔치기한다. ansible_host= 값(IP)은 그대로 둔다.

    remediate/scan 흐름이 DB의 hostname을 그대로 inventory alias로 사용하므로
    (main.py의 RemediateRequest.hostname 참고), 이 둘은 항상 같아야 한다 —
    DB 쪽 갱신은 호출자가 이 함수 성공 후에 맞춰 해야 한다.
    """
    if old_alias == new_alias:
        return
    settings = settings or conn_settings()
    path = settings["inventory_file"]
    lines = path.read_text(encoding="utf-8").splitlines()

    def is_host_line(line):
        s = line.strip()
        return bool(s) and not s.startswith(("#", "["))

    if any(line.split()[0] == new_alias for line in lines if is_host_line(line)):
        raise AnsibleError(f"'{new_alias}'은(는) 이미 inventory에 등록되어 있습니다.")

    for i, line in enumerate(lines):
        if is_host_line(line) and line.split()[0] == old_alias:
            rest = line.split(None, 1)[1] if len(line.split(None, 1)) > 1 else ""
            lines[i] = f"{new_alias}\t{rest}"
            break
    else:
        raise AnsibleError(f"'{old_alias}'을(를) inventory에서 찾을 수 없습니다.")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def gather_facts(hostname, timeout=None, settings=None):
    """00_gather_facts.yml을 실행해 hostname/OS를 수집한다.

    hostname은 이미 hosts.ini에 등록돼 있는 alias여야 한다 (add_server가 등록
    시점에 IP를 그대로 alias로 넣어두므로, 등록 직후 최초 호출이라면 보통 IP와
    같은 문자열이다).

    성공하면 {"hostname": ..., "os": ..., "detected_db": ...}, 접속 실패/타임아웃/
    미수집이면 None을 반환한다 — 호출자는 None일 때 기존 alias를 그대로 유지해야
    한다. detected_db는 "mysql"/"postgresql"/"mysql,postgresql"/"" 중 하나의
    힌트일 뿐이다 - 실제 확정 결과는 진단 실행의 D-항목을 봐야 한다(00_gather_facts.yml
    상단 주석 참고).
    """
    settings = settings or conn_settings()
    if timeout is None:
        timeout = settings["timeout"] if settings["timeout"] is not None else 30

    local_dir = tempfile.mkdtemp(prefix="facts_")
    try:
        args = [
            "00_gather_facts.yml", "-i", settings["inventory_arg"],
            "-l", hostname, "-e", f"local_facts_dir={local_dir}",
        ]
        try:
            proc = _run(settings["playbook_bin"], args, timeout, settings)
        except subprocess.TimeoutExpired:
            return None
        if proc.returncode != 0:
            return None

        result_file = os.path.join(local_dir, f"{hostname}.json")
        if not os.path.exists(result_file):
            return None
        with open(result_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        new_hostname = data.get("hostname")
        distro = data.get("distro")
        version = data.get("version")
        if not new_hostname or not distro:
            return None
        return {
            "hostname": new_hostname,
            "os": f"{distro} {version}".strip(),
            "detected_db": data.get("detected_db", "") or "",
        }
    finally:
        shutil.rmtree(local_dir, ignore_errors=True)


def _resolve_ssh_target(hostname, settings):
    """hosts.ini에서 hostname의 실제 접속 IP(ansible_host=)를 찾는다."""
    path = settings["inventory_file"]
    if not path.exists():
        raise AnsibleError(f"inventory 파일을 찾을 수 없습니다: {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        if _is_host_line(line) and line.split()[0] == hostname:
            for tok in line.split()[1:]:
                if tok.startswith("ansible_host="):
                    return tok.split("=", 1)[1]
            return hostname  # ansible_host= 생략 - hostname 자체가 접속 주소
    raise AnsibleError(f"'{hostname}'을(를) inventory에서 찾을 수 없습니다.")


def _resolve_ssh_user(settings):
    """설정 페이지의 '기본 접속 계정'이 있으면 그걸, 없으면 hosts.ini의
    [targets:vars] ansible_user=를, 그것도 없으면 'user'를 쓴다."""
    user = settings["extra_vars"].get("ansible_user")
    if user:
        return user
    path = settings["inventory_file"]
    if path.exists():
        m = re.search(r"^\s*ansible_user\s*=\s*(\S+)", path.read_text(encoding="utf-8"), re.MULTILINE)
        if m:
            return m.group(1)
    return "user"


def setup_sudoers(hostname, sudo_password, timeout=None, settings=None):
    """대상 서버 1대에 NOPASSWD sudo를 심는다.

    1) 먼저 00_setup_sudoers.yml을 비밀번호 없이 시도한다 - become 비밀번호를
       안 넘기면 Ansible이 sudo에 -n(non-interactive)을 그대로 둬서, 이미
       NOPASSWD인 서버(base image가 이미 그렇게 왔거나, 재실행인 경우)는 즉시
       성공하고 진짜 비밀번호가 필요한 서버는 대기 없이 바로 실패한다.

    2) 실패하면(=진짜 비밀번호가 필요) Ansible의 become 기능은 쓰지 않고 순수
       SSH로 비밀번호를 직접 sudo -S에 흘려보낸다. Ansible의 become은 자기가
       보낸 커스텀 프롬프트 문자열이 출력에 그대로(정확히 일치) 나오는지를
       감시하는데, 이 프로젝트가 다루는 서버들 중 일부 sudo는 그 프롬프트를
       `[sudo: <내용>] Password:` 식으로 다시 감싸서 출력한다(실측 확인) - 그러면
       Ansible이 절대 못 알아채고 32초 타임아웃(-K/--become-password-file/
       -e ansible_become_pass 셋 다 동일하게 걸림, 다 확인함)이 난다. sudo -S
       자체(원문 프롬프트 무시하고 stdin으로 비번을 바로 흘려보내는 방식)는
       정상 동작하므로, 이 단계만 Ansible을 거치지 않고 직접 처리한다.

       이후의 모든 become(01_run_audit.yml, remediate 등)은 NOPASSWD가 이미
       설정된 뒤라 -n 경로만 타므로 이 문제의 영향을 받지 않는다 - 그래서 이
       우회가 필요한 지점은 여기 단 한 곳뿐이다.
    """
    settings = settings or conn_settings()
    if timeout is None:
        timeout = settings["timeout"] if settings["timeout"] is not None else 60

    base_args = [
        "00_setup_sudoers.yml", "-i", settings["inventory_arg"],
        "-l", hostname,
    ]

    try:
        proc = _run(settings["playbook_bin"], base_args, timeout, settings, retries=1)
    except subprocess.TimeoutExpired:
        raise AnsibleError("연결 시간이 초과됐습니다. 네트워크 상태를 확인하고 다시 시도하세요.")
    if proc.returncode == 0:
        return  # 이미 NOPASSWD였음 - 비밀번호 안 써보고 바로 끝

    ip = _resolve_ssh_target(hostname, settings)
    user = _resolve_ssh_user(settings)
    sudoers_file = f"/etc/sudoers.d/{user}-nopasswd"
    # 임시 파일에 먼저 써서 visudo로 검증한 뒤에야 실제 경로로 옮긴다 - 잘못된
    # sudoers 파일이 서버를 sudo 불가 상태로 만드는 사고를 막기 위함
    # (00_setup_sudoers.yml의 validate: "visudo -cf %s"와 동일한 안전장치).
    remote_script = (
        "set -e; "
        f"tmp=$(mktemp); "
        f"echo {shlex.quote(f'{user} ALL=(ALL) NOPASSWD:ALL')} > \"$tmp\"; "
        f"chmod 0440 \"$tmp\"; chown root:root \"$tmp\"; "
        f"visudo -cf \"$tmp\"; "
        f"mv \"$tmp\" {shlex.quote(sudoers_file)}"
    )
    ssh_args = [
        "ssh", "-o", "StrictHostKeyChecking=no", "-o", f"ConnectTimeout={min(timeout, 30)}",
        f"{user}@{ip}", f"sudo -S -p '' sh -c {shlex.quote(remote_script)}",
    ]
    try:
        proc = subprocess.run(
            ssh_args,
            input=sudo_password + "\n",
            capture_output=True, text=True, timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        raise AnsibleError("연결 시간이 초과됐습니다. 네트워크 상태를 확인하고 다시 시도하세요.")
    if proc.returncode != 0:
        raise AnsibleError(f"sudo 설정 실패 (비밀번호를 확인하세요): {(proc.stdout + proc.stderr)[-1500:]}")


def provision_host(current_alias, sudo_password, timeout=None):
    """서버 등록 후 '초기 설정' 버튼 1회 실행: (1) 00_gather_facts.yml로 hostname/OS
    수집, (2) 그 방금 얻은 값으로 inventory alias를 실제 hostname으로 정리, (3) OS에
    맞는 inventory 그룹 재배치, (4) sudo 비밀번호로 NOPASSWD sudo 설정.

    그룹 재배치를 sudo 설정보다 먼저 하는 이유: hostname/OS는 이미 확실히 알아낸
    사실이라 sudo 성공 여부와 무관하게 바로 반영해야 한다 - sudo 단계에서 실패해도
    (예: 비밀번호 오류) hosts.ini는 이미 올바른 이름/그룹으로 남아 있어야 재시도가
    깔끔하다. 예전엔 순서가 반대라, sudo가 실패하면 hostname은 바뀌었는데 그룹은
    옛날 값(예: 실제론 Ubuntu인데 rocky)으로 남는 문제가 있었다.

    current_alias: 현재 hosts.ini/DB에 등록돼 있는 이 서버의 alias (등록 직후라면
                    보통 IP와 동일한 문자열 - add_server가 그렇게 등록한다). 접속에
                    쓸 IP는 hosts.ini의 ansible_host=로 이미 정해져 있으므로 따로
                    받지 않는다.

    실패하면 AnsibleError. 성공하면 {"hostname": ..., "os": ...} (inventory에
    최종 반영된 alias/OS 기준 - 호출자가 이 값으로 DB를 갱신해야 한다).
    """
    settings = conn_settings()

    # inventory에 이 alias 자체가 없으면 SSH를 시도할 것도 없다 - 같은 IP를
    # 다른 이름(예: rename_inventory_host로 hostname이 바뀐 뒤)으로 두 번 등록한
    # 중복 서버 항목일 가능성이 높다. 이 경우를 "SSH 접속 실패"로 뭉뚱그리면
    # 원인 파악이 안 되므로 먼저 구분해서 알려준다.
    if not _hostname_in_inventory(current_alias, settings):
        raise AnsibleError(
            f"'{current_alias}'이(가) inventory(hosts.ini)에 없습니다. 같은 IP를 다른 이름으로 "
            f"이미 등록한 중복 서버 항목일 수 있습니다 - 서버 목록에서 이 항목을 삭제하세요."
        )

    facts = gather_facts(current_alias, settings=settings)
    if not facts:
        raise AnsibleError("SSH 접속에 실패했습니다 - 키 교환이 되어 있는지 확인하세요 (README 참고).")

    alias = current_alias
    new_alias = facts["hostname"]
    if new_alias != current_alias:
        try:
            rename_inventory_host(current_alias, new_alias, settings)
            alias = new_alias
        except AnsibleError:
            pass  # 이미 같은 이름의 host가 등록돼 있음 - 기존 alias를 그대로 쓴다

    set_inventory_group(alias, facts["os"], settings)
    result = {"hostname": alias, "os": facts["os"], "detected_db": facts.get("detected_db", "")}

    try:
        setup_sudoers(alias, sudo_password, timeout=timeout, settings=settings)
    except AnsibleError as e:
        # hostname/OS/그룹은 이미 확정해서 반영했으니, 호출자(main.py)가 이 정보로
        # DB를 갱신할 수 있도록 facts를 실어서 다시 던진다 - sudo만 실패했다고
        # 화면에 여전히 IP/빈 OS로 남는 걸 막는다.
        raise ProvisionPartialError(str(e), result) from e

    return result


# 현재 실행 중인 전체 진단(run_scan)의 Popen 핸들. "중단" 버튼(abort_scan)이
# 이걸로 프로세스를 찾아서 죽인다. 한 번에 진단은 하나만 돌린다고 가정한다 -
# 이 앱에 별도의 스캔 작업 큐/ID 개념이 없어서, 그 이상은 과한 설계다.
_scan_lock = threading.Lock()
_scan_proc = None


def run_scan(hosts):
    global _scan_proc
    settings = conn_settings()
    limit = ",".join(hosts)
    args = ["-i", settings["inventory_arg"], "01_run_audit.yml"]
    if hosts:
        # localhost도 항상 포함: 리포트 생성/DB 저장(hosts: localhost) play가
        # --limit 대상에서 빠지면 통째로 스킵되기 때문.
        args += ["-l", f"{limit},localhost"]
    full_args = [settings["playbook_bin"]] + args + _extra_var_args(settings)

    # "중단" 버튼이 실제로 이 프로세스를 죽일 수 있어야 하므로, 다 끝날 때까지
    # 막고 기다리는 _run()/subprocess.run() 대신 Popen으로 직접 띄우고 핸들을
    # 전역에 보관한다. FastAPI가 sync 엔드포인트를 스레드풀에서 돌리므로, 이
    # 요청이 아래 communicate()에 블록돼 있는 동안에도 "중단" 요청은 다른
    # 스레드에서 별도로 들어와 처리된다.
    proc = subprocess.Popen(
        full_args,
        cwd=str(settings["ansible_dir"]),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    with _scan_lock:
        _scan_proc = proc

    try:
        try:
            stdout, stderr = proc.communicate(timeout=3600)
        except subprocess.TimeoutExpired:
            proc.kill()
            stdout, stderr = proc.communicate()
            return {
                "success": False,
                "output": f"진단이 1시간 내에 끝나지 않아 중단했습니다.\n{(stdout or '')[-4000:]}",
            }
    finally:
        with _scan_lock:
            if _scan_proc is proc:
                _scan_proc = None

    if proc.returncode < 0:
        # abort_scan()이 SIGTERM으로 죽였을 때 - subprocess 문서상 음수
        # returncode는 그 프로세스를 죽인 시그널 번호를 뜻한다.
        return {"success": False, "aborted": True, "output": "사용자가 진단을 중단했습니다."}

    return {
        "success": proc.returncode == 0,
        "output": (stdout + "\n" + stderr)[-8000:],
    }


def abort_scan():
    """현재 실행 중인 전체 진단을 중단시킨다.

    반환값은 "죽일 대상이 실제로 있었는지"이지 "진단이 이 호출로 끝났는지"가
    아니다 - 실제 종료/결과 반영은 run_scan()의 응답(위 aborted 필드)으로
    이뤄진다. 이미 끝났거나 애초에 실행 중인 진단이 없으면 False.
    """
    with _scan_lock:
        proc = _scan_proc
    if proc is None or proc.poll() is not None:
        return False
    proc.terminate()
    return True


def resolve_script_path(code, settings=None):
    """code(예: "U-01")에 대응하는 wrapper 스크립트를 찾는다.

    파일명 규칙은 <접두사 소문자><번호 2자리 이상>_<이름>.sh (예: u01_root_remote.sh)
    - 이 규칙만 지키면 접두사가 "U-"가 아니어도(예: 향후 DB 점검용 "D-01") 코드
    수정 없이 그대로 찾는다. code가 이 규칙과 안 맞으면(예: 접두사/번호 형식이
    아님) None을 반환한다."""
    settings = settings or conn_settings()
    m = re.match(r"^([A-Za-z]+)-(\d+)$", code)
    if not m:
        return None
    prefix, num = m.group(1).lower(), m.group(2).zfill(2)
    matches = glob.glob(str(settings["ansible_dir"] / "scripts" / "*" / f"{prefix}{num}_*.sh"))
    if not matches:
        return None
    return os.path.relpath(matches[0], str(settings["ansible_dir"] / "scripts"))


def _deploy_scripts(hostname, settings):
    fd, tar_path = tempfile.mkstemp(suffix=".tar.gz")
    os.close(fd)
    try:
        with tarfile.open(tar_path, "w:gz") as tar:
            tar.add(str(settings["ansible_dir"] / "scripts"), arcname=".")

        mkdir_args = [
            hostname, "-i", settings["inventory_arg"], "--become",
            "-m", "file", "-a", f"path={REMOTE_DIR} state=directory mode=0755",
        ]
        proc = _run(settings["ansible_bin"], mkdir_args, 30, settings, retries=1)
        if proc.returncode != 0:
            raise AnsibleError(f"remote dir create failed: {proc.stdout}\n{proc.stderr}")

        unarchive_args = [
            hostname, "-i", settings["inventory_arg"], "--become",
            "-m", "unarchive", "-a", f"src={tar_path} dest={REMOTE_DIR} mode=0755",
        ]
        proc = _run(settings["ansible_bin"], unarchive_args, 60, settings, retries=1)
        if proc.returncode != 0:
            raise AnsibleError(f"script deploy failed: {proc.stdout}\n{proc.stderr}")
    finally:
        os.remove(tar_path)


def _cleanup(hostname, settings):
    args = [
        hostname, "-i", settings["inventory_arg"], "--become",
        "-m", "file", "-a", f"path={REMOTE_DIR} state=absent",
    ]
    _run(settings["ansible_bin"], args, 30, settings, retries=1)


def _run_fix_script(hostname, relpath, settings):
    tree_dir = f"/tmp/remediate_out_{uuid.uuid4().hex}"
    os.makedirs(tree_dir, exist_ok=True)
    args = [
        hostname, "-i", settings["inventory_arg"], "--become",
        "--tree", tree_dir,
        "-m", "command", "-a", f"chdir={REMOTE_DIR} bash {relpath} fix",
    ]
    proc = _run(settings["ansible_bin"], args, 60, settings, retries=1)

    result_file = os.path.join(tree_dir, hostname)
    if not os.path.exists(result_file):
        raise AnsibleError(f"no ansible result: {proc.stdout}\n{proc.stderr}")

    with open(result_file, "r", encoding="utf-8") as f:
        raw = json.load(f)
    os.remove(result_file)
    os.rmdir(tree_dir)

    stdout = raw.get("stdout", "")
    lines = [ln for ln in stdout.strip().splitlines() if ln.strip()]
    for ln in reversed(lines):
        if ln.lstrip().startswith("{"):
            try:
                return json.loads(ln)
            except json.JSONDecodeError:
                return json.loads(_sanitize_json(ln))
    raise AnsibleError(f"no JSON line in script output: {raw}")


def remediate(hostname, codes):
    settings = conn_settings()
    _deploy_scripts(hostname, settings)
    results = []
    try:
        for code in codes:
            relpath = resolve_script_path(code, settings)
            if not relpath:
                results.append({"code": code, "success": False, "status": None, "error": "script not found"})
                continue
            try:
                parsed = _run_fix_script(hostname, relpath, settings)
                results.append({
                    "code": code,
                    "success": parsed.get("status") == "양호",
                    "status": parsed.get("status"),
                    "parsed": parsed,
                })
            except (AnsibleError, json.JSONDecodeError) as e:
                results.append({"code": code, "success": False, "status": None, "error": str(e)})
    finally:
        _cleanup(hostname, settings)
    return results


def get_online_ips(timeout=5):
    """Tailscale IPs currently reachable, per 'tailscale status --json'."""
    try:
        proc = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=timeout, check=True
        )
        data = json.loads(proc.stdout)
    except Exception:
        return None  # unknown: caller should not mark hosts offline on failure

    online_ips = set()
    self_peer = data.get("Self") or {}
    if self_peer.get("Online", True):
        online_ips.update(self_peer.get("TailscaleIPs") or [])
    for peer in (data.get("Peer") or {}).values():
        if peer.get("Online"):
            online_ips.update(peer.get("TailscaleIPs") or [])
    return online_ips
