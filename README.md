# DuuniCheck Robot Framework tests

Automated tests for DuuniCheck, built like the Nimeoniter and Kreniter Mind test suites.
The browser tests use the app like a real user; the API tests send requests straight to the backend.
Both Clerk test users are signed in through the browser, and the API tests take their session tokens
from those sessions (`window.Clerk.session.getToken()`), exactly as the app does. All addresses,
accounts and keys come from the gitignored `.env`. The TC number of every test is in its `[Documentation]`.

## Test suites

| Suite | What is tested |
|---|---|
| 01_landing_legal_pwa | Landing page with its title and canonical link, sign-in dialog, legal modals and their posting, file import, delete and font texts, no job site named, small screens, PWA manifest and icons, self-hosted fonts, third-party requests, secrets in the build (browser) |
| 02_authentication_api | Every protected route needs a valid token; forged, tampered, expired and azp-less tokens are rejected |
| 03_applications_api | Applications: CRUD, validation (five statuses incl. Hyväksytty), limits, dates, ordering |
| 04_cvs_templates_api | CVs and cover-letter templates: CRUD, validation, limits |
| 05_files_api | File upload and download: types, magic bytes, sizes, names, limits, download headers |
| 06_conversations_assistant_api | Conversation history, local answers, AI endpoint checks, posting links are never fetched (internal and non-HTTPS links included), job posting parser (`parse-posting`): sign-in, validation, missing OpenAI key, nothing stored, real extraction and duplicate check (RUN_REAL_AI) |
| 07_settings_api | Theme setting, validation and per-user separation |
| 08_user_isolation_api | User B cannot read, change, delete or attach anything of user A |
| 09_injection_security_api | NoSQL operators, prototype pollution, script strings, malformed and oversized JSON, CRLF |
| 10_headers_cors_api | Security headers, CORS, preflight, error responses, headers and manifest MIME type in the published `frontend/public/.htaccess`, no sensitive files in a local frontend build, backend CSP, Permissions-Policy and no-store on every response, public addresses are not redirected to Clerk while signed-in routes still need a token, HSTS and CSP sources in the published `.htaccess`, `vite preview` sends the same headers and redirects the base path without a slash |
| 11_webhook_api | Clerk webhook signature checks and input validation |
| 12_ui_applications | Add, edit, change status, delete applications in the browser |
| 12b_account_deletion_api | The user.deleted webhook removes all data of that user and only that user's |
| 13_ui_materials_assistant | CV, template and file management, AI chat in the browser, posting draft option: locking of the context, error without OpenAI key, draft editing and saving, duplicate warning, small screens (parse-posting is mocked) |
| 14_ui_navigation_settings | Navigation, theme persistence, user menu, signing out |
| 15_ui_xss_security | Hostile strings stored through the API are rendered as text, no script runs |
| 16_ui_pages_details | Dashboard (accepted applications in every theme), status Hyväksytty in the form, list, filter and timeline, progress timeline, calendar, search and stage filter, application details and events, status side effects, form cancel and limits, mobile menu, browser back |
| 17_ui_materials_profile | CV editing with list chips and photo, template editing, deleting, file download and drop zone, AI chat context options, Clerk profile dialog and legal links in the user menu |
| 18_import_delete_api | File import (`import-applications`, `remap`): sign-in, extension and content checks, macros, size, empty files, zip bombs, encrypted files, character set, PDF scripts, Excel/CSV/Word/PDF/TXT reading and conversion, duplicates, 50 row and 500 application limits, hidden instructions; `bulk-delete` and `find-applications`: sign-in, validation, own data only, no widening by regex characters |
| 19_ui_import_delete | AI chat tool options and their locking, file import list and saving, undo import, delete search and confirmation, chat state across tabs, reload and sign-out, beforeunload warning, scrolling of long lists, privacy note, small screens (OpenAI answers mocked) |
| 99_rate_limits_api | API, upload and AI rate limits; the posting parser, the file import and the delete search share the AI limit, file imports count as uploads, bulk delete counts towards the API limit (needs the backend's ORIGINAL limits) |

## Folder structure

```
duunicheck-tests/
    resources/
        settings.py      reads the settings from the .env file
        common.robot     keywords shared by all suites (browser, sign-in, Api Request, payloads)
    libraries/
        DuuniCheckLibrary.py   raw HTTP requests, webhook signing, test files, forged tokens, connection recorder
        ImportTestFiles.py     generated import test files (xlsx, csv, docx, pdf, txt) from invented data
        network_mocks.js       Browser library extension: mocks API responses (Playwright page.route)
        config.py              .env reader
    tests/                 the test suites
    .env                   your own settings (not in Git)
    .env.example           template for .env
```

## Installation

```
pip install -r requirements.txt
rfbrowser init
```

(`python -m Browser.entry init` does the same.) Copy `.env.example` to `.env` and fill it in.
The tests stop at once if a required value is missing.

## Before running

1. **Clerk development instance.** Create two users in the Clerk dashboard (Users), emails with `+clerk_test`, and a password. Put them in `.env` as `TEST_USER_A_*` and `TEST_USER_B_*`.
2. **Clerk protections.** Switch off for the test run: Protect > Protections > "Challenge suspicious sign-ups" and "Require Device Intelligence checks" (check also Device Trust and Block email subaddresses).
3. **Test backend.** Use a test database. `ALLOWED_ORIGIN` of the backend must equal `ALLOWED_ORIGIN` in `.env`. Its Clerk keys must belong to the same Clerk instance as the users. Set `CLERK_WEBHOOK_SIGNING_SECRET` to the same value in the backend and in `.env`.
4. **Frontend.** `npm run dev` in the frontend folder (port 5173). Do not use `VITE_BASE_PATH=/duunicheck/` in the dev `.env`.
5. **Rate limits.** Start the backend with raised limits for the normal run, for example `RATE_LIMIT_API`, `RATE_LIMIT_WEBHOOK`, `RATE_LIMIT_UPLOAD` and `RATE_LIMIT_AI` set to 100000 (read by `backend/middleware/security.js`). Suite 99 needs the normal limits (120, 30 and 20), so start the backend without these variables for it.
6. **Restart the backend** before every full run, so the rate limit counters are reset.
7. **Application repository.** Set `APP_DIR` in `.env` (or as an environment variable) to the path of the DuuniCheck repository. The `htaccess` and `build` tests read it.

## Running the tests

Run from the root of the test folder. Settings in real environment variables override `.env`
(`libraries/config.py`), so a single run can change them without editing `.env`.

1. Backend with raised rate limits and the OpenAI key, frontend running. Every test except the rate-limit and
   no-key tests:

   ```
   python -m robot --exclude rate-limit --exclude no-openai-key tests
   ```

   Set `RUN_SLOW=true` to include the slow limit tests and `RUN_REAL_AI=true` to include the tests tagged `openai`
   (real, paid OpenAI calls).

2. Backend restarted with raised rate limits and `OPENAI_API_KEY` set to an empty string for that process (dotenv
   does not override an existing variable). The tests tagged `no-openai-key`:

   ```
   python -m robot --include no-openai-key --output output-nokey.xml --log log-nokey.html --report report-nokey.html tests
   ```

   with `BACKEND_HAS_OPENAI_KEY=false`.

3. Backend restarted with the normal rate limits. The rate-limit tests (suite 99):

   ```
   python -m robot --include rate-limit --output output-99.xml --log log-99.html --report report-99.html tests
   ```

One suite:

```
python -m robot tests/02_authentication_api.robot
```

Tags: `api`, `browser`, `security`, `rate-limit`, `slow`, `known-gap`, `openai`, `no-openai-key`, `htaccess`, `build`, `import`.

Robot is never run against the production site. The tests tagged `htaccess` (TC01-016, TC10-012, TC10-014,
TC10-015) read `frontend/public/.htaccess` from `APP_DIR`, and TC10-016 builds the frontend into the gitignored
`tmp/` folder (`npx vite build --outDir`, never `frontend/dist`) and checks that no sensitive file would be
published.

OpenAI settings in `.env`: `BACKEND_HAS_OPENAI_KEY=true` when the backend has any `OPENAI_API_KEY`. The tests also
probe the backend for free (`Backend Has OpenAI Key`: a valid `/suggest` body for a missing application gives 503
without a key and 404 with one, never reaching OpenAI). Tests that need the key but make no OpenAI call run when
either says there is a key. The tests tagged `no-openai-key` (TC06-014, TC06-015, TC13-011) need a backend without a
key and `BACKEND_HAS_OPENAI_KEY=false`; they fail with a clear message if the backend has a key after all, so a wrong
flag can never cause a paid call.
`RUN_REAL_AI=true` also runs the tests tagged `openai`, which make real, paid OpenAI calls (TC06-011, TC06-016..018,
TC18-011..013, TC18-015, TC18-016, TC18-018..020, TC18-030..032). The no-key tests also include TC18-021, TC18-029
and TC19-013.

Import test files: `libraries/ImportTestFiles.py` builds every file in code from invented data (no real job search
data is ever stored) and writes a copy to the gitignored `tmp/import-files/`. The spreadsheet conversion is checked
exactly with the remap route, which applies a given column mapping without OpenAI.

Job site names: TC01-027 and TC19-014 check that the legal texts and the UI contain no web address other than the
service's own, the data protection authority's and example.com. This public repository lists no job site name.

Network mocks: the Browser library has no request interception keyword, so `libraries/network_mocks.js`
(loaded with `jsextension` in common.robot) adds `Mock Json Response`, `Get Mocked Request Bodies` and
`Clear Mocked Responses`, plus `Start Recording Requests`, `Get Recorded Requests` and `Stop Recording Requests`,
which record real requests without changing them. Suites 13 and 19 use them to test the posting draft, import and
delete paths without OpenAI.

## Expected findings (`known-gap`)

- TC10-014: directory listing needs `Options -Indexes` in `frontend/public/.htaccess`.

## Not automated

Some things cannot be automated reliably: real mailbox codes, Google login, changing the real account password
or e-mail, account deletion in Clerk, printing to PDF, drag and drop, real devices and the production server.
DuuniCheck is invite-only, so the tests cannot create users; 12b sends the signed webhook directly instead.