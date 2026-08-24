import db as dbmod
import csv_builder
import docx_builder
import json_builder
import ansible_ops

import hashlib
import json
import secrets

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import BackgroundTasks, FastAPI, HTTPException, Response, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

STATUS_MAP = {"양호": "pass", "취약": "fail", "검토": "manual", "N/A": "warning"}
SEVERITY_MAP = {"상": "high", "중": "medium", "하": "low"}


def map_status(value):
    return STATUS_MAP.get(value, "manual")


def map_severity(value):
    return SEVERITY_MAP.get(value, "medium")

# =========================================================
# 로그인 세션 / API 인증
# =========================================================

def token_hash(token: str) -> str:
    """
    세션 토큰 원문을 DB 저장용 SHA-256 해시값으로 변환한다.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def current_user(
    authorization: Optional[str] = Header(default=None)
):
    """
    Authorization: Bearer <token> 헤더를 검증한다.

    유효한 세션이면 사용자 정보를 반환하고,
    토큰이 없거나 만료되었으면 HTTP 401을 반환한다.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="authentication required"
        )

    token = authorization[7:]
    user = dbmod.get_session_user(token_hash(token))

    if not user:
        raise HTTPException(
            status_code=401,
            detail="invalid or expired session"
        )

    return user


# =========================================================
# 인증 API
# =========================================================

@app.post("/api/auth/login")
def login(payload: dict):
    """
    관리자 로그인 API

    요청 예시:
    {
        "username": "admin",
        "password": "password"
    }
    """
    username = str(payload.get("username", ""))
    password = str(payload.get("password", ""))

    user = dbmod.find_user(username)

    if not user:
        raise HTTPException(
            status_code=401,
            detail="invalid username or password"
        )

    # 입력 비밀번호를 DB salt로 PBKDF2-SHA256 해싱한다.
    password_hash = hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        user["password_salt"].encode("utf-8"),
        100000
    ).hex()

    # timing attack 방지를 위해 안전한 비교 함수를 사용한다.
    if not secrets.compare_digest(
        password_hash,
        user["password_hash"]
    ):
        raise HTTPException(
            status_code=401,
            detail="invalid username or password"
        )

    # 로그인 성공: 난수 세션 토큰 생성
    token = secrets.token_urlsafe(32)

    # config.py에 추가한 세션 유지 시간을 불러온다.
    from config import SESSION_TTL_SECONDS

    expires_at = (
        datetime.now(timezone.utc)
        + timedelta(seconds=SESSION_TTL_SECONDS)
    )

    # DB에는 토큰 원문이 아닌 해시값만 저장한다.
    dbmod.create_session(
        user["id"],
        token_hash(token),
        expires_at
    )

    return {
        "accessToken": token,
        "username": user["username"],
        "expiresIn": SESSION_TTL_SECONDS
    }


@app.post("/api/auth/logout")
def logout(
    authorization: Optional[str] = Header(default=None)
):
    """
    현재 Authorization 토큰에 연결된 DB 세션을 삭제한다.
    """
    if authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
        dbmod.delete_session(token_hash(token))

    return {"ok": True}


# =========================================================
# 시스템 설정 API
# =========================================================

@app.get("/api/config")
def get_config(user=Depends(current_user)):
    """
    로그인한 관리자만 시스템 설정 JSON을 조회할 수 있다.
    """
    config_json = dbmod.get_app_config()

    if config_json is None:
        return {}

    # MySQL/PyMySQL 환경에 따라 JSON 컬럼이 str 또는 dict로 반환될 수 있다.
    if isinstance(config_json, str):
        return json.loads(config_json)

    return config_json


@app.put("/api/config")
def save_config(
    payload: dict,
    user=Depends(current_user)
):
    """
    로그인한 관리자만 시스템 설정 JSON 전체를 저장할 수 있다.
    """
    config_json = json.dumps(
        payload,
        ensure_ascii=False
    )

    dbmod.save_app_config(
        config_json,
        user["id"]
    )

    return {
        "ok": True,
        "config": payload
    }



@app.get("/api/companies")
def companies(user=Depends(current_user)):
    return dbmod.list_audit_databases()


@app.get("/api/scans")
def scans(db: str, user=Depends(current_user)):
    return dbmod.get_scans(db)


