import pymysql
from config import DB_HOST, DB_PORT, DB_USER, DB_PASSWORD

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
