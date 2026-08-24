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

def add_host_placeholder(db_name, scan_id, hostname, ip, os_name):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO audit_hosts (
                    scan_id, hostname, ip, os,
                    pass_count, vuln_count, na_count, security_score_100, grade
                ) VALUES (%s, %s, %s, %s, 0, 0, 0, 0, '미진단')""",
                (scan_id, hostname, ip, os_name)
            )
            host_id = cur.lastrowid
        conn.commit()
        return host_id
    finally:
        conn.close()


def update_host_facts(db_name, host_id, hostname, os_name):
    """등록 시점엔 몰랐던 hostname/OS를 백그라운드 수집 완료 후 반영한다."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE audit_hosts SET hostname = %s, os = %s WHERE id = %s",
                (hostname, os_name, host_id)
            )
        conn.commit()
    finally:
        conn.close()


def delete_host(db_name, host_id):
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM audit_hosts WHERE id = %s", (host_id,))
        conn.commit()
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


# =========================================================
# SecureAudit 애플리케이션 DB
# - 관리자 계정
# - 로그인 세션
# - 시스템 설정 JSON
# =========================================================

def get_app_connection():
    """
    로그인 및 시스템 설정 저장용 secureaudit_app DB 연결을 생성한다.
    기존 audit_* 진단 결과 DB 연결과 분리해서 관리한다.
    """
    from config import APP_DB

    return pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=APP_DB,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor
    )


def find_user(username):
    """
    로그인 아이디로 활성화된 관리자 계정을 조회한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    id,
                    username,
                    password_hash,
                    password_salt
                FROM users
                WHERE username = %s
                  AND active = 1
                """,
                (username,)
            )

            return cur.fetchone()

    finally:
        conn.close()


def create_session(user_id, token_hash, expires_at):
    """
    로그인 성공 후 세션 토큰의 해시값과 만료 시각을 저장한다.

    주의:
    - token 원문은 DB에 저장하지 않는다.
    - token_hash만 DB에 저장한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO auth_sessions (
                    user_id,
                    token_hash,
                    expires_at
                )
                VALUES (%s, %s, %s)
                """,
                (user_id, token_hash, expires_at)
            )

        conn.commit()

    finally:
        conn.close()


def get_session_user(token_hash):
    """
    전달받은 토큰 해시가 유효하고 만료되지 않았는지 검사한다.
    유효하다면 로그인한 사용자 정보를 반환한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT
                    u.id,
                    u.username
                FROM auth_sessions s
                INNER JOIN users u
                    ON s.user_id = u.id
                WHERE s.token_hash = %s
                  AND s.expires_at > UTC_TIMESTAMP()
                  AND u.active = 1
                """,
                (token_hash,)
            )

            return cur.fetchone()

    finally:
        conn.close()


def delete_session(token_hash):
    """
    로그아웃할 때 해당 세션을 DB에서 삭제한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                DELETE FROM auth_sessions
                WHERE token_hash = %s
                """,
                (token_hash,)
            )

        conn.commit()

    finally:
        conn.close()


def get_app_config():
    """
    시스템 공통 설정 JSON을 조회한다.
    app_config는 id=1 행 하나만 사용한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT config_json
                FROM app_config
                WHERE id = 1
                """
            )

            row = cur.fetchone()

            if row is None:
                return None

            return row["config_json"]

    finally:
        conn.close()


def save_app_config(config_json, user_id):
    """
    시스템 설정 JSON 전체를 저장한다.
    누가 설정을 수정했는지도 updated_by에 기록한다.
    """
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE app_config
                SET
                    config_json = %s,
                    updated_by = %s,
                    updated_at = NOW()
                WHERE id = 1
                """,
                (config_json, user_id)
            )

        conn.commit()

    finally:
        conn.close()
