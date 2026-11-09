"""Helper library for the DuuniCheck Robot Framework tests.

It does the things that are awkward in plain Robot syntax:
  * sends raw HTTP requests, the session tokens come from the signed-in browser (common.robot),
  * sends raw HTTP requests to the backend (malformed JSON, odd headers, multipart uploads),
  * signs Clerk/Svix webhook requests,
  * builds small valid and invalid test files in memory,
  * records TCP connections to a local port (proves that the backend never opens a link).

Secrets come from the gitignored .env file via config.py, never from the tests.
"""
import base64
import hashlib
import hmac
import io
import json
import struct
import time
import uuid
import zipfile

import requests

from config import as_bool, load_config

CLERK_API = 'https://api.clerk.com/v1'
MAX_RATE_LIMIT_WAIT = 16 * 60


class ApiResponse:
    """Small immutable view of an HTTP response, easy to read from Robot."""

    def __init__(self, response):
        self.status = response.status_code
        self.headers = response.headers  # case-insensitive
        self.content = response.content
        self.text = response.text
        try:
            self.json = response.json()
        except ValueError:
            self.json = None

    def header(self, name):
        return self.headers.get(name, '')

    def __repr__(self):
        return f'ApiResponse(status={self.status}, body={self.text[:200]!r})'


class DuuniCheckLibrary:
    ROBOT_LIBRARY_SCOPE = 'GLOBAL'

    def __init__(self):
        self._cfg = load_config()
        self._tokens = {}
        self._sessions = {}
        self._user_ids = {}
        self._fapi = None

    # ------------------------------------------------------------------
    # Configuration helpers
    # ------------------------------------------------------------------
    def require_config(self, *names):
        """Fails with a clear message when a required .env value is missing."""
        missing = [name for name in names if not self._cfg.get(name)]
        if missing:
            raise AssertionError(
                'Missing configuration in .env: ' + ', '.join(missing)
                + '. Copy .env.example to .env and fill in the values.')

    def _email(self, user):
        key = {'A': 'TEST_USER_A_EMAIL', 'B': 'TEST_USER_B_EMAIL'}.get(str(user).upper())
        if not key:
            raise AssertionError(f'Unknown test user {user!r}, use A or B.')
        self.require_config(key)
        return self._cfg[key]

    def _secret_key(self):
        self.require_config('CLERK_SECRET_KEY')
        key = self._cfg['CLERK_SECRET_KEY']
        if not key.startswith('sk_test_'):
            raise AssertionError(
                'CLERK_SECRET_KEY must be a Clerk DEVELOPMENT key (sk_test_...). '
                'The tests never run with a production key.')
        return key

    # ------------------------------------------------------------------
    # Clerk tokens
    # ------------------------------------------------------------------
    def _clerk(self, method, path, **kwargs):
        response = requests.request(
            method, CLERK_API + path, timeout=20,
            headers={'Authorization': f'Bearer {self._secret_key()}'}, **kwargs)
        if response.status_code >= 400:
            raise AssertionError(
                f'Clerk API {method} {path} failed with {response.status_code}: {response.text[:300]}')
        return response.json()

    def _lookup_user_id(self, user):
        if user not in self._user_ids:
            email = self._email(user)
            found = self._clerk('GET', '/users', params={'email_address': [email]})
            users = found if isinstance(found, list) else found.get('data', [])
            if not users:
                raise AssertionError(f'No Clerk user with email {email}. Create it in the Clerk dev dashboard.')
            self._user_ids[user] = users[0]['id']
        return self._user_ids[user]

    def get_backend_api_token(self, user):
        """Session JWT minted with the Backend API. It has NO "azp" claim, so a backend that
        sets authorizedParties must reject it (see TC02-016). Not used for normal requests."""
        user = str(user).upper()
        user_id = self._lookup_user_id(user)
        session = self._clerk('POST', '/sessions', json={'user_id': user_id})
        return self._clerk('POST', f'/sessions/{session["id"]}/tokens', json={})['jwt']

    # ------------------------------------------------------------------
    # HTTP
    # ------------------------------------------------------------------
    def send_request(self, method, path, json_body=None, raw_body=None, headers=None, form=None,
                     files=None, token=None, origin=None, params=None, timeout=60, absolute_url=False,
                     follow_redirects=True):
        """Sends ONE request to the backend and returns an ApiResponse (no retries).

        token        bearer token string; None sends no Authorization header, '' sends an empty one.
        json_body    Python object sent as JSON.
        raw_body     string/bytes sent exactly as given (for malformed JSON etc).
        form, files  multipart upload data.
        follow_redirects  False returns a 3xx response as it is (Location header readable).
        The Robot keyword "Api Request" in common.robot adds the player token and waits out 429.
        """
        url = path if as_bool(absolute_url) else self._cfg.get('API_URL', '').rstrip('/') + path
        if not url.startswith('http'):
            raise AssertionError('API_URL is not configured in .env')
        request_headers = dict(headers or {})
        if token is not None and token != '':
            request_headers['Authorization'] = f'Bearer {token}'
        elif token == '':
            request_headers['Authorization'] = 'Bearer '
        if origin:
            request_headers['Origin'] = origin
        kwargs = {'headers': request_headers, 'params': params, 'timeout': float(timeout),
                  'allow_redirects': as_bool(follow_redirects, True)}
        if json_body is not None:
            kwargs['data'] = json.dumps(json_body, ensure_ascii=False).encode('utf-8')
            request_headers.setdefault('Content-Type', 'application/json')
        elif raw_body is not None:
            kwargs['data'] = raw_body.encode('utf-8') if isinstance(raw_body, str) else raw_body
            request_headers.setdefault('Content-Type', 'application/json')
        if form is not None or files is not None:
            kwargs['data'] = form
            kwargs['files'] = files
        return ApiResponse(requests.request(str(method).upper(), url, **kwargs))

    def seconds_until_reset(self, response):
        """How long to wait after a 429 until the rate limit window has reset."""
        value = response.headers.get('Retry-After') if hasattr(response, 'headers') else None
        if value and str(value).isdigit():
            return min(int(value) + 2, MAX_RATE_LIMIT_WAIT)
        policy = response.header('RateLimit') if hasattr(response, 'header') else ''
        for part in policy.replace(';', ',').split(','):
            part = part.strip()
            if part.startswith('r='):
                digits = ''.join(ch for ch in part[2:] if ch.isdigit())
                if digits:
                    return min(int(digits) + 2, MAX_RATE_LIMIT_WAIT)
        return 60

    # ------------------------------------------------------------------
    # Webhook signing (Svix scheme used by Clerk)
    # ------------------------------------------------------------------
    def sign_webhook(self, body, secret=None, timestamp=None, message_id=None):
        """Returns the svix-* headers for the given body."""
        secret = secret if secret is not None else self._cfg.get('CLERK_WEBHOOK_SIGNING_SECRET', '')
        if not secret:
            raise AssertionError('CLERK_WEBHOOK_SIGNING_SECRET is not configured in .env')
        key = base64.b64decode(secret.split('_', 1)[1] if secret.startswith('whsec_') else secret)
        timestamp = str(int(timestamp if timestamp is not None else time.time()))
        message_id = message_id or f'msg_{uuid.uuid4().hex}'
        payload = body if isinstance(body, str) else body.decode('utf-8')
        signed = f'{message_id}.{timestamp}.{payload}'.encode('utf-8')
        signature = base64.b64encode(hmac.new(key, signed, hashlib.sha256).digest()).decode()
        return {'svix-id': message_id, 'svix-timestamp': timestamp, 'svix-signature': f'v1,{signature}',
                'Content-Type': 'application/json'}

    def random_webhook_secret(self):
        return 'whsec_' + base64.b64encode(uuid.uuid4().bytes + uuid.uuid4().bytes).decode()

    # ------------------------------------------------------------------
    # Test files
    # ------------------------------------------------------------------
    def make_pdf(self):
        return (b'%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
                b'2 0 obj<</Type/Pages/Count 0/Kids[]>>endobj\n'
                b'trailer<</Root 1 0 R>>\n%%EOF\n')

    def make_docx(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w') as archive:
            archive.writestr('[Content_Types].xml',
                             '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
            archive.writestr('word/document.xml', '<w:document xmlns:w="x"><w:body/></w:document>')
        return buffer.getvalue()

    def make_text(self, text='Robot test file'):
        return text.encode('utf-8')

    def make_bytes(self, size, filler=b'a'):
        return filler * int(size)

    def make_png(self, width=8, height=8):
        """Smallest valid PNG of the given size (single colour)."""
        import zlib

        def chunk(kind, data):
            body = kind + data
            return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body) & 0xffffffff)

        rows = b''.join(b'\x00' + b'\x20\x40\x80' * int(width) for _ in range(int(height)))
        return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', int(width), int(height), 8, 2, 0, 0, 0))
                + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))

    def png_data_uri(self, width=8, height=8):
        return 'data:image/png;base64,' + base64.b64encode(self.make_png(width, height)).decode()

    def png_size(self, content):
        """Returns 'WIDTHxHEIGHT' of PNG bytes, or '' when the bytes are not a PNG."""
        if content[:8] != b'\x89PNG\r\n\x1a\n':
            return ''
        width, height = struct.unpack('>II', content[16:24])
        return f'{width}x{height}'

    def write_test_file(self, path, content):
        """Writes bytes to disk (used for browser upload tests)."""
        import os
        os.makedirs(os.path.dirname(path) or '.', exist_ok=True)
        with open(path, 'wb') as handle:
            handle.write(content if isinstance(content, bytes) else content.encode('utf-8'))
        return path

    def forged_jwt(self, algorithm='none', subject='user_forged'):
        """Builds an unsigned or randomly signed JWT to test token verification."""
        def encode(obj):
            return base64.urlsafe_b64encode(json.dumps(obj).encode()).rstrip(b'=').decode()

        header = encode({'alg': algorithm, 'typ': 'JWT'})
        payload = encode({'sub': subject, 'iat': int(time.time()), 'exp': int(time.time()) + 600,
                          'iss': 'https://example.clerk.accounts.dev'})
        if algorithm == 'none':
            return f'{header}.{payload}.'
        signature = base64.urlsafe_b64encode(
            hmac.new(b'not-the-real-secret', f'{header}.{payload}'.encode(), hashlib.sha256).digest()).rstrip(b'=').decode()
        return f'{header}.{payload}.{signature}'

    def tamper_jwt(self, token):
        """Flips one character in the signature part of a real token."""
        head, payload, signature = token.split('.')
        flipped = ('A' if signature[5] != 'A' else 'B')
        return '.'.join([head, payload, signature[:5] + flipped + signature[6:]])

    # ------------------------------------------------------------------
    # Published .htaccess (Robot is never run against the production site)
    # ------------------------------------------------------------------
    @staticmethod
    def _htaccess_lines(content):
        """Directive lines without comments, blank lines and surrounding spaces."""
        return [line.strip() for line in content.splitlines() if line.strip() and not line.strip().startswith('#')]

    def htaccess_set_headers(self, content):
        """Returns {header name: value} of every 'Header [always] set|append NAME VALUE' directive."""
        import re
        import shlex
        headers = {}
        for line in self._htaccess_lines(content):
            if not re.match(r'(?i)^Header\s', line):
                continue
            parts = shlex.split(line, posix=True)
            if parts[1].lower() in ('always', 'onsuccess'):
                parts = parts[:1] + parts[2:]
            if len(parts) >= 4 and parts[1].lower() in ('set', 'append', 'add'):
                headers[parts[2]] = parts[3]
        return headers

    def forbidden_build_files(self, directory):
        """Returns the paths in a frontend build that must never be published: environment files
        (.env*), Git data (.git), package.json, vite.config.* and the src/ source folder."""
        import os
        found = []
        for root, dirs, files in os.walk(directory):
            for name in dirs + files:
                lower = name.lower()
                is_dir = name in dirs
                if lower.startswith('.env') or lower == '.git' or lower == 'package.json' \
                        or lower.startswith('vite.config.') or (is_dir and lower == 'src'):
                    found.append(os.path.relpath(os.path.join(root, name), directory).replace(os.sep, '/'))
        return sorted(found)

    # ------------------------------------------------------------------
    # Connection recorder (proves that the backend never opens a link)
    # ------------------------------------------------------------------
    def start_connection_recorder(self):
        """Listens on a free 127.0.0.1 port and counts every TCP connection to it.

        The backend runs on the same machine, so any attempt to fetch a link that points here
        (http or https, the TLS handshake also opens a connection) is counted. Returns the port.
        """
        import socket
        import threading

        self.stop_connection_recorder()
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(('127.0.0.1', 0))
        server.listen(16)
        server.settimeout(0.2)
        state = {'count': 0, 'running': True}

        def accept_loop():
            while state['running']:
                try:
                    connection, _ = server.accept()
                except OSError:
                    continue
                state['count'] += 1
                connection.close()

        thread = threading.Thread(target=accept_loop, daemon=True)
        thread.start()
        self._recorder = (server, state, thread)
        return server.getsockname()[1]

    def recorded_connection_count(self):
        """Number of connections the recorder has received since it was started."""
        recorder = getattr(self, '_recorder', None)
        if recorder is None:
            raise AssertionError('Start Connection Recorder must be called first.')
        return recorder[1]['count']

    def stop_connection_recorder(self):
        """Stops the recorder. Safe to call when none is running (teardown)."""
        recorder = getattr(self, '_recorder', None)
        if recorder is None:
            return
        server, state, thread = recorder
        state['running'] = False
        thread.join(2)
        server.close()
        self._recorder = None
