#!/usr/bin/env python3
import sys
import os
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

def init_db(client_name):
    db_name = f"audit_{client_name.lower().replace('-', '_')}"
    sql_template_path = Path(__file__).resolve().parent / "schema_template.sql"
    
    with open(sql_template_path, "r", encoding="utf-8") as f:
        sql_script = f.read().replace("{DB_NAME}", db_name)

    conn = pymysql.connect(
        host=os.getenv("AUDIT_DB_HOST", "localhost"),
        port=int(os.getenv("AUDIT_DB_PORT", 3306)),
        user=os.getenv("DB_ROOT_USER", "root"),
        password=os.getenv("DB_ROOT_PASSWORD", ""),
        charset="utf8mb4"
    )
    try:
        with conn.cursor() as cur:
            for statement in sql_script.split(";"):
                stmt = statement.strip()
                if stmt:
                    cur.execute(stmt)
        conn.commit()
        print(f"[+] 성공: 고객사 데이터베이스 `{db_name}` 생성 완료")
    finally:
        conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("사용법: python3 init_project_db.py <고객사명>")
        sys.exit(1)
    init_db(sys.argv[1])
