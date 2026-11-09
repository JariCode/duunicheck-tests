*** Settings ***
Documentation     Shared variables and keywords for the DuuniCheck tests.
...               The frontend and the backend must be running. Settings and credentials
...               come from the gitignored .env file (resources/settings.py). The backend is
...               tested directly over HTTP; the session tokens of the two Clerk test users
...               are taken from their signed-in browser sessions, exactly like the app does it
...               (window.Clerk.session.getToken()), so they carry the "azp" claim the backend requires.
# network_mocks.js adds the keywords Mock Json Response and Clear Mocked Responses (Playwright page.route).
Library           Browser    jsextension=${CURDIR}/../libraries/network_mocks.js
Library           Collections
Library           OperatingSystem
Library           String
Library           DateTime
Library           ../libraries/DuuniCheckLibrary.py
Variables         settings.py


*** Variables ***
# Prefix for every record the tests create, so leftovers are easy to recognise.
${PREFIX}                 ROBOT
# Browser context ids of the signed-in players (A and B), filled by Prepare Players.
&{CONTEXTS}
# A syntactically valid ObjectId that does not exist.
${MISSING_ID}             000000000000000000000000
${DIALOG}                 role=dialog
# The top bar of the workspace. It is rendered only for a signed-in user once the data has loaded,
# and it stays visible on every screen width (the sidebar links are hidden on phones).
${WORKSPACE}              css=.workspace .topbar
${NAV}                    css=nav[aria-label="Päänavigaatio"]
${NAV_TIMEOUT}            30s
# Files the UI tests write for browser uploads. The folder is gitignored, so the repository root stays clean.
${TEST_FILES}             ${OUTPUT DIR}${/}testfiles${/}generated
@{MOBILE_WIDTHS}          ${320}    ${360}    ${390}    ${768}
# Strings that must never appear in an error response (stack traces, database details, secrets).
@{LEAK_MARKERS}           MongoServerError    MongooseError    E11000    node_modules    at Object.    at async    ValidationError    StrictModeError    mongodb+srv    sk_test    sk_live    ECONNREFUSED
# Error messages of the AI assistant routes (backend/routes/assistant.js and middleware/security.js).
${POSTING_TEXT_REQUIRED_ERROR}    Liitä työpaikkailmoituksen teksti. Ilmoituksia ei haeta linkeistä automaattisesti.
${PARSE_POSTING_INVALID_ERROR}    Liitä ilmoituksen teksti (enintään 16 000 merkkiä) ja tarkista, että linkki on kelvollinen http- tai https-osoite.
${AI_NOT_CONFIGURED_ERROR}        AI-palvelua ei ole vielä määritetty.
${AI_LIMIT_ERROR}                 AI-pyyntöjen tuntikohtainen raja tuli vastaan.


*** Keywords ***
Require API Configuration
    [Documentation]    Fails early with a clear message when .env is incomplete.
    Require Config    API_URL    TEST_USER_A_EMAIL    TEST_USER_B_EMAIL

Require Frontend Configuration
    Require Config    FRONTEND_URL    TEST_USER_A_EMAIL

Status Should Be
    [Arguments]    ${response}    ${expected}
    Should Be Equal As Integers    ${response.status}    ${expected}
    ...    msg=Expected HTTP ${expected} but got ${response.status}: ${response.text}[:300]

Status Should Be One Of
    [Arguments]    ${response}    @{expected}
    ${status}=    Convert To String    ${response.status}
    ${allowed}=    Evaluate    [str(item) for item in $expected]
    Should Contain    ${allowed}    ${status}
    ...    msg=Expected one of ${expected} but got ${status}: ${response.text}[:300]

Error Response Should Be Safe
    [Documentation]    The body must be JSON with an "error" text and must not leak internals.
    [Arguments]    ${response}
    Should Not Be Equal    ${response.json}    ${None}    msg=Response is not JSON: ${response.text}
    Dictionary Should Contain Key    ${response.json}    error
    FOR    ${marker}    IN    @{LEAK_MARKERS}
        Should Not Contain    ${response.text}    ${marker}    msg=Response leaks internal detail "${marker}"
    END

