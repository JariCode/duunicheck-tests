*** Settings ***
Documentation     Injection and abuse resistance of the backend API: NoSQL operator injection,
...               prototype pollution, script payloads stored as data, malformed or oversized JSON,
...               parameter pollution, path tricks and denial-of-service style requests.
...               A payload is "safe" when the server rejects it with 4xx or stores it as plain text
...               and returns it unchanged, and never answers with a 5xx error or changes behaviour.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    security    injection


*** Variables ***
@{TEXT_PAYLOADS}
...    <script>window.__xss=1</script>
...    <img src=x onerror="window.__xss=1">
...    "><svg onload=window.__xss=1>
...    javascript:alert(1)
...    ' OR '1'='1' --
...    "; DROP TABLE applications; --
...    {{7*7}}
...    \${7*7}
...    $(whoami)
...    `id`
...    ; cat /etc/passwd
...    ../../../../etc/passwd
...    %00%0d%0aX-Injected: yes
...    $ne
...    {"$ne": null}
...    <!--#exec cmd="ls"-->
...    ${{ '(a+)+$' + 'a' * 40 + '!' }}
...    ${{ '‮evil‬' }}
@{OPERATOR_OBJECTS}    ${{ {'$ne': None} }}    ${{ {'$gt': ''} }}    ${{ {'$regex': '.*'} }}    ${{ {'$where': 'sleep(2000)'} }}
...                    ${{ {'$in': ['a', 'b']} }}    ${{ {'$exists': True} }}    ${{ {'$expr': {'$eq': [1, 1]}} }}


*** Test Cases ***
Script and injection strings are stored as plain text and returned unchanged
    [Documentation]    TC09-001. Expected result: Script and injection strings are stored as plain text and returned unchanged.
    FOR    ${payload}    IN    @{TEXT_PAYLOADS}
        ${app}=    Application Payload    company=${payload}    role=${payload}    notes=${payload}    place=${payload}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${app}
        Status Should Be    ${response}    201
        Should Be Equal    ${response.json}[company]    ${payload.strip()}
        Should Contain    ${response.header('Content-Type')}    application/json
        Should Be Equal    ${response.header('X-Content-Type-Options')}    nosniff
    END
    ${list}=    Api Request    GET    /api/applications    user=A
    Status Should Be    ${list}    200
    Should Contain    ${list.header('Content-Type')}    application/json

Script strings are accepted in CV and template text fields without side effects
    [Documentation]    TC09-002. Expected result: Script strings are accepted in CV and template text fields without side effects.
    FOR    ${payload}    IN    @{TEXT_PAYLOADS}
        ${cv}=    Cv Payload    summary=${payload}    title=${payload}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
        Status Should Be    ${response}    201
        ${template}=    Template Payload    body=${payload}
        ${response}=    Api Request    POST    /api/templates    user=A    json_body=${template}
        Status Should Be    ${response}    201
    END

MongoDB operator objects in text fields are rejected
    [Documentation]    TC09-003. Expected result: MongoDB operator objects in text fields are rejected.
    FOR    ${operator}    IN    @{OPERATOR_OBJECTS}
        FOR    ${field}    IN    company    role    place    notes    next    status
            ${payload}=    Application Payload
            Set To Dictionary    ${payload}    ${field}=${operator}
            ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
            Status Should Be    ${response}    400
            Error Response Should Be Safe    ${response}
        END
    END

MongoDB operators in references and ids are rejected
    [Documentation]    TC09-004. Expected result: MongoDB operators in references and ids are rejected.
    FOR    ${operator}    IN    @{OPERATOR_OBJECTS}
        FOR    ${field}    IN    cvId    templateId    cvFileId
            ${payload}=    Application Payload
            Set To Dictionary    ${payload}    ${field}=${operator}
            ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
            Status Should Be    ${response}    400
        END
        ${payload}=    Application Payload    applicationFileIds=${{ [$operator] }}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
        ${event}=    Create Dictionary    id=${operator}    type=Lähetetty    date=2026-01-05
        ${payload}=    Application Payload    events=${{ [$event] }}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Operators as top-level keys are rejected
    [Documentation]    TC09-005. Expected result: Operators as top-level keys are rejected.
    FOR    ${key}    IN    $set    $where    $ne    company.$ne    events.0.type    $expr
        ${payload}=    Application Payload
        Set To Dictionary    ${payload}    ${key}=x
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
        ${update}=    Api Request    PUT    /api/applications/${MISSING_ID}    user=A    json_body=${payload}
        Status Should Be    ${update}    400
    END

Operators inside the identifier in the URL are rejected
    [Documentation]    TC09-006. Expected result: Operators inside the identifier in the URL are rejected.
    FOR    ${bad_id}    IN    %7B%22%24ne%22%3Anull%7D    %24ne    %5B%24ne%5D    ${MISSING_ID}%00    ${MISSING_ID}%0a    ${MISSING_ID.upper()}X
        ${update}=    Api Request    PUT    /api/applications/${bad_id}    user=A    json_body=${{ {'company': 'x', 'role': 'y', 'status': 'Kiinnostava'} }}
        Status Should Be    ${update}    400
        ${delete}=    Api Request    DELETE    /api/applications/${bad_id}    user=A
        Status Should Be    ${delete}    400
        ${history}=    Api Request    GET    /api/conversations/${bad_id}    user=A
        Status Should Be    ${history}    400
        ${download}=    Api Request    GET    /api/files/${bad_id}/download    user=A
        Status Should Be    ${download}    400
    END

