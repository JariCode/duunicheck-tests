*** Settings ***
Documentation     Security headers, CORS behaviour and information leakage of the backend, plus the
...               headers of the published frontend, checked from the application's frontend/public/.htaccess
...               (APP_DIR), and the content of a local frontend build. Robot is never run against the
...               production site.
Resource          ../resources/common.robot
Library           Process
Suite Setup       Prepare Headers Suite
Suite Teardown    Finish API Suite
Force Tags        api    security    headers


*** Keywords ***
Prepare Headers Suite
    Prepare API Suite
    Require Config    ALLOWED_ORIGIN

Header Should Be Present
    [Arguments]    ${response}    ${name}
    ${value}=    Set Variable    ${response.header('${name}')}
    Should Not Be Empty    ${value}    msg=Header ${name} is missing

Preflight
    [Arguments]    ${origin}    ${method}=DELETE    ${request_headers}=authorization,content-type
    &{headers}=    Create Dictionary    Access-Control-Request-Method=${method}    Access-Control-Request-Headers=${request_headers}
    ${response}=    Api Request    OPTIONS    /api/applications/${MISSING_ID}    origin=${origin}    headers=${headers}
    RETURN    ${response}

Combined Csp
    [Arguments]    ${response}
    ${csp}=    Set Variable    ${response.header('Content-Security-Policy')}${response.header('Content-Security-Policy-Report-Only')}
    RETURN    ${csp}

Csp Header Name
    [Documentation]    Name of the CSP header the published .htaccess sets. It is read from the file, not assumed:
    ...    exactly one of Content-Security-Policy (enforced) and Content-Security-Policy-Report-Only must be set.
    ${headers}=    Htaccess Headers
    ${names}=    Evaluate    [name for name in ('Content-Security-Policy', 'Content-Security-Policy-Report-Only') if name in $headers]
    Length Should Be    ${names}    1    msg=Expected exactly one CSP header in the published .htaccess, found ${names}
    Log    The published .htaccess sets ${names}[0].
    RETURN    ${names}[0]

Csp Directive
    [Documentation]    Returns the value of one directive of a CSP (without its name), or fails if it is missing.
    [Arguments]    ${csp}    ${directive}
    # Robot variables cannot be seen inside a generator, so they are passed to a function.
    ${value}=    Evaluate    (lambda policy, name: next((part.strip()[len(name):].strip() for part in policy.split(';') if part.strip().split(' ')[0] == name), None))($csp, $directive)
    Should Not Be Equal    ${value}    ${None}    msg=CSP has no ${directive} directive: ${csp}
    RETURN    ${value}

Wait For Preview
    [Arguments]    ${url}
    FOR    ${attempt}    IN RANGE    60
        ${status}    ${response}=    Run Keyword And Ignore Error    Send Request    GET    ${url}    absolute_url=${True}    timeout=3    follow_redirects=${False}
        IF    $status == 'PASS'    RETURN
        Sleep    1s
    END
    Fail    vite preview did not answer at ${url}

Published Csp
    [Documentation]    CSP of the published .htaccess: the enforced and the report-only header together.
    ${headers}=    Htaccess Headers
    ${csp}=    Evaluate    $headers.get('Content-Security-Policy', '') + $headers.get('Content-Security-Policy-Report-Only', '')
    Should Not Be Empty    ${csp}    msg=The published .htaccess sets no Content-Security-Policy header
    RETURN    ${csp}


*** Test Cases ***
Backend sets the standard Helmet security headers
    [Documentation]    TC10-001. Expected result: Backend sets the standard Helmet security headers.
    ${response}=    Api Request    GET    /api/health
    Header Should Be Present    ${response}    X-Content-Type-Options
    Should Be Equal    ${response.header('X-Content-Type-Options')}    nosniff
    Header Should Be Present    ${response}    X-Frame-Options
    Header Should Be Present    ${response}    Strict-Transport-Security
    Header Should Be Present    ${response}    Content-Security-Policy
    Should Contain    ${response.header('Content-Security-Policy')}    default-src 'self'
    Should Be Equal    ${response.header('Referrer-Policy')}    no-referrer
    Should Be Equal    ${response.header('X-XSS-Protection')}    0
    Should Be Equal    ${response.header('Cross-Origin-Resource-Policy')}    cross-origin

Backend does not reveal the server technology
    [Documentation]    TC10-002. Expected result: Backend does not reveal the server technology.
    ${response}=    Api Request    GET    /api/health
    Should Be Empty    ${response.header('X-Powered-By')}
    Should Not Contain    ${response.header('Server')}    Express

