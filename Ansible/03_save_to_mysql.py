#!/usr/bin/env python3
"""
03_save_to_mysql.py - 표준 JSON 데이터를 파싱하여 MySQL DB로 적재
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
        print(f"[-] 에러: 파일({json_file_path})을 찾을 수 없습니다.")
        sys.exit(1)

    with open(json_file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # 1. 대상 DB명 추출 (JSON 내부 client_info 우선)
    client_info = data.get("client_info", {})
    db_name = override_db_name or client_info.get("db_name") or os.getenv("AUDIT_DB_NAME", "audit_autoever_2026")

    conn = pymysql.connect(
        host=os.getenv("AUDIT_DB_HOST", "localhost"),
        port=int(os.getenv("AUDIT_DB_PORT", 3306)),
        user=os.getenv("DB_APP_USER", "audit_user"),
        password=os.getenv("DB_APP_PASSWORD", ""),
        database=db_name,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with conn.cursor() as cur:
            s = data.get("scan_info", {})
            t = data.get("total_summary", {})
            
            # 2. audit_scans 적재
            cur.execute("""
                INSERT INTO audit_scans (
                    scan_id, project_name, scan_date, auditor, 
                    total_hosts, average_security_score, total_grade
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE 
                    average_security_score = VALUES(average_security_score),
                    total_grade = VALUES(total_grade)
            """, (
                s.get("scan_id"), 
                s.get("project_name", "주요정보통신기반시설 시스템 취약점 진단"), 
                s.get("scan_date"), 
                s.get("auditor", "protruser"), 
                t.get("total_hosts", 0), 
                t.get("average_security_score", 0.0), 
                t.get("total_grade", "양호")
            ))

            # 3. audit_hosts 적재
            for h in data.get("hosts", []):
                hi = h.get("host_info", {})
                hs = h.get("summary", {})
                results = h.get("results", [])
                
                total_checks = len(results)
                valid_checks = total_checks - hs.get("na", 0)
                comp_rate = f"{(hs.get('pass', 0) / valid_checks * 100):.1f}%" if valid_checks > 0 else "100.0%"

                cur.execute("""
                    INSERT INTO audit_hosts (
                        scan_id, hostname, ip, os, kernel, arch, 
                        total_checks, pass_count, vuln_count, na_count, 
                        compliance_rate, max_score, deducted_score, 
                        security_score_100, grade
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    s.get("scan_id"), 
                    hi.get("hostname", "Unknown"), 
                    hi.get("ip", "0.0.0.0"), 
                    hi.get("os", "Linux"), 
                    hi.get("kernel", "-"), 
                    hi.get("arch", "x86_64"),
                    total_checks, 
                    hs.get("pass", 0), 
                    hs.get("vuln", 0), 
                    hs.get("na", 0), 
                    comp_rate, 
                    0, 
                    0, 
                    hs.get("security_score_100", 0.0), 
                    hs.get("grade", "양호")
                ))
                host_id = cur.lastrowid

                # 4. audit_results 적재 (recommendation_text 매핑)
                if results:
                    val_list = [
                        (
                            host_id, 
                            r.get("code"), 
                            r.get("category", "기타"), 
                            r.get("title", ""),
                            r.get("importance", "중"), 
                            r.get("weight_score", 0), 
                            r.get("risk_score", 0),
                            r.get("status"), 
                            r.get("target_file", "-"), 
                            r.get("command", ""),
                            r.get("command_output", ""), 
                            r.get("evidence_description", ""),
                            r.get("recommendation_text") or r.get("guide", ""),
                            r.get("remediation_cmd", "")
                        )
                        for r in results
                    ]
                    cur.executemany("""
                        INSERT INTO audit_results (
                            host_id, code, category, title, importance, 
                            weight_score, risk_score, status, target_file, 
                            command, command_output, evidence_description, 
                            guide, remediation_cmd
                        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                    """, val_list)

        conn.commit()
        print(f"[+] 성공: [{s.get('scan_id')}] 데이터가 DB `{db_name}`에 정상 저장되었습니다.")
    except Exception as e:
        conn.rollback()
        print(f"[-] DB 적재 실패: {e}")
        sys.exit(1)
    finally:
        conn.close()

if __name__ == "__main__":
    json_path = sys.argv[2] if len(sys.argv) > 2 else "audit_reports/final_report.json"
    target_db = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].endswith(".json") else None
    
    if len(sys.argv) > 1 and sys.argv[1].endswith(".json"):
        json_path = sys.argv[1]
        target_db = None

    save_to_db(json_path, target_db)
