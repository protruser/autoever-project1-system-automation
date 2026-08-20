import os
from pathlib import Path

ENV_PATH = Path(__file__).resolve().parent.parent / ".env"
if ENV_PATH.exists():
    with open(ENV_PATH, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

DB_HOST = os.getenv("AUDIT_DB_HOST", "localhost")
DB_PORT = int(os.getenv("AUDIT_DB_PORT", 3306))
DB_USER = os.getenv("DB_APP_USER", "audit_user")
DB_PASSWORD = os.getenv("DB_APP_PASSWORD", "")
DEFAULT_DB = os.getenv("AUDIT_DB_NAME", "audit_autoever_2026")