@app.get("/api/servers")
def servers(db: str, scan_id: str, user=Depends(current_user)):
    hosts = dbmod.get_hosts(db, scan_id)
    online_ips = ansible_ops.get_online_ips()
    out = []
    for h in hosts:
        if online_ips is None:
            status = "online"  # tailscale status unavailable: do not guess
        else:
            status = "online" if h["ip"] in online_ips else "offline"
        out.append({
            "id": str(h["id"]),
            "hostname": h["hostname"],
            "ip": h["ip"],
            "os": h["os"] or "",
            "group": "-",
            "status": status,
            "lastScan": h["created_at"].strftime("%Y-%m-%d %H:%M") if h["created_at"] else None,
            "totalChecks": h["pass_count"] + h["vuln_count"] + h["na_count"],
            "passCount": h["pass_count"],
            "failCount": h["vuln_count"],
            "warnCount": h["na_count"],
            "score": float(h["security_score_100"]),
        })
    return out


@app.delete("/api/servers/{host_id}")
def delete_server(host_id: int, db: str, user=Depends(current_user)):
    dbmod.delete_host(db, host_id)
    return {"ok": True}


class AddServerRequest(BaseModel):
    ip: str
    db: str
    scan_id: str


def _resolve_facts_and_update(db_name, host_id, ip):
    """등록 응답을 보낸 뒤 백그라운드에서 실행: gather_facts로 실제 hostname/OS를
    얻어지면 inventory alias(IP -> hostname)와 DB를 함께 갱신한다. 실패하면
    아무 것도 바꾸지 않고 조용히 끝난다 (hostname은 IP로 남는다)."""
    facts = ansible_ops.gather_facts(ip)
    if not facts:
        return
    try:
        ansible_ops.rename_inventory_host(ip, facts["hostname"])
    except ansible_ops.AnsibleError:
        return  # 이미 같은 이름의 host가 있는 등 — IP alias로 그대로 둔다
    dbmod.update_host_facts(db_name, host_id, facts["hostname"], facts["os"])


@app.post("/api/servers")
def add_server(req: AddServerRequest, background_tasks: BackgroundTasks, user=Depends(current_user)):
    # hostname/OS는 아직 모르므로 일단 IP를 hostname 자리에 써서 즉시 등록하고,
    # 실제 정보는 백그라운드에서 받아와 나중에 갱신한다 (등록 응답을 기다리게 하지 않음).
    try:
        ansible_ops.add_inventory_host(req.ip, req.ip, "")
    except ansible_ops.AnsibleError as e:
        raise HTTPException(400, str(e))
    host_id = dbmod.add_host_placeholder(req.db, req.scan_id, req.ip, req.ip, "")
    background_tasks.add_task(_resolve_facts_and_update, req.db, host_id, req.ip)
    return {"ok": True, "hostname": req.ip, "os": "", "pending": True}


@app.get("/api/results")
def results(db: str, host_id: int, user=Depends(current_user)):
    rows = dbmod.get_results(db, host_id)
    out = []
    for r in rows:
        out.append({
            "id": str(r["id"]),
            "code": r["code"],
            "category": r["category"],
            "title": r["title"],
            "description": r["evidence_description"] or "",
            "severity": map_severity(r["importance"]),
            "status": map_status(r["status"]),
            "details": r["command_output"] or "",
            "recommendation": r["recommendation_text"] or "",
            "remediationStatus": "completed" if r["fixed_by_user"] else "pending",
        })
    return out


@app.get("/api/report")
def report(db: str, scan_id: str, format: str, user=Depends(current_user)):
    data = dbmod.fetch_full_report_data(db, scan_id)
    if not data.get("scan"):
        raise HTTPException(404, "scan not found")

    if format == "json":
        content = json_builder.generate_json(data)
        media_type = "application/json"
        ext = "json"
    elif format == "csv":
        content = csv_builder.generate_csv(data["hosts"])
        media_type = "text/csv"
        ext = "csv"
    elif format == "docx":
        content = docx_builder.generate_docx(data)
        media_type = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        ext = "docx"
    else:
        raise HTTPException(400, "unsupported format")

    if isinstance(content, str):
        content = content.encode("utf-8")

    filename = f"{scan_id}.{ext}"
    return Response(
        content=content,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


class ScanRunRequest(BaseModel):
    hosts: list[str]


@app.post("/api/scan/run")
def scan_run(req: ScanRunRequest, user=Depends(current_user)):
    return ansible_ops.run_scan(req.hosts)


class RemediateRequest(BaseModel):
    db: str
    host_id: int
    hostname: str
    codes: list[str]


@app.post("/api/remediate")
def remediate(req: RemediateRequest, user=Depends(current_user)):
    results = ansible_ops.remediate(req.hostname, req.codes)
    for r in results:
        parsed = r.pop("parsed", None)
        if parsed:
            dbmod.apply_remediation_result(req.db, req.host_id, r["code"], parsed)
    dbmod.recompute_host_score(req.db, req.host_id)
    return results