Safe Error Should Be
    [Documentation]    The status and the exact "error" text must match, and the body must not leak internals.
    [Arguments]    ${response}    ${status}    ${message}
    Status Should Be    ${response}    ${status}
    Error Response Should Be Safe    ${response}
    Should Be Equal    ${response.json}[error]    ${message}

Require Backend Without OpenAI Key
    [Documentation]    Skips the test unless the backend really has no OPENAI_API_KEY. The .env flag alone is not
    ...    trusted, because a test that expects the "no key" answer would make a real, paid OpenAI call
    ...    when the flag is wrong. The probe is free: /api/assistant/suggest checks the key before it looks
    ...    up the application, so a valid body for a missing application gives 503 without a key and 404
    ...    with one, and never reaches OpenAI. Fails when the flag says no key but the backend has one.
    Skip If    ${BACKEND_HAS_OPENAI_KEY}    The backend has an OpenAI key; this test needs BACKEND_HAS_OPENAI_KEY=false.
    ${has_key}=    Backend Has OpenAI Key
    IF    ${has_key}    Fail    BACKEND_HAS_OPENAI_KEY=false, but the backend has an OPENAI_API_KEY (the key probe got 404, not 503). Start the backend with OPENAI_API_KEY set to an empty string for the no-openai-key tests.

Backend Has OpenAI Key
    [Documentation]    Free probe (no OpenAI call, see Require Backend Without OpenAI Key). Returns True when the
    ...    backend has an OPENAI_API_KEY, whatever the .env flag says.
    &{context}=    Create Dictionary    applicationId=${MISSING_ID}    includePosting=${False}    postingText=${EMPTY}
    ...    includeCv=${False}    includeTemplate=${False}    includeApplication=${False}    allowSuggestions=${True}
    &{body}=    Create Dictionary    message=Key probe    context=${context}
    ${probe}=    Api Request    POST    /api/assistant/suggest    user=A    json_body=${body}
    Status Should Be One Of    ${probe}    503    404
    RETURN    ${{ $probe.status == 404 }}

Published Htaccess
    [Documentation]    Returns the content of frontend/public/.htaccess of the application (APP_DIR), the file
    ...    that is published with the frontend. Robot is never run against the production site, so the
    ...    production headers and access rules are checked from this file.
    Require Config    APP_DIR
    ${path}=    Normalize Path    ${APP_DIR}${/}frontend${/}public${/}.htaccess
    File Should Exist    ${path}    msg=No .htaccess at ${path}. Set APP_DIR in .env to the path of the DuuniCheck repository.
    ${content}=    Get File    ${path}    encoding=UTF-8
    RETURN    ${content}

Htaccess Headers
    [Documentation]    Returns the headers the published .htaccess sets (Header set / always set), name -> value.
    ${content}=    Published Htaccess
    ${headers}=    Htaccess Set Headers    ${content}
    RETURN    ${headers}

Text Should Name No Job Site
    [Documentation]    The text must not name any job site by its web address: it may contain no web address
    ...    (domain) other than the service's own, the data protection authority's and example.com. E-mail
    ...    addresses are not counted. The repository is public, so no job site name is listed here.
    [Arguments]    ${text}    ${where}
    ${domains}=    Evaluate
    ...    sorted(set(m.lower() for m in re.findall(r'(?<![@\\w.-])(?:[a-z0-9-]+\\.)+(?:fi|com|net|org|io|eu|se|jobs|app|dev|info)\\b', $text, re.I)) - {'jaricode.fi', 'tietosuoja.fi', 'example.com', 'duunicheck.onrender.com'})
    ...    modules=re
    Should Be Empty    ${domains}    msg=${where} names web addresses: ${domains}

Application Count Of
    [Documentation]    Returns the number of applications the given player has.
    [Arguments]    ${user}
    ${list}=    Api Request    GET    /api/applications    user=${user}
    Status Should Be    ${list}    200
    ${count}=    Get Length    ${list.json}
    RETURN    ${count}

Response Should Not Contain Internal Fields
    [Documentation]    userId, _id and Mongo internals must never reach the client.
    [Arguments]    ${response}
    Should Not Contain    ${response.text}    "userId"
    Should Not Contain    ${response.text}    "_id"
    Should Not Contain    ${response.text}    "__v"

