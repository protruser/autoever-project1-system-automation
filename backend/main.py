import db as dbmod
import csv_builder
import docx_builder
import json_builder
import ansible_ops
import notify

import hashlib
import json
import secrets

from datetime import datetime, timedelta, timezone
from typing import Optional
from zoneinfo import ZoneInfo

from fastapi import FastAPI, HTTPException, Response, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI()
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.on_event("startup")
def _ensure_schema():
    """로그인 잠금/감사 로그에 쓰는 컬럼·테이블이 없으면 추가한다 (이미 있으면
    아무 것도 안 함) - 기존에 init_app_db.sql로 만들어 둔 DB도 재시작 한 번으로
    바로 반영된다."""
    dbmod.ensure_extended_schema()
    # 클라이언트별 audit_<name> DB마다 audit_hosts.detected_db,
    # audit_results.manual_verdict 등의 컬럼도 보정한다. 하나가 실패해도
    # (예: 스키마 권한 문제) 나머지 DB/앱 기동을 막지 않는다.
    for _db in dbmod.list_audit_databases():
        try:
            dbmod.ensure_hosts_extended_schema(_db)
        except Exception:
            pass
        try:
            dbmod.ensure_results_extended_schema(_db)
        except Exception:
            pass
        try:
            dbmod.ensure_host_facts_table(_db)
        except Exception:
            pass

STATUS_MAP = {"양호": "pass", "취약": "fail", "검토": "manual", "N/A": "warning"}
SEVERITY_MAP = {"상": "high", "중": "medium", "하": "low"}

# MySQL 서버(및 컨트롤 노드)의 시스템 타임존이 UTC라서 TIMESTAMP 컬럼(created_at 등)이
# UTC 벽시계 값으로 저장된다. 화면에 보여줄 때만 KST로 변환한다 - DB/서버 자체를
# KST로 바꾸지 않는 이유는, 로그인 세션 만료(UTC_TIMESTAMP() 기준)처럼 이미 UTC를
# 명시적으로 쓰는 로직과 꼬이지 않게 저장은 UTC로 유지하고 표시만 변환하기 위함이다.
KST = ZoneInfo("Asia/Seoul")


def to_kst_str(dt, fmt="%Y-%m-%d %H:%M"):
    """DB에서 읽은 naive datetime(실제로는 UTC 벽시계 값)을 KST 문자열로 변환한다."""
    if dt is None:
        return None
    return dt.replace(tzinfo=timezone.utc).astimezone(KST).strftime(fmt)


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

# 설정 페이지 "로그인 실패 5회 시 계정 잠금" 체크박스가 켜져 있을 때만 적용된다.
LOGIN_LOCKOUT_THRESHOLD = 5
LOGIN_LOCKOUT_MINUTES = 15


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

    lockout_enabled = bool((_app_config_dict().get("security") or {}).get("lockout", True))

    if lockout_enabled and dbmod.get_lock_status(username):
        raise HTTPException(
            status_code=423,
            detail=f"로그인 실패 횟수 초과로 계정이 잠겼습니다. {LOGIN_LOCKOUT_MINUTES}분 후 다시 시도하세요."
        )

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
        if lockout_enabled:
            dbmod.record_login_failure(username, LOGIN_LOCKOUT_THRESHOLD, LOGIN_LOCKOUT_MINUTES)
        raise HTTPException(
            status_code=401,
            detail="invalid username or password"
        )

    if lockout_enabled:
        dbmod.reset_login_failures(username)

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

def _app_config_dict():
    """app_config JSON을 dict로 읽는다. MySQL/PyMySQL 환경에 따라 JSON 컬럼이
    str 또는 dict로 반환될 수 있어 둘 다 처리한다. 로그인/조치 API가 설정값을
    (인증 없이, 요청 내부에서) 그대로 읽어야 해서 /api/config 엔드포인트와는
    별도로 둔다."""
    config_json = dbmod.get_app_config()
    if config_json is None:
        return {}
    if isinstance(config_json, str):
        return json.loads(config_json)
    return config_json


