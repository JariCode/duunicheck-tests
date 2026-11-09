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