Unique Name
    [Arguments]    ${label}=item
    ${suffix}=    Generate Random String    8    [LOWER][NUMBERS]
    RETURN    ${PREFIX}-${label}-${suffix}

Application Payload
    [Documentation]    Valid minimal application body. Extra keys can be added or overridden.
    [Arguments]    &{overrides}
    ${company}=    Unique Name    company
    &{payload}=    Create Dictionary    company=${company}    role=${PREFIX} Tester    status=Kiinnostava
    FOR    ${key}    ${value}    IN    &{overrides}
        Set To Dictionary    ${payload}    ${key}=${value}
    END
    RETURN    ${payload}

Cv Payload
    [Arguments]    &{overrides}
    ${name}=    Unique Name    cv
    &{payload}=    Create Dictionary    name=${name}    fullName=${PREFIX} Tester
    FOR    ${key}    ${value}    IN    &{overrides}
        Set To Dictionary    ${payload}    ${key}=${value}
    END
    RETURN    ${payload}

Template Payload
    [Arguments]    &{overrides}
    ${name}=    Unique Name    template
    &{payload}=    Create Dictionary    name=${name}    body=Hei, haen tehtävää.
    FOR    ${key}    ${value}    IN    &{overrides}
        Set To Dictionary    ${payload}    ${key}=${value}
    END
    RETURN    ${payload}

Create Application As
    [Arguments]    ${user}    &{overrides}
    ${payload}=    Application Payload    &{overrides}
    ${response}=    Api Request    POST    /api/applications    user=${user}    json_body=${payload}
    Status Should Be    ${response}    201
    RETURN    ${response.json}

Create Cv As
    [Arguments]    ${user}    &{overrides}
    ${payload}=    Cv Payload    &{overrides}
    ${response}=    Api Request    POST    /api/cvs    user=${user}    json_body=${payload}
    Status Should Be    ${response}    201
    RETURN    ${response.json}

Create Template As
    [Arguments]    ${user}    &{overrides}
    ${payload}=    Template Payload    &{overrides}
    ${response}=    Api Request    POST    /api/templates    user=${user}    json_body=${payload}
    Status Should Be    ${response}    201
    RETURN    ${response.json}

Upload Text File As
    [Arguments]    ${user}    ${category}=cv    ${filename}=${PREFIX}-note.txt    ${text}=Robot test file
    ${content}=    Make Text    ${text}
    ${response}=    Upload File    ${user}    ${category}    ${filename}    ${content}    text/plain
    Status Should Be    ${response}    201
    RETURN    ${response.json}

Ids Of
    [Documentation]    Returns the list of ids in a JSON list response.
    [Arguments]    ${response}
    ${ids}=    Evaluate    [item['id'] for item in $response.json]
    RETURN    ${ids}

Upload File
    [Documentation]    Multipart upload to POST /api/files as the given player.
    [Arguments]    ${user}    ${category}    ${filename}    ${content}    ${content_type}=application/octet-stream
    ...    ${token}=${None}    ${retry_429}=${True}
    ${bytes}=    Evaluate    $content.encode('utf-8') if isinstance($content, str) else $content
    ${files}=    Evaluate    {'file': ($filename, $bytes, $content_type)}
    ${form}=    Evaluate    {} if $category is None else {'category': $category}
    ${response}=    Api Request    POST    /api/files    user=${user}    token=${token}    form=${form}
    ...    files=${files}    retry_429=${retry_429}
    RETURN    ${response}

Clean Up Test Users
    [Documentation]    Deletes all data of both test users. Used in Suite Setup and Suite Teardown.
    Delete All Data    A
    Delete All Data    B

Clean Up User A
    Delete All Data    A

Delete All Data
    [Documentation]    Removes every application, CV, template and file of a test player
    ...    and resets the theme. Cleanup helper, uses the player's own token.
    [Arguments]    ${user}
    FOR    ${path}    IN    /api/applications    /api/cvs    /api/templates    /api/files
        ${listing}=    Api Request    GET    ${path}    user=${user}
        Should Be Equal As Integers    ${listing.status}    200
        ...    msg=Cleanup could not list ${path}: ${listing.status} ${listing.text}[:200]
        FOR    ${item}    IN    @{listing.json}
            Api Request    DELETE    ${path}/${item}[id]    user=${user}
        END
    END
    Api Request    PUT    /api/settings    user=${user}    json_body=${{ {'theme': 'default'} }}