def _notify(trigger_key, text):
    """설정 페이지 "알림 트리거"에 trigger_key가 체크돼 있고 Slack Webhook URL이
    설정돼 있을 때만 Slack으로 메시지를 보낸다."""
    cfg = _app_config_dict()
    webhook = str(cfg.get("slackWebhook") or "").strip()
    triggers = cfg.get("triggers") or []
    if webhook and trigger_key in triggers:
        notify.send_slack(webhook, text)


@app.get("/api/config")
def get_config(user=Depends(current_user)):
    """
    로그인한 관리자만 시스템 설정 JSON을 조회할 수 있다.
    """
    return _app_config_dict()


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
        # "초기 설정" 없이 스캔만 돌아 DB의 os는 채워졌지만 hosts.ini 그룹은 그대로인
        # 서버를 여기서 자동으로 바로잡는다 - set_inventory_group은 이미 맞으면
        # 아무것도 안 하므로(파일 쓰기 없음) 매 조회마다 불러도 비용이 거의 없다.
        # hostname이 inventory에 없는 등으로 실패해도 목록 조회 자체는 막지 않는다.
        if h["os"]:
            try:
                ansible_ops.set_inventory_group(h["hostname"], h["os"])
            except ansible_ops.AnsibleError:
                pass
        out.append({
            "id": str(h["id"]),
            "hostname": h["hostname"],
            "ip": h["ip"],
            "os": h["os"] or "",
            "group": ansible_ops.inventory_group(h["os"]) if h["os"] else "미설정",
            # "초기 설정" 시점에 systemctl로 감지한 힌트일 뿐, 실제 진단(D-항목)이
            # 최종 확정 결과다 - 자세한 이유는 00_gather_facts.yml 상단 주석 참고.
            "detectedDb": h.get("detected_db") or "",
            "status": status,
            "lastScan": to_kst_str(h["created_at"]),
            "totalChecks": h["pass_count"] + h["vuln_count"] + h["na_count"],
            "passCount": h["pass_count"],
            "failCount": h["vuln_count"],
            "warnCount": h["na_count"],
            "score": float(h["security_score_100"]),
        })
    return out


@app.delete("/api/servers/{host_id}")
def delete_server(host_id: int, db: str, user=Depends(current_user)):
    # hosts.ini 정리는 최선 노력 - 실패해도(권한 문제 등) DB 삭제 자체는 막지 않는다.
    row = dbmod.get_host(db, host_id)
    if row:
        try:
            ansible_ops.remove_inventory_host(row["hostname"], row.get("ip"))
        except Exception:
            pass
    dbmod.delete_host(db, host_id)
    return {"ok": True}


class AddServerRequest(BaseModel):
    ip: str
    db: str
    scan_id: str


@app.post("/api/servers")
def add_server(req: AddServerRequest, user=Depends(current_user)):
    # hostname/OS/그룹은 아직 모르므로 일단 IP를 hostname 자리에 써서 즉시 등록만
    # 해둔다. 실제 정보 수집 + sudo 설정은 목록의 "초기 설정" 버튼(→ /api/servers/
    # {id}/provision)에서 관리자가 sudo 비밀번호를 입력해 처리한다.
    try:
        ansible_ops.add_inventory_host(req.ip, req.ip, "")
    except ansible_ops.AnsibleError as e:
        raise HTTPException(400, str(e))
    dbmod.add_host_placeholder(req.db, req.scan_id, req.ip, req.ip, "")
    return {"ok": True, "hostname": req.ip, "os": "", "pending": True}


class ProvisionRequest(BaseModel):
    db: str
    sudo_password: str


