*** Settings ***
Documentation     Authentication and access control of the backend API.
...               Every /api route except /api/health must reject requests without a valid
...               Clerk session token, and forged or tampered tokens must never be accepted.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    security    authentication


*** Variables ***
@{PROTECTED_GET_PATHS}    /api/applications    /api/cvs    /api/templates    /api/files    /api/settings
...                       /api/conversations/${MISSING_ID}    /api/files/${MISSING_ID}/download    /api/does-not-exist


*** Test Cases ***
Health endpoint is public and reports the database state
    [Documentation]    TC02-001. Expected result: Health endpoint is public and reports the database state.
    ${response}=    Api Request    GET    /api/health
    Status Should Be    ${response}    200
    Should Be Equal    ${response.json}[status]    ok

Protected GET routes reject requests without a token
    [Documentation]    TC02-002. Expected result: Protected GET routes reject requests without a token.
    FOR    ${path}    IN    @{PROTECTED_GET_PATHS}
        ${response}=    Api Request    GET    ${path}
        Status Should Be    ${response}    401
        Error Response Should Be Safe    ${response}
    END

Protected write routes reject requests without a token
    [Documentation]    TC02-003. Expected result: Protected write routes reject requests without a token.
    &{body}=    Create Dictionary    company=Acme    role=Tester    status=Kiinnostava
    ${post}=    Api Request    POST    /api/applications    json_body=${body}
    Status Should Be    ${post}    401
    ${put}=    Api Request    PUT    /api/applications/${MISSING_ID}    json_body=${body}
    Status Should Be    ${put}    401
    ${delete}=    Api Request    DELETE    /api/applications/${MISSING_ID}
    Status Should Be    ${delete}    401
    ${cv}=    Api Request    POST    /api/cvs    json_body=${body}
    Status Should Be    ${cv}    401
    ${template}=    Api Request    POST    /api/templates    json_body=${body}
    Status Should Be    ${template}    401
    ${settings}=    Api Request    PUT    /api/settings    json_body=${{ {'theme': 'dark'} }}
    Status Should Be    ${settings}    401
    ${upload}=    Upload File    ${None}    cv    a.txt    hello    text/plain
    Status Should Be    ${upload}    401
    ${answer}=    Api Request    POST    /api/conversations/${MISSING_ID}/answer    json_body=${{ {'message': 'hei'} }}
    Status Should Be    ${answer}    401
    ${ai}=    Api Request    POST    /api/assistant/suggest    json_body=${{ {'message': 'hei'} }}
    Status Should Be    ${ai}    401
    ${parse}=    Api Request    POST    /api/assistant/parse-posting    json_body=${{ {'postingText': 'Ilmoitus', 'link': ''} }}
    Status Should Be    ${parse}    401

Garbage and empty bearer tokens are rejected
    [Documentation]    TC02-004. Expected result: Garbage and empty bearer tokens are rejected.
    FOR    ${token}    IN    not-a-token    a.b.c    ${SPACE}    Bearer    null    undefined
        ${response}=    Api Request    GET    /api/applications    token=${token}
        Status Should Be    ${response}    401
    END
    ${empty}=    Api Request    GET    /api/applications    headers=${{ {'Authorization': 'Bearer '} }}
    Status Should Be    ${empty}    401

Wrong authorization schemes are rejected
    [Documentation]    TC02-005. Expected result: Wrong authorization schemes are rejected.
    ${real}=    Get Session Token    A
    FOR    ${scheme}    IN    Basic    Token    Digest    Negotiate
        ${response}=    Api Request    GET    /api/applications    headers=${{ {'Authorization': '${scheme} ${real}'} }}
        Status Should Be    ${response}    401
    END

Unsigned JWT with alg none is rejected
    [Documentation]    TC02-006. Expected result: Unsigned JWT with alg none is rejected.
    ${forged}=    Forged Jwt    none
    ${response}=    Api Request    GET    /api/applications    token=${forged}
    Status Should Be    ${response}    401

JWT signed with a foreign secret is rejected
    [Documentation]    TC02-007. Expected result: JWT signed with a foreign secret is rejected.
    ${forged}=    Forged Jwt    HS256
    ${response}=    Api Request    GET    /api/applications    token=${forged}
    Status Should Be    ${response}    401

Tampered token signature is rejected
    [Documentation]    TC02-008. Expected result: Tampered token signature is rejected.
    ${real}=    Get Session Token    A
    ${tampered}=    Tamper Jwt    ${real}
    ${response}=    Api Request    GET    /api/applications    token=${tampered}
    Status Should Be    ${response}    401

Token passed in the query string is ignored
    [Documentation]    TC02-009. Expected result: Token passed in the query string is ignored.
    ${real}=    Get Session Token    A
    ${response}=    Api Request    GET    /api/applications    params=${{ {'token': '${real}', 'access_token': '${real}', '__clerk_db_jwt': '${real}'} }}
    Status Should Be    ${response}    401