Prepare API Suite
    [Documentation]    Suite Setup of the API suites: starts the browser, signs both players in
    ...    (their browser sessions give the API tokens) and clears their data.
    Require API Configuration
    Prepare Players    A    B
    Clean Up Test Users

Finish API Suite
    [Documentation]    Suite Teardown of the API suites: clears the data and closes the browser.
    Run Keyword And Ignore Error    Clean Up Test Users
    Run Keyword And Ignore Error    Close Browser    ALL


# ---------------------------------------------------------------------
# Browser sessions and sign-in
# ---------------------------------------------------------------------
Open Test Browser
    [Documentation]    Starts the browser. Run once at the start of a suite. Engine (BROWSER),
    ...    visibility (HEADLESS) and slow-down (SLOWMO) come from the .env file.
    New Browser    ${BROWSER}    headless=${HEADLESS}    slowMo=${SLOWMO}
    Set Browser Timeout    30s

Open New Session
    [Documentation]    Opens a clean browser session with no earlier sign-ins and loads the
    ...    landing page. Run at the start of every test that needs a clean session.
    [Arguments]    ${width}=1280    ${height}=900
    New Context    viewport={'width': ${width}, 'height': ${height}}    locale=fi-FI
    New Page    ${FRONTEND_URL}

Open Mobile Session
    [Documentation]    Opens a clean browser session that emulates a phone of the given width:
    ...    touch input and overlay scrollbars that take no layout space, as on real phones.
    ...    A desktop window narrowed to 320 px would reserve ~10 px for a classic scrollbar,
    ...    which no phone does.
    [Arguments]    ${width}    ${height}=800
    New Context    viewport={'width': ${width}, 'height': ${height}}    locale=fi-FI    isMobile=${True}    hasTouch=${True}
    New Page    ${FRONTEND_URL}

Open Mobile Workspace
    [Documentation]    Opens the active player's workspace in a new session that emulates a phone
    ...    (see Open Mobile Session). The sign-in is copied from the active session's cookies and
    ...    storage, so Clerk is not asked again. The state file holds session cookies, so it is
    ...    deleted at once. Close the session with Close Mobile Workspace.
    [Arguments]    ${width}    ${height}=800
    ${state}=    Save Storage State
    ${context}=    New Context    viewport={'width': ${width}, 'height': ${height}}    locale=fi-FI
    ...    isMobile=${True}    hasTouch=${True}    storageState=${state}
    Remove File    ${state}
    Set Test Variable    ${MOBILE_CONTEXT}    ${context}
    New Page    ${FRONTEND_URL}
    Wait For Workspace

Close Mobile Workspace
    [Documentation]    Closes the phone session of Open Mobile Workspace, if one is open, and returns
    ...    to the given player's own session. Safe to use in a teardown.
    [Arguments]    ${player}=A
    ${context}=    Get Variable Value    ${MOBILE_CONTEXT}    ${None}
    IF    $context is not None
        Switch Context    ${context}
        Close Context
        Set Test Variable    ${MOBILE_CONTEXT}    ${None}
    END
    Switch To Player    ${player}

Close Session
    [Documentation]    Closes the test's browser session.
    Close Context

Open Landing Page
    Go To    ${FRONTEND_URL}
    Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible

Open Sign In
    [Documentation]    Opens Clerk's sign-in dialog from the landing page button.
    Open Landing Page
    Click    text=Avaa DuuniCheck >> nth=0
    Wait For Elements State    input[name="identifier"]    visible    timeout=15s

Open Login Dialog
    Open Landing Page
    Click    text=Avaa DuuniCheck >> nth=0
    Wait For Elements State    css=[aria-label="DuuniCheckin kirjautuminen ja tilin luonti"]    visible