@app.post("/api/servers/{host_id}/provision")
def provision_server(host_id: int, req: ProvisionRequest, user=Depends(current_user)):
    """서버 목록의 "초기 설정" 버튼: 00_gather_facts.yml로 hostname/OS 수집 +
    00_setup_sudoers.yml로 NOPASSWD sudo 설정을 한 번에 실행한다. 접속 IP는
    hosts.ini에 이미 등록돼 있는 값을 그대로 쓴다. sudo_password는 이 요청 처리
    동안만 쓰이고 어디에도 저장되지 않는다 (ansible_ops.setup_sudoers가 임시
    파일로만 잠깐 넘기고 즉시 삭제)."""
    row = dbmod.get_host(req.db, host_id)
    if not row:
        raise HTTPException(404, "server not found")
    try:
        facts = ansible_ops.provision_host(row["hostname"], req.sudo_password)
    except ansible_ops.ProvisionPartialError as e:
        # hostname/OS/그룹은 이미 확정됐으니(hosts.ini에도 반영됨) sudo만
        # 실패했어도 화면에 최신 정보가 보이도록 DB는 갱신하고 에러는 그대로 알린다.
        dbmod.update_host_facts(req.db, host_id, e.facts["hostname"], e.facts["os"], e.facts.get("detected_db", ""))
        raise HTTPException(400, str(e))
    except ansible_ops.AnsibleError as e:
        raise HTTPException(400, str(e))
    dbmod.update_host_facts(req.db, host_id, facts["hostname"], facts["os"], facts.get("detected_db", ""))
    return {
        "ok": True,
        "hostname": facts["hostname"],
        "os": facts["os"],
        "group": ansible_ops.inventory_group(facts["os"]),
        "detectedDb": facts.get("detected_db", ""),
    }


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
            "manualVerdict": r.get("manual_verdict") or "",
            "manualReason": r.get("manual_reason") or "",
            "manualAt": to_kst_str(r.get("manual_at")) if r.get("manual_at") else None,
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
    elif format == "xlsx":
        # 순수 CSV는 파일 형식상 색을 넣을 수 없어서, 양호/취약/검토 색구분이 들어간
        # XLSX(csv_builder.generate_xlsx)로 대체했다 - 항목별 데이터 다운로드라는
        # 용도는 그대로고, 색상만 CSV/DOCX 보고서와 통일된다.
        scan_meta = data.get("scan") or {}
        content = csv_builder.generate_xlsx(data["hosts"], meta={
            "title": scan_meta.get("project_name"),
            "period": scan_meta.get("scan_date"),
        })
        media_type = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        ext = "xlsx"
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
    result = ansible_ops.run_scan(req.hosts)
    if not result.get("aborted"):
        status = "성공" if result.get("success") else "실패"
        _notify("scanComplete", f"[SecureAudit] 진단 완료 — 대상 {len(req.hosts)}대, 결과: {status}")
    return result


@app.post("/api/scan/abort")
def scan_abort(user=Depends(current_user)):
    """"중단" 버튼: 현재 실행 중인 진단을 종료시킨다. 실제 결과 반영은 진단을
    시작한 /api/scan/run 요청 쪽 응답(aborted: true)에서 이뤄진다."""
    aborted = ansible_ops.abort_scan()
    return {"ok": True, "aborted": aborted}


class RemediateRequest(BaseModel):
    db: str
    host_id: int
    hostname: str
    codes: list[str]