Private API responses are never cacheable
    [Documentation]    TC10-003. Expected result: Private API responses are never cacheable.
    ${authed}=    Api Request    GET    /api/applications    user=A
    Should Contain    ${authed.header('Cache-Control')}    no-store
    ${unauth}=    Api Request    GET    /api/applications
    Should Contain    ${unauth.header('Cache-Control')}    no-store
    ${settings}=    Api Request    GET    /api/settings    user=A
    Should Contain    ${settings.header('Cache-Control')}    no-store

Rate limit information is sent with API responses
    [Documentation]    TC10-004. Expected result: Rate limit information is sent with API responses.
    ${response}=    Api Request    GET    /api/settings    user=A
    ${policy}=    Set Variable    ${response.header('RateLimit-Policy')}${response.header('RateLimit')}
    Should Not Be Empty    ${policy}    msg=No RateLimit headers on an API response
    Should Be Empty    ${response.header('X-RateLimit-Limit')}

Allowed origin receives CORS headers
    [Documentation]    TC10-005. Expected result: Allowed origin receives CORS headers.
    ${response}=    Api Request    GET    /api/health    origin=${ALLOWED_ORIGIN}
    Should Be Equal    ${response.header('Access-Control-Allow-Origin')}    ${ALLOWED_ORIGIN}
    Should Contain    ${response.header('Vary')}    Origin
    Should Be Empty    ${response.header('Access-Control-Allow-Credentials')}

Foreign origins receive no CORS headers
    [Documentation]    TC10-006. Expected result: Foreign origins receive no CORS headers.
    ${host}=    Evaluate    $ALLOWED_ORIGIN.split('//', 1)[-1]
    @{origins}=    Create List    https://evil.example    http://localhost:9999    null    ${ALLOWED_ORIGIN}.evil.example
    ...    ${ALLOWED_ORIGIN}:8080    evil${ALLOWED_ORIGIN}    https://${host}.evil.example    http://${host}@evil.example
    FOR    ${origin}    IN    @{origins}
        ${response}=    Api Request    GET    /api/health    origin=${origin}
        Should Be Empty    ${response.header('Access-Control-Allow-Origin')}    msg=Origin ${origin} was allowed
    END

Preflight from the allowed origin lists only the expected methods and headers
    [Documentation]    TC10-007. Expected result: Preflight from the allowed origin lists only the expected methods and headers.
    ${response}=    Preflight    ${ALLOWED_ORIGIN}
    Should Be True    ${response.status} in (200, 204)
    Should Be Equal    ${response.header('Access-Control-Allow-Origin')}    ${ALLOWED_ORIGIN}
    ${methods}=    Set Variable    ${response.header('Access-Control-Allow-Methods')}
    FOR    ${method}    IN    GET    POST    PUT    DELETE
        Should Contain    ${methods}    ${method}
    END
    Should Not Contain    ${methods}    PATCH
    Should Not Contain    ${methods}    *
    ${allowed_headers}=    Convert To Lower Case    ${response.header('Access-Control-Allow-Headers')}
    Should Contain    ${allowed_headers}    authorization
    Should Contain    ${allowed_headers}    content-type
    Should Not Contain    ${allowed_headers}    *
    Should Be Equal    ${response.header('Access-Control-Max-Age')}    600

Preflight from a foreign origin is not approved
    [Documentation]    TC10-008. Expected result: Preflight from a foreign origin is not approved.
    FOR    ${origin}    IN    https://evil.example    null
        ${response}=    Preflight    ${origin}
        Should Be Empty    ${response.header('Access-Control-Allow-Origin')}
        Should Be Empty    ${response.header('Access-Control-Allow-Methods')}
    END

Unexpected request headers are not allowed by the preflight
    [Documentation]    TC10-009. Expected result: Unexpected request headers are not allowed by the preflight.
    ${response}=    Preflight    ${ALLOWED_ORIGIN}    request_headers=x-evil-header,x-forwarded-host
    ${allowed}=    Convert To Lower Case    ${response.header('Access-Control-Allow-Headers')}
    Should Not Contain    ${allowed}    x-evil-header
    Should Not Contain    ${allowed}    x-forwarded-host

