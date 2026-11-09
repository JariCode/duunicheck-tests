"""Reads the settings from the gitignored .env file (or real environment variables).

Every module level name below becomes a Robot variable, e.g. ${FRONTEND_URL}.
The run stops at once if a required value is missing, instead of running tests
with empty values.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'libraries'))
from config import as_bool, load_config  # noqa: E402

_cfg = load_config()

# Frontend (Vite dev server, or the production build) and backend addresses.
FRONTEND_URL = _cfg.get('FRONTEND_URL', '')
if FRONTEND_URL and not FRONTEND_URL.endswith('/'):
    FRONTEND_URL += '/'
API_URL = _cfg.get('API_URL', '').rstrip('/')
ALLOWED_ORIGIN = _cfg.get('ALLOWED_ORIGIN', '').rstrip('/')

# The two Clerk test users (created in the Clerk development dashboard) and the
# fixed verification code of +clerk_test addresses.
USER_A_EMAIL = _cfg.get('TEST_USER_A_EMAIL', '')
USER_A_PASSWORD = _cfg.get('TEST_USER_A_PASSWORD', '')
USER_B_EMAIL = _cfg.get('TEST_USER_B_EMAIL', '')
USER_B_PASSWORD = _cfg.get('TEST_USER_B_PASSWORD', '')
CLERK_CODE = _cfg.get('TEST_CLERK_CODE', '')

# Optional values. Tests that need them are skipped when they are empty.
CLERK_SECRET_KEY = _cfg.get('CLERK_SECRET_KEY', '')
WEBHOOK_SECRET = _cfg.get('CLERK_WEBHOOK_SIGNING_SECRET', '')
BACKEND_HAS_OPENAI_KEY = as_bool(_cfg.get('BACKEND_HAS_OPENAI_KEY'))
RUN_REAL_AI = as_bool(_cfg.get('RUN_REAL_AI'))
RUN_SLOW = as_bool(_cfg.get('RUN_SLOW'))
API_RATE_LIMIT = int(_cfg.get('API_RATE_LIMIT') or 120)
AUTO_WAIT_RATE_LIMIT = as_bool(_cfg.get('AUTO_WAIT_RATE_LIMIT'), True)

# Browser: chromium, firefox or webkit. HEADLESS=false shows the browser,
# SLOWMO slows down every action (seconds).
BROWSER = _cfg.get('BROWSER') or 'chromium'

# DuuniCheck application repository (APP_DIR in .env or the environment). The .htaccess and build tests
# read frontend/public/.htaccess from it, because Robot is never run against the production site.
APP_DIR = _cfg.get('APP_DIR', '')
HEADLESS = as_bool(_cfg.get('HEADLESS'), False)
SLOWMO = f"{float(_cfg.get('SLOWMO') or 0.5)}s"

_REQUIRED = {
    'FRONTEND_URL': FRONTEND_URL,
    'API_URL': API_URL,
    'TEST_USER_A_EMAIL': USER_A_EMAIL,
    'TEST_USER_A_PASSWORD': USER_A_PASSWORD,
    'TEST_USER_B_EMAIL': USER_B_EMAIL,
    'TEST_USER_B_PASSWORD': USER_B_PASSWORD,
    'TEST_CLERK_CODE': CLERK_CODE,
}
_MISSING = [name for name, value in _REQUIRED.items() if not value]
if _MISSING:
    raise RuntimeError('These values are missing from the .env file: ' + ', '.join(_MISSING))

if BROWSER not in ('chromium', 'firefox', 'webkit'):
    raise RuntimeError('BROWSER must be chromium, firefox or webkit')