Wait For Workspace
    [Documentation]    Waits until the signed-in user's workspace is shown. The top bar is used
    ...    because the sidebar links are hidden behind the menu button on narrow screens.
    Wait For Elements State    ${WORKSPACE}    visible    timeout=45s

Return To Clean Workspace
    [Documentation]    Test Setup of the signed-in UI suites. Resets the viewport and opens the
    ...    overview from a clean URL, so a form, dialog, Clerk popup or mobile menu that an
    ...    earlier failed test left open cannot block the next test. The URL keeps the open
    ...    form and details (?form=, ?details=), so a plain reload is not enough.
    Set Viewport Size    1280    900
    Go To    ${FRONTEND_URL}
    Wait For Workspace

Enter Verification Code If Asked
    [Documentation]    Clerk asks for an email code when signing in from a new device. Every
    ...    Robot session looks like a new device. The fixed test code only works for
    ...    +clerk_test addresses in Clerk's development instance. The code is typed once
    ...    Clerk has sent it; if Clerk refuses it, the input is cleared and it is typed again.
    [Arguments]    ${code}=${CLERK_CODE}
    ${otp}=    Set Variable    css=.cl-otpCodeFieldInput >> nth=0
    ${asked}=    Run Keyword And Return Status
    ...    Wait For Elements State    ${otp}    visible    timeout=6s
    IF    not ${asked}    RETURN
    FOR    ${attempt}    IN RANGE    3
        Run Keyword And Ignore Error    Wait For Load State    networkidle    timeout=10s
        IF    ${attempt} > 0    Run Keyword And Ignore Error    Clear Verification Code
        Focus    css=input[autocomplete="one-time-code"]
        Keyboard Input    type    ${code}
        ${done}=    Run Keyword And Return Status
        ...    Wait For Elements State    ${WORKSPACE}    visible    timeout=12s
        IF    ${done}    RETURN
        # INFO, not WARN: a retry is normal Clerk behaviour and must not show up as an execution error.
        Log    Clerk did not accept the code yet (attempt ${attempt}), trying again
    END
    Fail    Clerk did not accept the verification code after three attempts

Clear Verification Code
    [Documentation]    Empties Clerk's code input.
    Focus    css=input[autocomplete="one-time-code"]
    Keyboard Key    press    End
    FOR    ${i}    IN RANGE    6
        Keyboard Key    press    Backspace
    END

Sign In
    [Documentation]    Signs in from the landing page. If Clerk asks to verify a new device,
    ...    the test code is entered. Success is confirmed by the workspace, which is only
    ...    shown to a signed-in user.
    [Arguments]    ${email}=${USER_A_EMAIL}    ${password}=${USER_A_PASSWORD}
    Open Sign In
    Fill Text    input[name="identifier"]    ${email}
    Click    .cl-formButtonPrimary
    Fill Text    input[name="password"]    ${password}
    Click    .cl-formButtonPrimary
    # Clerk swaps the identifier step for the password step with an animation. A click that lands
    # during the swap is lost and the password step stays open, so it is submitted once more.
    ${submitted}=    Run Keyword And Return Status
    ...    Wait For Elements State    input[name="password"]    hidden    timeout=10s
    IF    not ${submitted}
        Log    Password step was not submitted, submitting again
        Click    .cl-formButtonPrimary
    END
    Enter Verification Code If Asked
    Wait For Workspace

Prepare Players
    [Documentation]    Starts the browser and signs the given players (A and/or B) in, each in
    ...    their own browser session. The session ids are stored so Api Request can switch
    ...    between the players. The tokens always come from the active player's session.
    [Arguments]    @{players}
    Open Test Browser
    FOR    ${player}    IN    @{players}
        ${email}=    Set Variable If    '${player}' == 'A'    ${USER_A_EMAIL}    ${USER_B_EMAIL}
        ${password}=    Set Variable If    '${player}' == 'A'    ${USER_A_PASSWORD}    ${USER_B_PASSWORD}
        ${context}=    New Context    viewport={'width': 1280, 'height': 900}    locale=fi-FI
        New Page    ${FRONTEND_URL}
        Sign In    ${email}    ${password}
        Set To Dictionary    ${CONTEXTS}    ${player}=${context}
    END