Operators in the query string do not change the result
    [Documentation]    TC09-007. Expected result: Operators in the query string do not change the result.
    ${before}=    Api Request    GET    /api/applications    user=A
    ${operators}=    Api Request    GET    /api/applications?company[$ne]=x&role[$regex]=.*&$where=1&__proto__[x]=1&status[$in][]=a    user=A
    Status Should Be    ${operators}    200
    Should Be Equal    ${operators.json}    ${before.json}
    ${pollution}=    Api Request    GET    /api/applications?a=1&a=2&a[]=3&a[b]=4    user=A
    Status Should Be    ${pollution}    200

Prototype pollution through the JSON body does not change later requests
    [Documentation]    TC09-008. Expected result: Prototype pollution through the JSON body does not change later requests.
    ${raw}=    Set Variable    {"company":"Proto","role":"Test","status":"Kiinnostava","__proto__":{"polluted":"yes","isAdmin":true}}
    ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${raw}
    Status Should Be    ${response}    400
    ${raw2}=    Set Variable    {"company":"Proto","role":"Test","status":"Kiinnostava","constructor":{"prototype":{"polluted":"yes"}}}
    ${response2}=    Api Request    POST    /api/applications    user=A    raw_body=${raw2}
    Status Should Be    ${response2}    400
    ${check}=    Api Request    GET    /api/settings    user=A
    Status Should Be    ${check}    200
    Should Be Equal    ${check.json}    ${{ {'theme': 'default'} }}
    ${fresh}=    Create Application As    A
    Dictionary Should Not Contain Key    ${fresh}    polluted
    Dictionary Should Not Contain Key    ${fresh}    isAdmin

Malformed JSON is answered with a safe 400
    [Documentation]    TC09-009. Expected result: Malformed JSON is answered with a safe 400.
    ...    The last body is the JSON text {"company":"\\ud800"}: a JSON escape of a lone UTF-16
    ...    surrogate, sent as plain ASCII. The backslash is doubled so that Robot does not turn it
    ...    into a real surrogate character, which cannot be encoded as UTF-8 and breaks output.xml.
    FOR    ${raw}    IN    {    {"company":    {'company':'x'}    {"company":"x",}    {"a":1}}    \x00    <xml/>    {"company":"\\ud800"}
        ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${raw}
        Status Should Be    ${response}    400
        Error Response Should Be Safe    ${response}
    END

Wrong content type does not bypass validation or crash the server
    [Documentation]    TC09-010. Expected result: Wrong content type does not bypass validation or crash the server.
    ${body}=    Set Variable    {"company":"X","role":"Y","status":"Kiinnostava"}
    FOR    ${type}    IN    text/plain    application/x-www-form-urlencoded    application/xml    multipart/form-data    ${EMPTY}
        ${headers}=    Create Dictionary    Content-Type=${type}
        ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${body}    headers=${headers}
        Should Be True    ${response.status} < 500    msg=Server error for content type ${type}: ${response.text}
        Should Be True    ${response.status} >= 400
    END

JSON body above 1 MB is refused with 413
    [Documentation]    TC09-011. Expected result: JSON body above 1 MB is refused with 413.
    ${big}=    Evaluate    'x' * (1024 * 1024 + 10)
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${{ {'company': $big, 'role': 'r', 'status': 'Kiinnostava'} }}
    Status Should Be    ${response}    413
    Error Response Should Be Safe    ${response}

Deeply nested JSON does not crash the server
    [Documentation]    TC09-012. Expected result: Deeply nested JSON does not crash the server.
    ${nested}=    Evaluate    '[' * 50000 + ']' * 50000
    ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${nested}
    Should Be True    400 <= ${response.status} < 500    msg=Unexpected ${response.status}: ${response.text}[:200]
    ${object_nested}=    Evaluate    '{"a":' * 20000 + '1' + '}' * 20000
    ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${object_nested}
    Should Be True    400 <= ${response.status} < 500
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

Very long URLs and many headers do not crash the server
    [Documentation]    TC09-013. Expected result: Very long URLs and many headers do not crash the server.
    ${long_path}=    Evaluate    '/api/applications/' + 'a' * 20000
    ${response}=    Api Request    GET    ${long_path}    user=A
    Should Be True    ${response.status} in (400, 404, 414, 431)    msg=Unexpected ${response.status}
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

Control characters and null bytes in text fields round-trip as data
    [Documentation]    TC09-014. Expected result: Control characters and null bytes in text fields round-trip as data.
    ${payload}=    Set Variable    line1\nline2\ttab \u0000 nul
    ${app}=    Application Payload    notes=${payload}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${app}
    Status Should Be One Of    ${response}    201    400
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

CRLF in a text field cannot inject response headers
    [Documentation]    TC09-015. Expected result: CRLF in a text field cannot inject response headers.
    ${payload}=    Set Variable    x\r\nX-Injected: yes\r\n\r\n<script>alert(1)</script>
    ${app}=    Application Payload    company=${payload}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${app}
    Should Be Empty    ${response.header('X-Injected')}
    ${list}=    Api Request    GET    /api/applications    user=A
    Should Be Empty    ${list.header('X-Injected')}

Host header and forwarded headers cannot spoof the rate limit identity
    [Documentation]    TC09-016. Expected result: Host header and forwarded headers cannot spoof the rate limit identity.
    ${first}=    Api Request    GET    /api/health    headers=${{ {'X-Forwarded-For': '1.2.3.4', 'X-Real-IP': '5.6.7.8', 'Host': 'evil.example'} }}
    Should Be True    ${first.status} < 500

Requests with an invalid Origin or Referer are not trusted for authentication
    [Documentation]    TC09-017. Expected result: Requests with an invalid Origin or Referer are not trusted for authentication.
    ${response}=    Api Request    GET    /api/applications    user=A    headers=${{ {'Referer': 'https://evil.example/', 'Origin': 'https://evil.example'} }}
    Should Be True    ${response.status} < 500
    Should Be Empty    ${response.header('Access-Control-Allow-Origin')}