Valid token gives access to the own empty list
    [Documentation]    TC02-010. Expected result: Valid token gives access to the own empty list.
    ${response}=    Api Request    GET    /api/applications    user=A
    Status Should Be    ${response}    200
    Should Be Equal    ${response.json}    ${{ [] }}

First request of a user is idempotent and repeated calls stay stable
    [Documentation]    TC02-011. Expected result: First request of a user is idempotent and repeated calls stay stable.
    FOR    ${index}    IN RANGE    3
        ${response}=    Api Request    GET    /api/settings    user=A
        Status Should Be    ${response}    200
        Should Be Equal    ${response.json}[theme]    default
    END

Unknown route with a valid token returns a safe JSON 404
    [Documentation]    TC02-012. Expected result: Unknown route with a valid token returns a safe JSON 404.
    ${response}=    Api Request    GET    /api/does-not-exist    user=A
    Status Should Be    ${response}    404
    Error Response Should Be Safe    ${response}

Unsupported methods on existing routes are not served
    [Documentation]    TC02-013. Expected result: Unsupported methods on existing routes are not served.
    FOR    ${method}    IN    PATCH    TRACE    HEAD    OPTIONS
        ${response}=    Api Request    ${method}    /api/applications/${MISSING_ID}    user=A
        Should Not Be Equal As Integers    ${response.status}    200
        Should Be True    ${response.status} < 500    msg=${method} caused a server error
    END

Method override headers do not change the request method
    [Documentation]    TC02-014. Expected result: Method override headers do not change the request method.
    ${created}=    Create Application As    A
    ${response}=    Api Request    GET    /api/applications/${created}[id]    user=A    headers=${{ {'X-HTTP-Method-Override': 'DELETE'} }}
    Should Be True    ${response.status} < 500
    ${list}=    Api Request    GET    /api/applications    user=A    headers=${{ {'X-HTTP-Method-Override': 'DELETE', 'X-Method-Override': 'DELETE'} }}
    Status Should Be    ${list}    200
    ${ids}=    Ids Of    ${list}
    Should Contain    ${ids}    ${created}[id]

Responses never expose server technology headers
    [Documentation]    TC02-015. Expected result: Responses never expose server technology headers.
    ${response}=    Api Request    GET    /api/health
    Should Be Empty    ${response.headers.get('X-Powered-By', '')}

Valid session token without the azp claim is rejected
    [Documentation]    TC02-016. Tokens minted with the Clerk Backend API carry no "azp" (authorized party) claim.
    ...    A backend that sets authorizedParties must not accept a token that cannot be tied to the frontend origin.
    Skip If    not $CLERK_SECRET_KEY    Set CLERK_SECRET_KEY (sk_test_) in .env to run this test.
    ${token}=    Get Backend Api Token    A
    ${response}=    Api Request    GET    /api/applications    token=${token}
    Status Should Be    ${response}    401

Sign-up without an invitation is refused by Clerk's Frontend API
    [Documentation]    TC02-017. The Clerk development instance is in Restricted (invite-only) sign-up mode, so the
    ...    restriction must hold on Clerk's server too, not only in the app's dialog. A sign-up is sent straight to
    ...    Clerk's Frontend API (POST /v1/client/sign_ups) with a made-up e-mail and a valid password but no
    ...    invitation ticket. Expected result: Clerk answers with an error (4xx, code sign_up_mode_restricted),
    ...    the answer has no sign-up object, and no Clerk user with that e-mail exists afterwards.
    [Tags]    invitation
    Skip If    not $CLERK_SECRET_KEY    Set CLERK_SECRET_KEY (sk_test_) in .env to run this test.
    ${stamp}=    Generate Random String    10    [LOWER][NUMBERS]
    ${email}=    Set Variable    robot-noinvite-${stamp}+clerk_test@example.com
    ${response}=    Frontend Api Sign Up    ${email}    Robot-${stamp}-Salasana-aA1!
    Should Be True    400 <= ${response.status} < 500    msg=Sign-up without an invitation was not refused: ${response.status} ${response.text}[:300]
    ${codes}=    Evaluate    [e.get('code') for e in ($response.json or {}).get('errors', [])]
    Should Contain    ${codes}    sign_up_mode_restricted    msg=Unexpected Clerk answer: ${response.text}[:300]
    Should Be Equal    ${{ ($response.json or {}).get('response') }}    ${None}    msg=Clerk returned a sign-up object: ${response.text}[:300]
    ${users}=    Clerk User Ids With Email    ${email}
    Should Be Empty    ${users}    msg=A Clerk user was created without an invitation
    [Teardown]    Delete Created Clerk Users