Error responses are JSON and leak no internals
    [Documentation]    TC10-010. Expected result: Error responses are JSON and leak no internals.
    ${not_found}=    Api Request    GET    /api/nope    user=A
    Error Response Should Be Safe    ${not_found}
    ${bad_json}=    Api Request    POST    /api/applications    user=A    raw_body={bad
    Error Response Should Be Safe    ${bad_json}
    ${bad_id}=    Api Request    DELETE    /api/applications/xyz    user=A
    Error Response Should Be Safe    ${bad_id}
    ${unauth}=    Api Request    GET    /api/applications
    Error Response Should Be Safe    ${unauth}
    FOR    ${response}    IN    ${not_found}    ${bad_json}    ${bad_id}    ${unauth}
        Should Contain    ${response.header('Content-Type')}    application/json
    END

TRACE requests are not echoed back
    [Documentation]    TC10-011. Expected result: TRACE requests are not echoed back.
    ${trace}=    Api Request    TRACE    /api/health    headers=${{ {'X-Probe': 'trace-marker'} }}
    Should Not Contain    ${trace.text}    trace-marker
    Should Not Be Equal As Integers    ${trace.status}    200

Published .htaccess sets the hardening headers
    [Documentation]    TC10-012. Checks the content of the published frontend/public/.htaccess (Robot is never
    ...    run against the production site). Expected result: X-Content-Type-Options nosniff, X-Frame-Options
    ...    DENY, Referrer-Policy strict-origin-when-cross-origin, Permissions-Policy with camera=() and a CSP
    ...    with default-src 'self' and frame-ancestors 'none'.
    [Tags]    frontend    htaccess
    ${headers}=    Htaccess Headers
    Should Be Equal    ${headers}[X-Content-Type-Options]    nosniff
    Should Be Equal    ${headers}[X-Frame-Options]    DENY
    Should Be Equal    ${headers}[Referrer-Policy]    strict-origin-when-cross-origin
    Should Contain    ${headers}[Permissions-Policy]    camera=()
    ${csp}=    Published Csp
    Should Contain    ${csp}    default-src 'self'
    Should Contain    ${csp}    frame-ancestors 'none'

Published .htaccess switches directory listing off
    [Documentation]    TC10-014. Checks the content of the published frontend/public/.htaccess. Directory listing
    ...    would expose the build files. Expected result: "Options -Indexes" is set.
    [Tags]    frontend    htaccess    known-gap
    ${content}=    Published Htaccess
    Should Match Regexp    ${content}    (?im)^\\s*Options\\s+(?:\\S+\\s+)*-Indexes\\b    msg=The published .htaccess does not set Options -Indexes

Published .htaccess serves the manifest with the correct MIME type
    [Documentation]    TC10-015. Checks the content of the published frontend/public/.htaccess. Expected result:
    ...    "AddType application/manifest+json .webmanifest" is set.
    [Tags]    frontend    htaccess
    ${content}=    Published Htaccess
    Should Match Regexp    ${content}    (?im)^\\s*AddType\\s+application/manifest\\+json\\s+(?:\\S+\\s+)*\\.webmanifest\\b    msg=The published .htaccess does not set the manifest MIME type

Frontend build contains no sensitive files
    [Documentation]    TC10-016. Builds the frontend (npx vite build, about 5 s) into a temporary folder of the
    ...    test repository, never into frontend/dist, and checks what would be published. Expected result: the
    ...    build has no environment files (.env*), no .git, no package.json, no vite.config.* and no src/
    ...    folder. The temporary folder is removed afterwards.
    [Tags]    frontend    build
    Require Config    APP_DIR
    ${frontend}=    Normalize Path    ${APP_DIR}${/}frontend
    ${out}=    Normalize Path    ${CURDIR}${/}..${/}tmp${/}build-check
    ${result}=    Run Process    npx vite build --outDir "${out}" --emptyOutDir    shell=True    cwd=${frontend}
    ...    timeout=180s    stderr=STDOUT
    Should Be Equal As Integers    ${result.rc}    0    msg=Frontend build failed: ${result.stdout}[-1500:]
    File Should Exist    ${out}${/}index.html
    ${forbidden}=    Forbidden Build Files    ${out}
    Should Be Empty    ${forbidden}    msg=The frontend build would publish: ${forbidden}
    [Teardown]    Remove Directory    ${CURDIR}${/}..${/}tmp${/}build-check    recursive=${True}

Published .htaccess sets HSTS for one year with subdomains
    [Documentation]    TC10-017. Checks the content of the published frontend/public/.htaccess. Expected result:
    ...    "Header always set Strict-Transport-Security" is set exactly to "max-age=31536000; includeSubDomains".
    [Tags]    frontend    htaccess
    ${content}=    Published Htaccess
    Should Match Regexp    ${content}    (?m)^\\s*Header\\s+always\\s+set\\s+Strict-Transport-Security\\s+"max-age=31536000; includeSubDomains"\\s*$
    ${headers}=    Htaccess Headers
    Should Be Equal    ${headers}[Strict-Transport-Security]    max-age=31536000; includeSubDomains

Published CSP allows the real backend and has no placeholder or eval
    [Documentation]    TC10-018. Checks the content of the published frontend/public/.htaccess. The header name is
    ...    read from the file (Csp Header Name), not assumed. Expected result: connect-src allows
    ...    https://duunicheck.onrender.com, the Clerk sources follow Clerk's CSP guide (*.protect.clerk.com in
    ...    script-src, frame-src and, with the port wildcard, connect-src), the placeholder BACKEND-URL.example is
    ...    gone from the whole file and the CSP has no 'unsafe-eval', no wildcard source "*" and object-src 'none'.
    [Tags]    frontend    htaccess
    ${name}=    Csp Header Name
    ${headers}=    Htaccess Headers
    ${csp}=    Set Variable    ${headers}[${name}]
    ${connect}=    Csp Directive    ${csp}    connect-src
    ${connect_sources}=    Evaluate    $connect.split()
    Should Contain    ${connect_sources}    https://duunicheck.onrender.com
    Should Contain    ${connect_sources}    https://*.protect.clerk.com:*
    ${script}=    Csp Directive    ${csp}    script-src
    Should Contain    ${{ $script.split() }}    https://*.protect.clerk.com
    ${frame}=    Csp Directive    ${csp}    frame-src
    Should Contain    ${{ $frame.split() }}    https://*.protect.clerk.com
    ${objects}=    Csp Directive    ${csp}    object-src
    Should Be Equal    ${objects}    'none'
    Should Not Contain    ${csp}    'unsafe-eval'
    ${wildcards}=    Evaluate    [source for part in $csp.split(';') for source in part.split()[1:] if source == '*']
    Should Be Empty    ${wildcards}
    ${content}=    Published Htaccess
    Should Not Contain    ${content}    BACKEND-URL.example

