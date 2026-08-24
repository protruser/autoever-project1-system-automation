import glob
import json
import os
import re
import shutil
import subprocess
import tarfile
import tempfile
import uuid
import time
from pathlib import Path

ANSIBLE_DIR = Path(__file__).resolve().parent.parent / "Ansible"
REMOTE_DIR = "/tmp/kisa_audit"

# ansible's become/stdout capture occasionally drops one backslash of a
# doubled escape (e.g. "\\s" -> "\s"), which is invalid JSON. Re-double any
# backslash not already forming a valid JSON escape before parsing.
_BAD_ESCAPE_RE = re.compile(r'\\(?!["\\/bfnrtu])')


def _sanitize_json(s):
    return _BAD_ESCAPE_RE.sub(r"\\\\", s)


class AnsibleError(Exception):
    pass


def _run(args, timeout):
    proc = subprocess.run(
        args,
        cwd=str(ANSIBLE_DIR),
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return proc


def _inventory_group(os_name):
    os_lower = (os_name or "").lower()
    if "ubuntu" in os_lower or "debian" in os_lower:
        return "ubuntu24"
    return "rocky9"


def add_inventory_host(hostname, ip, os_name):
    path = ANSIBLE_DIR / "hosts.ini"
    group = _inventory_group(os_name)
    header = f"[{group}]"
    lines = path.read_text(encoding="utf-8").splitlines()

    if any(line.split()[0] == hostname for line in lines if line.strip() and not line.strip().startswith(("#", "["))):
        raise AnsibleError(f"'{hostname}'은(는) 이미 inventory에 등록되어 있습니다.")

    for i, line in enumerate(lines):
        if line.strip() == header:
            lines.insert(i + 1, f"{hostname}\tansible_host={ip}")
            break
    else:
        raise AnsibleError(f"inventory에서 [{group}] 그룹을 찾을 수 없습니다.")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def rename_inventory_host(old_alias, new_alias):
    """IP를 임시 alias로 등록해둔 host를, 나중에 gather_facts로 알아낸 실제
    hostname으로 바꿔치기한다. ansible_host= 값(IP)은 그대로 둔다.

    remediate/scan 흐름이 DB의 hostname을 그대로 inventory alias로 사용하므로
    (main.py의 RemediateRequest.hostname 참고), 이 둘은 항상 같아야 한다 —
    DB 쪽 갱신은 호출자가 이 함수 성공 후에 맞춰 해야 한다.
    """
    if old_alias == new_alias:
        return
    path = ANSIBLE_DIR / "hosts.ini"
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


def gather_facts(ip, timeout=15):
    """IP만으로 SSH 접속해 실제 hostname/OS를 수집한다 (inventory 등록 전).

    성공하면 {"hostname": ..., "os": ...}, 접속 실패/타임아웃/미수집이면 None을
    반환한다 — 호출자는 None일 때 IP를 임시 hostname으로 폴백해야 한다.
    """
    tree_dir = tempfile.mkdtemp(prefix="facts_")
    try:
        args = [
            "ansible", "all", "-i", f"{ip},",
            "-u", "user",
            "-e", "ansible_become=false",
            "-T", "8",
            "-m", "setup",
            "-a", "filter=ansible_distribution,ansible_distribution_version,ansible_hostname",
            "--tree", tree_dir,
        ]
        try:
            _run(args, timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

        result_file = os.path.join(tree_dir, ip)
        if not os.path.exists(result_file):
            return None
        with open(result_file, "r", encoding="utf-8") as f:
            raw = json.load(f)

        facts = raw.get("ansible_facts") or {}
        hostname = facts.get("ansible_hostname")
        distro = facts.get("ansible_distribution")
        version = facts.get("ansible_distribution_version")
        if not hostname or not distro:
            return None
        return {"hostname": hostname, "os": f"{distro} {version}".strip()}
    finally:
        shutil.rmtree(tree_dir, ignore_errors=True)


def run_scan(hosts):
    limit = ",".join(hosts)
    args = ["ansible-playbook", "-i", "hosts.ini", "01_run_audit.yml"]
    if hosts:
        # localhost도 항상 포함: 리포트 생성/DB 저장(hosts: localhost) play가
        # --limit 대상에서 빠지면 통째로 스킵되기 때문.
        args += ["-l", f"{limit},localhost"]
    try:
        proc = _run(args, timeout=3600)
    except subprocess.TimeoutExpired as e:
        return {
            "success": False,
            "output": f"진단이 1시간 내에 끝나지 않아 중단했습니다.\n{(e.stdout or '')[-4000:]}",
        }
    return {
        "success": proc.returncode == 0,
        "output": (proc.stdout + "\n" + proc.stderr)[-8000:],
    }


def resolve_script_path(code):
    num = code.replace("U-", "").zfill(2)
    matches = glob.glob(str(ANSIBLE_DIR / "scripts" / "*" / f"u{num}_*.sh"))
    if not matches:
        return None
    return os.path.relpath(matches[0], str(ANSIBLE_DIR / "scripts"))


def _deploy_scripts(hostname):
    fd, tar_path = tempfile.mkstemp(suffix=".tar.gz")
    os.close(fd)
    try:
        with tarfile.open(tar_path, "w:gz") as tar:
            tar.add(str(ANSIBLE_DIR / "scripts"), arcname=".")

        mkdir_args = [
            "ansible", hostname, "-i", "hosts.ini", "--become",
            "-m", "file", "-a", f"path={REMOTE_DIR} state=directory mode=0755",
        ]
        proc = _run(mkdir_args, timeout=30)
        if proc.returncode != 0:
            raise AnsibleError(f"remote dir create failed: {proc.stdout}\n{proc.stderr}")

        unarchive_args = [
            "ansible", hostname, "-i", "hosts.ini", "--become",
            "-m", "unarchive", "-a", f"src={tar_path} dest={REMOTE_DIR} mode=0755",
        ]
        proc = _run(unarchive_args, timeout=60)
        if proc.returncode != 0:
            raise AnsibleError(f"script deploy failed: {proc.stdout}\n{proc.stderr}")
    finally:
        os.remove(tar_path)


def _cleanup(hostname):
    args = [
        "ansible", hostname, "-i", "hosts.ini", "--become",
        "-m", "file", "-a", f"path={REMOTE_DIR} state=absent",
    ]
    _run(args, timeout=30)


def _run_fix_script(hostname, relpath):
    tree_dir = f"/tmp/remediate_out_{uuid.uuid4().hex}"
    os.makedirs(tree_dir, exist_ok=True)
    args = [
        "ansible", hostname, "-i", "hosts.ini", "--become",
        "--tree", tree_dir,
        "-m", "command", "-a", f"chdir={REMOTE_DIR} bash {relpath} fix",
    ]
    proc = _run(args, timeout=60)

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
    _deploy_scripts(hostname)
    results = []
    try:
        for code in codes:
            relpath = resolve_script_path(code)
            if not relpath:
                results.append({"code": code, "success": False, "status": None, "error": "script not found"})
                continue
            try:
                parsed = _run_fix_script(hostname, relpath)
                results.append({
                    "code": code,
                    "success": parsed.get("status") == "양호",
                    "status": parsed.get("status"),
                    "parsed": parsed,
                })
            except (AnsibleError, json.JSONDecodeError) as e:
                results.append({"code": code, "success": False, "status": None, "error": str(e)})
    finally:
        _cleanup(hostname)
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
