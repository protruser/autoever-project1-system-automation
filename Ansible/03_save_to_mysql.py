#!/usr/bin/env python3
"""
03_save_to_mysql.py - final_report.json 데이터를 파싱하여 MySQL DB로 적재 (id 기반 외래키 매핑)
"""

import sys
import os
import json
from pathlib import Path
import pymysql

env_file = Path(__file__).resolve().parent.parent / ".env"
if env_file.exists():
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

def save_to_db(json_file_path, override_db_name=None):
    if not os.path.exists(json_file_path):
        print(f"[-] 에러: 진단 결과 파일({json_file_path})이 없습니다.")
        sys.exit(1)

    with open(json_file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    client_info = data.get("client_info", {})
    db_name = override_db_name or client_info.get("db_name") or os.getenv("AUDIT_DB_NAME", "audit_autoever_2026")

    conn = pymysql.connect(
        host=os.getenv("AUDIT_DB_HOST", "localhost"),
        port=int(os.getenv("AUDIT_DB_PORT", 3306)),
        user=os.getenv("DB_APP_USER", "audit_user"),
        password=os.getenv("DB_APP_PASSWORD", "UserStrongPass2026!"),
        database=db_name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with conn.cursor() as cur:
            s = data.get("scan_info", {})
            t = data.get("total_summary", {})
            scan_id = s.get("scan_id")

            # 새로 생기는 회차인지 미리 확인 (이전 회차 호스트를 이어받을지 판단하는 데 사용)
            cur.execute("SELECT id FROM audit_scans WHERE scan_id = %s", (scan_id,))
            is_new_scan = cur.fetchone() is None

            # 1. audit_scans 적재 (ON DUPLICATE KEY UPDATE)
            cur.execute("""
                INSERT INTO audit_scans (
                    scan_id, project_name, scan_date, auditor, consultant_comment,
                    total_hosts, total_checks, total_pass, total_vuln, total_na,
                    average_compliance_rate, average_security_score, average_security_ratio, total_grade
                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE
                    average_security_score = VALUES(average_security_score),
                    average_security_ratio = VALUES(average_security_ratio),
                    total_grade = VALUES(total_grade),
                    consultant_comment = VALUES(consultant_comment)
            """, (
                scan_id,
                s.get("project_name", "주요정보통신기반시설 시스템 취약점 진단"),
                s.get("scan_date"),
                s.get("auditor", "심수용, 김성진, 김하영, 정진우, 한주협"),
                s.get("consultant_comment", ""),
                t.get("total_hosts", 0),
                t.get("total_checks", 0),
                t.get("total_pass", 0),
                t.get("total_vuln", 0),
                t.get("total_na", 0),
                t.get("average_compliance_rate", "0.0%"),
                t.get("average_security_score", 0.0),
                t.get("average_security_ratio", 0.0),
                t.get("total_grade", "양호")
            ))

            # "초기 설정"이 감지한 DB 엔진 힌트(detected_db)는 스캔 자체가 다시
            # 알아내는 값이 아니라서, 아래 호스트별 DELETE+INSERT로 행을 새로
            # 만들면 그냥 빈 값으로 초기화돼버린다. 예전엔 이걸 audit_hosts의
            # "가장 최근 행"에서 이어받았는데, audit_hosts는 스캔마다 지우고
            # 다시 만드는 테이블이라 스캔 이력이 한 번만 끊겨도(예: 회차 데이터
            # 유실) 영구히 사라지는 문제가 실측됐다(autoever1 사례). 그래서
            # 스캔 회차와 완전히 무관하게 서버(IP)당 1행만 영구 보관하는
            # host_facts 테이블에서 이어받는다 - "초기 설정"을 다시 돌리면
            # 그때 새로 감지된 값으로 덮어써진다(backend/db.py::update_host_facts).
            # [MOD] PK를 hostname -> ip로 변경(IP는 등록 후 안 바뀐다는 전제) -
            # hostname은 provisioning으로 IP alias에서 실제 이름으로 바뀌어서,
            # hostname 기준으로는 같은 서버인데도 매번 새 행이 생겨 이력이
            # fragment된다(backend/db.py::ensure_host_facts_table 참고).
            # [MOD] COLLATE를 명시한다 - audit_hosts/audit_scans가 실제로
            # utf8mb4_0900_ai_ci로 생성돼 있어서(DB 기본 콜레이션인
            # utf8mb4_unicode_ci와 다름 - 실측 확인됨), 안 맞추면 ip/scan_id로
            # JOIN할 때 "Illegal mix of collations" 에러가 난다
            # (backend/db.py::ensure_host_facts_table와 반드시 동일하게 유지).
            cur.execute("""
                CREATE TABLE IF NOT EXISTS host_facts (
                    ip VARCHAR(45) PRIMARY KEY,
                    hostname VARCHAR(100),
                    os VARCHAR(100),
                    detected_db VARCHAR(50) NOT NULL DEFAULT '',
                    baseline_scan_id VARCHAR(50),
                    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
            """)

            # 2. audit_hosts 및 audit_results 적재
            current_hostnames = set()
            for h in data.get("hosts", []):
                hi = h.get("host_info", {})
                hs = h.get("summary", {})
                hostname = hi.get("hostname", "Unknown")
                ip = hi.get("ip", "0.0.0.0")
                current_hostnames.add(hostname)

                # host_facts는 ip 기준(등록 후 안 바뀐다는 전제)이라 ip로 조회한다.
                # ip가 미확인 기본값("0.0.0.0")일 때만 hostname으로 대체 조회.
                if ip and ip != "0.0.0.0":
                    cur.execute(
                        "SELECT detected_db FROM host_facts WHERE ip = %s",
                        (ip,)
                    )
                else:
                    cur.execute(
                        "SELECT detected_db FROM host_facts WHERE hostname = %s",
                        (hostname,)
                    )
                prev_detected = cur.fetchone()
                detected_db = prev_detected["detected_db"] if prev_detected else ""

                # 같은 회차(scan_id)에 이 호스트를 재진단한 경우, 기존 행을 지우고
                # 새로 넣는다 (audit_results는 FK ON DELETE CASCADE로 함께 삭제됨).
                # hostname뿐 아니라 ip도 같이 매칭한다 - 같은 물리 서버가 hosts.ini에
                # 등록 초기(원시 IP alias)와 초기 설정 후(실제 hostname alias) 두
                # 이름으로 각각 스캔된 적이 있으면, hostname만 보고 지우면 옛날
                # alias로 남은 행이 안 지워지고 그대로 중복으로 쌓인다(실측된 버그).
                # ip가 미확인 기본값("0.0.0.0")일 때는 서로 무관한 호스트까지
                # 잘못 지울 수 있어 hostname 매칭만 쓴다.
                if ip and ip != "0.0.0.0":
                    cur.execute(
                        "DELETE FROM audit_hosts WHERE scan_id = %s AND (hostname = %s OR ip = %s)",
                        (scan_id, hostname, ip)
                    )
                else:
                    cur.execute(
                        "DELETE FROM audit_hosts WHERE scan_id = %s AND hostname = %s",
                        (scan_id, hostname)
                    )

                cur.execute("""
                    INSERT INTO audit_hosts (
                        scan_id, hostname, ip, os, detected_db, pass_count, vuln_count, na_count,
                        security_score_100, grade, created_at
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    scan_id,
                    hostname,
                    ip,
                    hi.get("os", "Linux"),
                    detected_db,
                    hs.get("pass", 0),
                    hs.get("vuln", 0),
                    hs.get("na", 0),
                    hs.get("security_score_100", 0.0),
                    hs.get("grade", "양호"),
                    hs.get("last_diagnosed_at") or s.get("scan_date")
                ))
                # 삽입된 호스트의 id(PK) 추출
                host_id = cur.lastrowid

                results = h.get("results", [])
                if results:
                    val_list = []
                    for r in results:
                        code = r.get("code")
                        cmd_out = r.get("command_output", "")

                        # 사람이 예전에 이 "검토" 항목을 양호/취약으로 확정해둔
                        # 내역이 있으면, 이번 진단 근거(command_output)가 그때와
                        # 완전히 같을 때만 그 확정을 그대로 이어붙인다. 서버
                        # 상태가 바뀌어 근거가 달라졌으면 확정을 버리고 다시
                        # "검토"로 되돌려 사람이 재확인하게 한다.
                        #
                        # 확정은 "검토" 상태였던 항목에만 가능하다(API가 강제함:
                        # backend/main.py의 /api/manual-verdict). 그래서 이번
                        # 진단 결과가 "검토"가 아니면 확정값이 존재할 수 없는
                        # 게 확정이라 조회 자체를 건너뛴다 - 원래는 매 항목마다
                        # (호스트당 최대 80여 개) 무조건 조회했는데, 대부분
                        # 어차피 못 찾을 조회라 스캔마다 불필요한 DB 왕복이
                        # 많이 발생하고 있었다(실측 후 정리).
                        manual_verdict, manual_reason, manual_by, manual_at = "", None, None, None
                        if r.get("status") == "검토":
                            cur.execute(
                                """SELECT ar.manual_verdict, ar.manual_reason, ar.manual_by,
                                          ar.manual_at, ar.command_output
                                   FROM audit_results ar JOIN audit_hosts ah ON ah.id = ar.host_id
                                   WHERE ah.hostname = %s AND ar.code = %s AND ar.manual_verdict != ''
                                   ORDER BY ar.id DESC LIMIT 1""",
                                (hostname, code)
                            )
                            prev_manual = cur.fetchone()
                            if prev_manual and prev_manual["command_output"] == cmd_out:
                                manual_verdict = prev_manual["manual_verdict"]
                                manual_reason = prev_manual["manual_reason"]
                                manual_by = prev_manual["manual_by"]
                                manual_at = prev_manual["manual_at"]

                        val_list.append((
                            host_id,
                            code,
                            r.get("category", "기타"),
                            r.get("title", ""),
                            r.get("importance", "중"),
                            r.get("weight_score", 0),
                            r.get("risk_score", 0),
                            r.get("status"),
                            r.get("target_file", "-"),
                            r.get("command", ""),
                            cmd_out,
                            r.get("evidence_description", ""),
                            r.get("recommendation_text") or r.get("guide", ""),
                            r.get("remediation_cmd", ""),
                            r.get("ui_meta", {}).get("reviewed", False),
                            r.get("ui_meta", {}).get("fixed_by_user", False),
                            manual_verdict, manual_reason, manual_by, manual_at,
                        ))
                    cur.executemany("""
                        INSERT INTO audit_results (
                            host_id, code, category, title, importance,
                            weight_score, risk_score, status, target_file,
                            command, command_output, evidence_description,
                            recommendation_text, remediation_cmd, reviewed, fixed_by_user,
                            manual_verdict, manual_reason, manual_by, manual_at
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """, val_list)

            # 3. 새 회차라면, 이번 실행에서 진단되지 않은(오프라인 등) 호스트를
            #    직전 회차에서 그대로 이어받아 새 회차가 빈 상태로 시작하지 않게 한다.
            if is_new_scan:
                cur.execute(
                    """SELECT id FROM audit_scans WHERE scan_id != %s
                       ORDER BY id DESC LIMIT 1""",
                    (scan_id,)
                )
                prev = cur.fetchone()
                if prev:
                    cur.execute(
                        """SELECT ah.* FROM audit_hosts ah
                           JOIN audit_scans asx ON asx.scan_id = ah.scan_id
                           WHERE asx.id = %s""",
                        (prev["id"],)
                    )
                    prev_hosts = cur.fetchall()
                    for ph in prev_hosts:
                        if ph["hostname"] in current_hostnames:
                            continue

                        cur.execute("""
                            INSERT INTO audit_hosts (
                                scan_id, hostname, ip, os, detected_db, pass_count, vuln_count, na_count,
                                security_score_100, grade, created_at
                            ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                        """, (
                            scan_id, ph["hostname"], ph["ip"], ph["os"], ph.get("detected_db", ""),
                            ph["pass_count"], ph["vuln_count"], ph["na_count"],
                            ph["security_score_100"], ph["grade"], ph["created_at"]
                        ))
                        new_host_id = cur.lastrowid

                        cur.execute(
                            "SELECT * FROM audit_results WHERE host_id = %s",
                            (ph["id"],)
                        )
                        old_results = cur.fetchall()
                        if old_results:
                            # 이 호스트는 이번 회차에 재진단되지 않아 결과를 그대로
                            # 복사하는 것뿐이라, 진단 근거(command_output)도 안
                            # 바뀌었으니 manual_verdict 등도 조건 없이 그대로
                            # 이어붙인다(위 재진단 경로와 달리 "달라졌으면 되돌리기"
                            # 판단 자체가 필요 없음).
                            cur.executemany("""
                                INSERT INTO audit_results (
                                    host_id, code, category, title, importance,
                                    weight_score, risk_score, status, target_file,
                                    command, command_output, evidence_description,
                                    recommendation_text, remediation_cmd, reviewed, fixed_by_user,
                                    manual_verdict, manual_reason, manual_by, manual_at
                                ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                            """, [
                                (
                                    new_host_id, r["code"], r["category"], r["title"],
                                    r["importance"], r["weight_score"], r["risk_score"],
                                    r["status"], r["target_file"], r["command"],
                                    r["command_output"], r["evidence_description"],
                                    r["recommendation_text"], r["remediation_cmd"],
                                    r["reviewed"], r["fixed_by_user"],
                                    r.get("manual_verdict", ""), r.get("manual_reason"),
                                    r.get("manual_by"), r.get("manual_at"),
                                )
                                for r in old_results
                            ])

                    # 이어받은 호스트까지 반영해 total_hosts 재계산
                    cur.execute(
                        "UPDATE audit_scans SET total_hosts = "
                        "(SELECT COUNT(*) FROM audit_hosts WHERE scan_id = %s) "
                        "WHERE scan_id = %s",
                        (scan_id, scan_id)
                    )

        conn.commit()
        print(f"[+] 성공: [{scan_id}] 데이터가 DB `{db_name}`에 정상 저장되었습니다.")
    except Exception as e:
        conn.rollback()
        print(f"[-] DB 적재 실패: {e}")
        sys.exit(1)
    finally:
        conn.close()

if __name__ == "__main__":
    json_path = sys.argv[2] if len(sys.argv) > 2 else "audit_reports/report.json"
    target_db = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].endswith(".json") else None
    if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
        json_path = sys.argv[1]
        target_db = None
    save_to_db(json_path, target_db)
