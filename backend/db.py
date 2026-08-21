import pymysql
from config import DB_HOST, DB_PORT, DB_USER, DB_PASSWORD

DEFAULT_IMPORTANCE_SCORES = {"상": 10, "중": 8, "하": 6}

def get_connection(db_name):
    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=db_name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor
    )

def list_audit_databases():
    conn = pymysql.connect(host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASSWORD, charset="utf8mb4")
    try:
        with conn.cursor() as cur:
            cur.execute("SHOW DATABASES LIKE 'audit_%'")
            return [row[0] for row in cur.fetchall()]
    finally:
        conn.close()

def get_scans(db_name):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_scans ORDER BY id DESC")
            return cur.fetchall()
    finally:
        conn.close()

def get_hosts(db_name, scan_id):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_hosts WHERE scan_id = %s ORDER BY id ASC", (scan_id,))
            return cur.fetchall()
    finally:
        conn.close()

def get_results(db_name, host_id):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_results WHERE host_id = %s ORDER BY code ASC", (host_id,))
            return cur.fetchall()
    finally:
        conn.close()

def fetch_full_report_data(db_name, scan_id):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_scans WHERE scan_id = %s", (scan_id,))
            scan = cur.fetchone()
            cur.execute("SELECT * FROM audit_hosts WHERE scan_id = %s", (scan_id,))
            hosts = cur.fetchall()
            for h in hosts:
                cur.execute("SELECT * FROM audit_results WHERE host_id = %s", (h["id"],))
                h["results"] = cur.fetchall()
            return {"scan": scan, "hosts": hosts}
    finally:
        conn.close()

def apply_remediation_result(db_name, host_id, code, parsed):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            status = parsed.get("status", "검토")
            cur.execute(
                """UPDATE audit_results SET
                    status = %s, target_file = %s, command = %s, command_output = %s,
                    evidence_description = %s, recommendation_text = %s, remediation_cmd = %s,
                    reviewed = 1, fixed_by_user = %s
                   WHERE host_id = %s AND code = %s""",
                (
                    status,
                    parsed.get("target_file", ""),
                    parsed.get("command", ""),
                    parsed.get("command_output", ""),
                    parsed.get("evidence_description", ""),
                    parsed.get("recommendation_text", ""),
                    parsed.get("remediation_cmd", ""),
                    status == "양호",
                    host_id,
                    code,
                )
            )
        conn.commit()
    finally:
        conn.close()

def recompute_host_score(db_name, host_id):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT status, importance, weight_score FROM audit_results WHERE host_id = %s", (host_id,))
            rows = cur.fetchall()

            pass_count = sum(1 for r in rows if r["status"] == "양호")
            vuln_count = sum(1 for r in rows if r["status"] == "취약")
            na_count = sum(1 for r in rows if r["status"] == "N/A")

            max_score = 0
            deducted_score = 0
            for r in rows:
                if r["status"] not in ("양호", "취약", "검토"):
                    continue
                weight = r["weight_score"] or DEFAULT_IMPORTANCE_SCORES.get(r["importance"], 8)
                max_score += weight
                if r["status"] == "취약":
                    deducted_score += weight

            sec_score = ((max_score - deducted_score) / max_score * 100) if max_score > 0 else 100.0
            ratio = sec_score / 100

            if ratio >= 0.91:
                grade = "우수"
            elif ratio >= 0.81:
                grade = "양호"
            elif ratio >= 0.71:
                grade = "보통"
            elif ratio >= 0.61:
                grade = "미흡"
            else:
                grade = "취약"

            cur.execute(
                """UPDATE audit_hosts SET
                    pass_count = %s, vuln_count = %s, na_count = %s,
                    security_score_100 = %s, grade = %s
                   WHERE id = %s""",
                (pass_count, vuln_count, na_count, round(sec_score, 2), grade, host_id)
            )
        conn.commit()
    finally:
        conn.close()