Vite preview sends the .htaccess headers and redirects the base path without a trailing slash
    [Documentation]    TC10-019. Builds the frontend into the gitignored tmp/ folder with VITE_BASE_PATH=/robot-base/
    ...    and VITE_API_URL=http://localhost:5000 (environment variables of the build and preview processes only,
    ...    no .env file is read or changed) and starts vite preview on port 4317. Expected result: the page
    ...    /robot-base/ is served with every header of the published .htaccess unchanged, except that the CSP
    ...    connect-src also allows the local API origin http://localhost:5000; /robot-base answers 301 to
    ...    /robot-base/ and keeps the query string; the base path with the slash is not redirected.
    [Tags]    frontend    build
    Require Config    APP_DIR
    ${frontend}=    Normalize Path    ${APP_DIR}${/}frontend
    ${vite}=    Normalize Path    ${frontend}${/}node_modules${/}vite${/}bin${/}vite.js
    ${out}=    Normalize Path    ${CURDIR}${/}..${/}tmp${/}preview-check
    ${build}=    Run Process    node    ${vite}    build    --outDir    ${out}    --emptyOutDir    cwd=${frontend}
    ...    timeout=180s    stderr=STDOUT    env:VITE_BASE_PATH=/robot-base/    env:VITE_API_URL=http://localhost:5000
    Should Be Equal As Integers    ${build.rc}    0    msg=Frontend build failed: ${build.stdout}[-1500:]
    Start Process    node    ${vite}    preview    --outDir    ${out}    --port    4317    --strictPort    cwd=${frontend}
    ...    alias=preview    env:VITE_BASE_PATH=/robot-base/    env:VITE_API_URL=http://localhost:5000
    Wait For Preview    http://localhost:4317/robot-base/
    ${page}=    Send Request    GET    http://localhost:4317/robot-base/    absolute_url=${True}    follow_redirects=${False}
    Status Should Be    ${page}    200
    ${headers}=    Htaccess Headers
    ${name}=    Csp Header Name
    FOR    ${header}    ${value}    IN    &{headers}
        IF    $header == $name
            ${expected}=    Evaluate    re.sub(r'(^|;\\s*)connect-src([^;]*)', lambda m: m.group(0) + ' http://localhost:5000', $value, count=1)    modules=re
            Should Be Equal    ${page.header('${header}')}    ${expected}    msg=Preview ${header} differs
        ELSE
            Should Be Equal    ${page.header('${header}')}    ${value}    msg=Preview ${header} differs from .htaccess
        END
    END
    ${redirect}=    Send Request    GET    http://localhost:4317/robot-base    absolute_url=${True}    follow_redirects=${False}
    Status Should Be    ${redirect}    301
    Should Be Equal    ${redirect.header('Location')}    /robot-base/
    ${with_query}=    Send Request    GET    http://localhost:4317/robot-base?view=jobs&x=1    absolute_url=${True}    follow_redirects=${False}
    Status Should Be    ${with_query}    301
    Should Be Equal    ${with_query.header('Location')}    /robot-base/?view=jobs&x=1
    [Teardown]    Run Keywords    Terminate All Processes    kill=${True}
    ...    AND    Remove Directory    ${CURDIR}${/}..${/}tmp${/}preview-check    recursive=${True}
