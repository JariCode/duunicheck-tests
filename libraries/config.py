"""Reads the test configuration from the process environment and the gitignored .env file.

Real environment variables take priority over values in .env, so CI or a
one-off shell override never needs a file edit.
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _read_dotenv(path):
    values = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, _, value = line.partition('=')
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def load_config():
    values = _read_dotenv(ROOT / '.env')
    for key in list(values):
        if key in os.environ:
            values[key] = os.environ[key]
    for key in ('FRONTEND_URL', 'API_URL', 'ALLOWED_ORIGIN', 'CLERK_SECRET_KEY',
                'CLERK_WEBHOOK_SIGNING_SECRET', 'TEST_USER_A_EMAIL', 'TEST_USER_A_PASSWORD',
                'TEST_USER_B_EMAIL', 'TEST_USER_B_PASSWORD', 'TEST_CLERK_CODE',
                'BACKEND_HAS_OPENAI_KEY', 'RUN_REAL_AI', 'RUN_SLOW', 'APP_DIR',
                'API_RATE_LIMIT', 'AUTO_WAIT_RATE_LIMIT', 'HEADLESS', 'SLOWMO', 'BROWSER'):
        if key in os.environ:
            values[key] = os.environ[key]
    return values


def as_bool(value, default=False):
    if value is None or value == '':
        return default
    return str(value).strip().lower() in ('1', 'true', 'yes', 'on')
