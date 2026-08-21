import glob
import json
import os
import re
import subprocess
import tarfile
import tempfile
import uuid
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


def run_scan(hosts):
    limit = ",".join(hosts)
    args = ["ansible-playbook", "-i", "hosts.ini", "01_run_audit.yml"]
    if hosts:
        args += ["-l", limit]
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
