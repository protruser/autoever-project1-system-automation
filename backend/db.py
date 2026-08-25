import json
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

def get_host(db_name, host_id):
    """host_id 하나만으로 서버 1행을 조회한다 (scan_id를 모르는 provision 호출용)."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM audit_hosts WHERE id = %s", (host_id,))
            return cur.fetchone()
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


def update_host_facts(db_name, host_id, hostname, os_name, detected_db=None):
    """등록 시점엔 몰랐던 hostname/OS를 백그라운드 수집 완료 후 반영한다.

    detected_db: "초기 설정"이 gather_facts로 감지한 DB 엔진 힌트("mysql"/
    "postgresql"/"mysql,postgresql"/""). None이면 이 값은 건드리지 않는다 -
    기존 호출부 중 이 정보가 없는 경로(예전 버전 호환)를 위한 안전장치."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            if detected_db is None:
                cur.execute(
                    "UPDATE audit_hosts SET hostname = %s, os = %s WHERE id = %s",
                    (hostname, os_name, host_id)
                )
            else:
                cur.execute(
                    "UPDATE audit_hosts SET hostname = %s, os = %s, detected_db = %s WHERE id = %s",
                    (hostname, os_name, detected_db, host_id)
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
            cur.execute(
                "SELECT status, importance, weight_score, manual_verdict FROM audit_results WHERE host_id = %s",
                (host_id,)
            )
            rows = cur.fetchall()

            # "검토(manual)" 항목을 사람이 양호/취약으로 확정(manual_verdict)해뒀으면
            # 점수·카운트 계산에서 원래 status 대신 그 확정값을 쓴다 - 진단이 직접
            # 낸 status 컬럼 자체는 그대로 두고(자동 진단 결과 기록은 보존), 점수
            # 산정에만 사람의 최종 판단을 반영한다.
            def eff_status(r):
                return r["manual_verdict"] or r["status"]

            pass_count = sum(1 for r in rows if eff_status(r) == "양호")
            vuln_count = sum(1 for r in rows if eff_status(r) == "취약")
            na_count = sum(1 for r in rows if eff_status(r) == "N/A")

            max_score = 0
            deducted_score = 0
            for r in rows:
                st = eff_status(r)
                if st not in ("양호", "취약", "검토"):
                    continue
                weight = r["weight_score"] or DEFAULT_IMPORTANCE_SCORES.get(r["importance"], 8)
                max_score += weight
                if st == "취약":
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


def set_manual_verdict(db_name, host_id, code, verdict, reason, user_id):
    """"검토(manual)" 항목을 사람이 양호/취약으로 확정한 결과를 기록한다.
    원래 check가 낸 status 컬럼은 건드리지 않는다(자동 진단 근거를 그대로
    보존) - 대신 manual_verdict/manual_reason/manual_by/manual_at에 확정
    내역을 별도로 남기고, recompute_host_score가 점수 계산 시에만 이 값을
    우선시한다."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE audit_results SET
                    manual_verdict = %s, manual_reason = %s, manual_by = %s, manual_at = NOW()
                   WHERE host_id = %s AND code = %s""",
                (verdict, reason, user_id, host_id, code)
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


# =========================================================
# 로그인 실패 잠금 (설정 페이지 "로그인 실패 5회 시 계정 잠금")
# =========================================================

def get_lock_status(username):
    """계정이 '지금' 잠겨 있는지 조회한다. 잠금 시각이 지났으면 자동으로 None
    (잠기지 않음)을 돌려준다 - 별도 해제 처리가 필요 없다."""
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT locked_until
                FROM users
                WHERE username = %s
                  AND locked_until IS NOT NULL
                  AND locked_until > UTC_TIMESTAMP()
                """,
                (username,)
            )

            return cur.fetchone()

    finally:
        conn.close()


def record_login_failure(username, lock_after, lock_minutes):
    """비밀번호 실패 1회를 누적하고, lock_after회에 도달하면 lock_minutes분간 잠근다."""
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users
                SET
                    failed_attempts = failed_attempts + 1,
                    locked_until = CASE
                        WHEN failed_attempts + 1 >= %s
                            THEN DATE_ADD(UTC_TIMESTAMP(), INTERVAL %s MINUTE)
                        ELSE locked_until
                    END
                WHERE username = %s
                """,
                (lock_after, lock_minutes, username)
            )

        conn.commit()

    finally:
        conn.close()