Switch To Player
    [Documentation]    Switches the active browser session to player A or B.
    [Arguments]    ${player}
    Should Contain    ${CONTEXTS}    ${player}
    ...    msg=Player ${player} is not signed in. Use Prepare Players ${player} in Suite Setup.
    Switch Context    ${CONTEXTS}[${player}]

Get Current User Id
    [Documentation]    Returns the Clerk user id of the signed-in user in the active session.
    ${user_id}=    Evaluate JavaScript    ${None}    () => window.Clerk.user.id
    RETURN    ${user_id}

Get Session Token
    [Documentation]    Gets the active (or given) player's session token (JWT) straight from
    ...    Clerk inside the browser. The token is short-lived, so it is always fetched
    ...    right before an API call.
    [Arguments]    ${player}=${None}
    IF    $player is not None    Switch To Player    ${player}
    ${token}=    Evaluate JavaScript    ${None}    async () => await window.Clerk.session.getToken()
    RETURN    ${token}

Api Request
    [Documentation]    Sends a request to the backend and returns the response (status, headers, text, json).
    ...    With user=A or user=B the player's browser token is sent. A 429 (rate limit) is
    ...    waited out unless retry_429=${False} or AUTO_WAIT_RATE_LIMIT=false.
    [Arguments]    ${method}    ${path}    ${user}=${None}    ${json_body}=${None}    ${raw_body}=${None}
    ...    ${headers}=${None}    ${form}=${None}    ${files}=${None}    ${token}=${None}    ${origin}=${None}
    ...    ${params}=${None}    ${timeout}=60    ${retry_429}=${True}    ${absolute_url}=${False}
    ${waited}=    Set Variable    ${0}
    WHILE    True
        ${use_token}=    Set Variable    ${token}
        IF    $user is not None and $token is None
            ${use_token}=    Get Session Token    ${user}
        END
        ${response}=    Send Request    ${method}    ${path}    json_body=${json_body}    raw_body=${raw_body}
        ...    headers=${headers}    form=${form}    files=${files}    token=${use_token}    origin=${origin}
        ...    params=${params}    timeout=${timeout}    absolute_url=${absolute_url}
        ${wait_it_out}=    Evaluate    ($response.status == 429 and $retry_429 and $AUTO_WAIT_RATE_LIMIT and $user is not None and $waited < 960)
        IF    not ${wait_it_out}    RETURN    ${response}
        ${wait}=    Seconds Until Reset    ${response}
        Log To Console    \n[rate limit] 429 from ${method} ${path}, waiting ${wait} s for the window to reset (raise the backend limits for test runs)
        Sleep    ${wait}s
        ${waited}=    Evaluate    $waited + $wait
    END


# ---------------------------------------------------------------------
# Browser helpers
# ---------------------------------------------------------------------
Go To Section
    [Documentation]    Opens a workspace section from the sidebar. On narrow screens (740 px or less)
    ...    the links are hidden behind the menu button, which is opened first.
    [Arguments]    ${name}
    ${link}=    Set Variable    ${NAV} >> button.nav-link:has-text("${name}")
    ${visible}=    Run Keyword And Return Status    Wait For Elements State    ${link}    visible    timeout=2s
    IF    not ${visible}
        Click    css=button.mobile-nav-toggle
        Wait For Elements State    ${link}    visible
    END
    Click    ${link}
    Wait For Load State    networkidle

Page Should Not Scroll Horizontally
    [Documentation]    Fails when the page is wider than the viewport (layout overflow on small screens).
    ${overflow}=    Evaluate JavaScript    ${None}    () => document.documentElement.scrollWidth - document.documentElement.clientWidth
    Should Be True    ${overflow} <= 1    msg=Horizontal overflow of ${overflow}px

Set Width
    [Arguments]    ${width}    ${height}=800
    Set Viewport Size    ${width}    ${height}

Script Marker Should Be Unset
    [Documentation]    Injected scripts set window.__xss; it must never be set.
    ${marker}=    Evaluate JavaScript    ${None}    () => window.__xss === undefined
    Should Be True    ${marker}    msg=Injected script was executed

Handle Dialogs Dismissing
    Handle Future Dialogs    action=dismiss