@app.post("/api/remediate")
def remediate(req: RemediateRequest, user=Depends(current_user)):
    # "취약(fail)" 상태인 코드, 그리고 "검토(manual)" 중 사람이 "취약"로
    # 확정(manual_verdict)해둔 코드만 실제로 조치 스크립트를 돌린다. 검토
    # 항목 대부분은 조치 스크립트 자체가 없는(fix_UXX가 빈 스텁) 수동 판단
    # 영역이라 스크립트를 돌려도 ansible_ops.remediate()가 "자동조치 불가"로
    # 되돌려줄 뿐 위험하지 않다 - 반면 U-58(SNMP)처럼 실제 조치가 있는 항목은
    # 사람이 "불필요한데 켜져 있다(취약)"고 확정한 순간 돌릴 수 있어야 한다.
    # "양호"로 확정된 검토 항목은 여전히 대상이 아니다. 프론트(RemediationPage)가
    # 이미 이 조건으로 선택을 막아두지만, 다른 클라이언트/직접 호출 경로로
    # 그 외 코드가 들어와도 여기서 한 번 더 막는다.
    results_rows = dbmod.get_results(req.db, req.host_id)
    current_status = {r["code"]: r["status"] for r in results_rows}
    manual_verdicts = {r["code"]: r.get("manual_verdict") for r in results_rows}
    fail_codes = [
        c for c in req.codes
        if current_status.get(c) == "취약" or (current_status.get(c) == "검토" and manual_verdicts.get(c) == "취약")
    ]
    skipped_codes = [c for c in req.codes if c not in fail_codes]

    # ansible_ops.remediate()는 스크립트 배포 단계(SSH 접속 등)에서 실패하면
    # AnsibleError를 던지는데, 이걸 그대로 두면 라우트 밖으로 새어나가 프론트에
    # 그냥 "500 실패"라는 의미 없는 메시지만 보이고(실측됨) 어느 항목이 왜
    # 실패했는지 알 수 없다. 개별 코드 실패(스크립트 실행 자체의 실패)와 같은
    # 형태(코드별 error 문자열)로 맞춰서, 선택했던 코드 전부를 실패로 채워
    # 로그 패널에 원인이 그대로 보이게 한다.
    try:
        results = ansible_ops.remediate(req.hostname, fail_codes) if fail_codes else []
    except ansible_ops.AnsibleError as e:
        results = [
            {"code": c, "success": False, "status": current_status.get(c), "error": f"조치 준비 실패(서버 접속 확인 필요): {e}"}
            for c in fail_codes
        ]
    for code in skipped_codes:
        results.append({
            "code": code,
            "success": False,
            "status": current_status.get(code),
            "error": "취약(fail) 상태이거나 '취약'으로 확정된 검토 항목이 아니라 조치 대상이 아닙니다.",
        })

    for r in results:
        parsed = r.pop("parsed", None)
        if parsed:
            dbmod.apply_remediation_result(req.db, req.host_id, r["code"], parsed)
    dbmod.recompute_host_score(req.db, req.host_id)

    # 설정 페이지 "감사 로그 저장" 체크박스가 켜져 있을 때만 조치 작업을 기록한다.
    audit_enabled = bool((_app_config_dict().get("security") or {}).get("auditLog", True))
    if audit_enabled:
        dbmod.write_audit_log(
            user["id"], "remediate", req.hostname,
            {
                "db": req.db,
                "host_id": req.host_id,
                "results": [{"code": r["code"], "success": r["success"]} for r in results],
            }
        )

    ok = sum(1 for r in results if r["success"])
    fail = len(results) - ok
    if fail == 0:
        _notify("remediationComplete", f"[SecureAudit] {req.hostname} 조치 완료 — {ok}건 성공")
    else:
        _notify("remediationFailed", f"[SecureAudit] {req.hostname} 조치 중 실패 — 성공 {ok}건 / 실패 {fail}건")

    return results


class ManualVerdictRequest(BaseModel):
    db: str
    host_id: int
    code: str
    verdict: str  # "양호" 또는 "취약"
    reason: str


@app.post("/api/manual-verdict")
def manual_verdict(req: ManualVerdictRequest, user=Depends(current_user)):
    """"검토(manual)" 상태 항목을 사람이 양호/취약으로 최종 확정한다. 자동
    진단이 판정을 못 낸 항목(status="검토")만 대상이다 - 이미 자동으로
    양호/취약이 확정된 항목까지 덮어써서 점수를 조작하는 경로로 쓰이지
    않게 막는다. 사유(reason)는 나중에 감사 시 "왜 이렇게 판단했는지"
    설명할 수 있어야 해서 필수로 받는다."""
    if req.verdict not in ("양호", "취약"):
        raise HTTPException(400, "verdict는 '양호' 또는 '취약'만 가능합니다.")
    if not req.reason or not req.reason.strip():
        raise HTTPException(400, "사유(reason)를 입력해야 합니다.")

    current_status = {r["code"]: r["status"] for r in dbmod.get_results(req.db, req.host_id)}
    if current_status.get(req.code) != "검토":
        raise HTTPException(400, "검토(manual) 상태인 항목만 확정할 수 있습니다.")

    reason = req.reason.strip()
    dbmod.set_manual_verdict(req.db, req.host_id, req.code, req.verdict, reason, user["id"])
    dbmod.recompute_host_score(req.db, req.host_id)

    audit_enabled = bool((_app_config_dict().get("security") or {}).get("auditLog", True))
    if audit_enabled:
        dbmod.write_audit_log(
            user["id"], "manual_verdict", req.code,
            {"db": req.db, "host_id": req.host_id, "code": req.code, "verdict": req.verdict, "reason": reason}
        )

    return {"ok": True}