def reset_login_failures(username):
    """로그인 성공 시 실패 카운트/잠금을 초기화한다."""
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE users
                SET failed_attempts = 0, locked_until = NULL
                WHERE username = %s
                """,
                (username,)
            )

        conn.commit()

    finally:
        conn.close()


# =========================================================
# 감사 로그 (설정 페이지 "감사 로그 저장")
# =========================================================

def write_audit_log(user_id, action, target, detail):
    """조치 작업 1건을 감사 로그에 남긴다. detail은 JSON으로 직렬화해서 저장한다."""
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO audit_log (user_id, action, target, detail)
                VALUES (%s, %s, %s, %s)
                """,
                (
                    user_id,
                    action,
                    target,
                    json.dumps(detail, ensure_ascii=False) if detail is not None else None,
                )
            )

        conn.commit()

    finally:
        conn.close()


# =========================================================
# 스키마 자동 보정
# =========================================================

def ensure_extended_schema():
    """로그인 잠금 컬럼(users.failed_attempts/locked_until)과 audit_log 테이블이
    없으면 추가한다. 이미 init_app_db.sql로 만들어 둔 기존 DB에도, 이 함수가
    백엔드 기동 시마다 안전하게(이미 있으면 아무 것도 안 함) 적용된다."""
    conn = get_app_connection()

    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*) AS c
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'users'
                  AND COLUMN_NAME = 'failed_attempts'
                """
            )
            if cur.fetchone()["c"] == 0:
                cur.execute(
                    """
                    ALTER TABLE users
                    ADD COLUMN failed_attempts INT UNSIGNED NOT NULL DEFAULT 0,
                    ADD COLUMN locked_until DATETIME NULL
                    """
                )

            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS audit_log (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user_id BIGINT UNSIGNED NULL,
                    action VARCHAR(64) NOT NULL,
                    target VARCHAR(255) NULL,
                    detail JSON NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

                    CONSTRAINT fk_audit_log_user
                        FOREIGN KEY (user_id) REFERENCES users(id)
                        ON DELETE SET NULL,

                    INDEX idx_audit_log_created (created_at)
                )
                """
            )

        conn.commit()

    finally:
        conn.close()


def ensure_hosts_extended_schema(db_name):
    """audit_hosts.detected_db 컬럼이 없으면 추가한다 - "초기 설정"이 gather_facts로
    감지한 DB 엔진 힌트를 저장하는 컬럼. ensure_extended_schema()와 같은 패턴
    (이미 있으면 아무 것도 안 함, DB_APP_USER가 ALTER 권한을 가진 audit_<client>
    DB마다 백엔드 기동 시 호출된다)."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*) AS c
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'audit_hosts'
                  AND COLUMN_NAME = 'detected_db'
                """
            )
            if cur.fetchone()["c"] == 0:
                cur.execute(
                    "ALTER TABLE audit_hosts ADD COLUMN detected_db VARCHAR(50) NOT NULL DEFAULT ''"
                )
        conn.commit()
    finally:
        conn.close()


def ensure_results_extended_schema(db_name):
    """audit_results에 수동 검토 확정 컬럼(manual_verdict 등)이 없으면 추가한다.
    ensure_hosts_extended_schema()와 같은 패턴(이미 있으면 아무 것도 안 함)."""
    conn = get_connection(db_name)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT COUNT(*) AS c
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'audit_results'
                  AND COLUMN_NAME = 'manual_verdict'
                """
            )
            if cur.fetchone()["c"] == 0:
                cur.execute(
                    """
                    ALTER TABLE audit_results
                    ADD COLUMN manual_verdict VARCHAR(10) NOT NULL DEFAULT '',
                    ADD COLUMN manual_reason TEXT,
                    ADD COLUMN manual_by BIGINT UNSIGNED NULL,
                    ADD COLUMN manual_at DATETIME NULL
                    """
                )
        conn.commit()
    finally:
        conn.close()
