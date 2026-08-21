import db as dbmod
import csv_builder
import docx_builder
import json_builder
import ansible_ops

from fastapi import FastAPI, HTTPException, Response
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


@app.get("/api/companies")
def companies():
    return dbmod.list_audit_databases()


@app.get("/api/scans")
def scans(db: str):
    return dbmod.get_scans(db)


@app.get("/api/servers")
def servers(db: str, scan_id: str):
    hosts = dbmod.get_hosts(db, scan_id)
    out = []
    for h in hosts:
        out.append({
            "id": str(h["id"]),
            "hostname": h["hostname"],
            "ip": h["ip"],
            "os": h["os"] or "",
            "group": "-",
            "status": "online",
            "lastScan": h["created_at"].strftime("%Y-%m-%d %H:%M") if h["created_at"] else None,
            "totalChecks": h["pass_count"] + h["vuln_count"] + h["na_count"],
            "passCount": h["pass_count"],
            "failCount": h["vuln_count"],
            "warnCount": h["na_count"],
            "score": float(h["security_score_100"]),
        })
    return out


@app.get("/api/results")
def results(db: str, host_id: int):
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
def report(db: str, scan_id: str, format: str):
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
def scan_run(req: ScanRunRequest):
    return ansible_ops.run_scan(req.hosts)


class RemediateRequest(BaseModel):
    db: str
    host_id: int
    hostname: str
    codes: list[str]


@app.post("/api/remediate")
def remediate(req: RemediateRequest):
    results = ansible_ops.remediate(req.hostname, req.codes)
    for r in results:
        parsed = r.pop("parsed", None)
        if parsed:
            dbmod.apply_remediation_result(req.db, req.host_id, r["code"], parsed)
    dbmod.recompute_host_score(req.db, req.host_id)
    return results
