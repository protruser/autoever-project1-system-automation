#!/usr/bin/env python3
"""
03_save_to_mysql.py - final_report.json 데이터를 파싱하여 MySQL DB로 적재하는 스크립트

사용법:
  python3 03_save_to_mysql.py [DB_NAME] [JSON_PATH]
  예: python3 03_save_to_mysql.py audit_autoever_2026 audit_reports/final_report.json
"""

import sys
import os
import json
from pathlib import Path
import pymysql

# 1. 상위 디렉터리의 .env 환경변수 로드
env_file = Path(__file__).resolve().parent.parent / ".env"
if env_file.exists():
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

def save_to_db(json_file_path, db_name):
    if not os.path.exists(json_file_path):
        print(f"[-] 에러: 진단 결과 파일({json_file_path})을 찾을 수 없습니다.")
        sys.exit(1)

    with open(json_file_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # DB 연결
    conn = pymysql.connect(
        host=os.getenv("AUDIT_DB_HOST", "localhost"),
        port=int(os.getenv("AUDIT_DB_PORT", 3306)),
        user=os.getenv("DB_APP_USER", "audit_user"),
        password=os.getenv("DB_APP_PASSWORD", ""),
        database=db_name,
        charset=os.getenv("AUDIT_DB_CHARSET", "utf8mb4"),
        cursorclass=pymysql.cursors.DictCursor
    )

    try:
        with conn.cursor() as cur:
            s = data["scan_info"]
            t = data["total_summary"]
            
            # 1. audit_scans (스캔 회차 메타데이터) 적재
            cur.execute("""
                INSERT INTO audit_scans (
                    scan_id, project_name, scan_date, auditor, 
                    total_hosts, average_security_score, total_grade
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE 
                    average_security_score = VALUES(average_security_score),
                    total_grade = VALUES(total_grade)
            """, (
                s["scan_id"], 
                s.get("project_name", "주요정보통신기반시설 시스템 취약점 진단"), 
                s["scan_date"], 
                s.get("auditor", "protruser"), 
                t["total_hosts"], 
                t["average_security_score"], 
                t["total_grade"]
            ))

            # 2. audit_hosts 및 audit_results 적재
            for h in data.get("hosts", []):
                hi = h["host_info"]
                hs = h["summary"]
                
                cur.execute("""
                    INSERT INTO audit_hosts (
                        scan_id, hostname, ip, os, kernel, arch, 
                        total_checks, pass_count, vuln_count, na_count, 
                        compliance_rate, max_score, deducted_score, 
                        security_score_100, grade
                    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, (
                    s["scan_id"], 
                    hi.get("hostname", "Unknown"), 
                    hi.get("ip", "0.0.0.0"), 
                    hi.get("os", "Linux"), 
                    hi.get("kernel", "-"), 
                    hi.get("arch", "x86_64"),
                    hs["total"], 
                    hs["pass"], 
                    hs["vuln"], 
                    hs["na"], 
                    hs["compliance_rate"], 
                    hs["max_score"], 
                    hs["deducted_score"], 
                    hs["security_score_100"], 
                    hs["grade"]
                ))
                host_id = cur.lastrowid

                # 3. 개별 점검 항목 결과 적재 (guide 컬럼 매핑)
                results = h.get("results", [])
                if results:
                    val_list = [
                        (
                            host_id, 
                            r.get("code"), 
                            r.get("category", "기타"), 
                            r.get("title", ""),
                            r.get("importance", "중"), 
                            r.get("weight_score", 10), 
                            r.get("risk_score", 0),
                            r.get("status"), 
                            r.get("target_file", "-"), 
                            r.get("command", ""),
                            r.get("command_output", ""), 
                            r.get("evidence_description", ""),
                            r.get("recommendation_text") or r.get("guide", ""),  # guide 컬럼으로 매핑
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
        print(f"[+] 성공: [{s['scan_id']}] 데이터가 DB `{db_name}`에 정상 저장되었습니다.")
    except Exception as e:
        conn.rollback()
        print(f"[-] DB 적재 실패: {e}")
        sys.exit(1)
    finally:
        conn.close()

if __name__ == "__main__":
    target_db = sys.argv[1] if len(sys.argv) > 1 else "audit_autoever_2026"
    json_path = sys.argv[2] if len(sys.argv) > 2 else "audit_reports/final_report.json"
    
    save_to_db(json_path, target_db)