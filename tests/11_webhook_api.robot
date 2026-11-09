*** Settings ***
Documentation     Clerk webhook endpoint (/api/webhooks/clerk): signature verification and input
...               validation. Only events without side effects are sent with a valid signature
...               (user.updated and user.deleted with an invalid id), so no data is ever deleted.
...               Real account deletion is tested by hand, see the README.
Resource          ../resources/common.robot
Suite Setup       Require Config    API_URL
Force Tags        api    security    webhook


*** Variables ***
${WEBHOOK_PATH}           /api/webhooks/clerk
${UPDATED_EVENT}          {"type":"user.updated","object":"event","data":{"id":"user_robotwebhook123"}}
${BAD_ID_EVENT}           {"type":"user.deleted","object":"event","data":{"id":"not a valid id!"}}


*** Keywords ***
Post Webhook
    [Arguments]    ${body}    ${headers}=${None}
    ${response}=    Api Request    POST    ${WEBHOOK_PATH}    raw_body=${body}    headers=${headers}
    RETURN    ${response}

Require Webhook Secret
    Skip If    '${WEBHOOK_SECRET}' == ''    Set CLERK_WEBHOOK_SIGNING_SECRET in .env (same value as the test backend).


*** Test Cases ***
Unsigned webhook request is rejected
    [Documentation]    TC11-001. Expected result: Unsigned webhook request is rejected.
    ${response}=    Post Webhook    ${UPDATED_EVENT}
    Status Should Be One Of    ${response}    400    503
    Error Response Should Be Safe    ${response}

Webhook does not require a user session and is not an authenticated route
    [Documentation]    TC11-002. Expected result: Webhook does not require a user session and is not an authenticated route.
    ${response}=    Post Webhook    ${UPDATED_EVENT}
    Should Not Be Equal As Integers    ${response.status}    401

Request with fake svix headers is rejected
    [Documentation]    TC11-003. Expected result: Request with fake svix headers is rejected.
    # Header values must be strings for requests, so the timestamp is converted with str().
    ${headers}=    Create Dictionary    svix-id=msg_fake    svix-timestamp=${{ str(int(__import__('time').time())) }}    svix-signature=v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=    Content-Type=application/json
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Status Should Be One Of    ${response}    400    503

Webhook signed with the wrong secret is rejected
    [Documentation]    TC11-004. Expected result: Webhook signed with the wrong secret is rejected.
    ${wrong}=    Random Webhook Secret
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}    secret=${wrong}
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Status Should Be One Of    ${response}    400    503

Correctly signed non-deletion event is accepted without side effects
    [Documentation]    TC11-005. Expected result: Correctly signed non-deletion event is accepted without side effects.
    Require Webhook Secret
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Status Should Be    ${response}    204

Signed webhook is accepted without Clerk's middleware or a redirect
    [Documentation]    TC11-016. Clerk's middleware no longer runs on the webhook route. Expected result: a correctly
    ...    signed non-deletion event is accepted with 204, also when the request carries browser page headers and
    ...    Clerk's __client_uat cookie, and the answer has no 3xx status, no Location and no x-clerk-auth-status
    ...    header (redirects are not followed).
    Require Webhook Secret
    FOR    ${with_cookie}    IN    ${False}    ${True}
        ${headers}=    Sign Webhook    ${UPDATED_EVENT}
        IF    ${with_cookie}
            Set To Dictionary    ${headers}    Cookie=__client_uat=1700000000    Sec-Fetch-Dest=document
            ...    Sec-Fetch-Mode=navigate    Accept=text/html,*/*;q=0.8
        END
        ${response}=    Send Request    POST    ${WEBHOOK_PATH}    raw_body=${UPDATED_EVENT}    headers=${headers}    follow_redirects=${False}
        Status Should Be    ${response}    204
        Should Be Empty    ${response.header('Location')}
        Should Be Empty    ${response.header('x-clerk-auth-status')}
    END

Tampered body with a valid signature of another body is rejected
    [Documentation]    TC11-006. Expected result: Tampered body with a valid signature of another body is rejected.
    Require Webhook Secret
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}
    ${tampered}=    Set Variable    {"type":"user.deleted","object":"event","data":{"id":"user_victim123"}}
    ${response}=    Post Webhook    ${tampered}    ${headers}
    Status Should Be    ${response}    400

Old timestamps are rejected to prevent replay
    [Documentation]    TC11-007. Expected result: Old timestamps are rejected to prevent replay.
    Require Webhook Secret
    ${old}=    Evaluate    int(__import__('time').time()) - 3600
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}    timestamp=${old}
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Status Should Be    ${response}    400

Future timestamps are rejected
    [Documentation]    TC11-008. Expected result: Future timestamps are rejected.
    Require Webhook Secret
    ${future}=    Evaluate    int(__import__('time').time()) + 3600
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}    timestamp=${future}
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Status Should Be    ${response}    400

Missing signature headers are rejected even with a valid body
    [Documentation]    TC11-009. Expected result: Missing signature headers are rejected even with a valid body.
    Require Webhook Secret
    ${headers}=    Sign Webhook    ${UPDATED_EVENT}
    FOR    ${name}    IN    svix-id    svix-timestamp    svix-signature
        ${partial}=    Copy Dictionary    ${headers}
        Remove From Dictionary    ${partial}    ${name}
        ${response}=    Post Webhook    ${UPDATED_EVENT}    ${partial}
        Status Should Be    ${response}    400
    END

Signed deletion event with an invalid user id is refused
    [Documentation]    TC11-010. Expected result: Signed deletion event with an invalid user id is refused.
    Require Webhook Secret
    ${headers}=    Sign Webhook    ${BAD_ID_EVENT}
    ${response}=    Post Webhook    ${BAD_ID_EVENT}    ${headers}
    Status Should Be    ${response}    400
    Error Response Should Be Safe    ${response}

Operator objects as user id in a signed deletion event are refused
    [Documentation]    TC11-011. Expected result: Operator objects as user id in a signed deletion event are refused.
    Require Webhook Secret
    ${body}=    Set Variable    {"type":"user.deleted","object":"event","data":{"id":{"$ne":null}}}
    ${headers}=    Sign Webhook    ${body}
    ${response}=    Post Webhook    ${body}    ${headers}
    Status Should Be    ${response}    400

Oversized webhook body is refused
    [Documentation]    TC11-012. Expected result: Oversized webhook body is refused.
    ${big}=    Evaluate    '{"data":"' + 'x' * 70000 + '"}'
    ${response}=    Post Webhook    ${big}
    Status Should Be One Of    ${response}    400    413

Malformed and non-JSON webhook bodies do not crash the server
    [Documentation]    TC11-013. Expected result: Malformed and non-JSON webhook bodies do not crash the server.
    FOR    ${body}    IN    {    not json    []    null    ${EMPTY}
        ${response}=    Post Webhook    ${body}
        Should Be True    400 <= ${response.status} < 500 or ${response.status} == 503
    END
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

Webhook with a non-JSON content type is refused
    [Documentation]    TC11-014. Expected result: Webhook with a non-JSON content type is refused.
    ${headers}=    Create Dictionary    Content-Type=text/plain
    ${response}=    Post Webhook    ${UPDATED_EVENT}    ${headers}
    Should Be True    ${response.status} >= 400 and ${response.status} < 500 or ${response.status} == 503

Only POST is accepted on the webhook route
    [Documentation]    TC11-015. Expected result: Only POST is accepted on the webhook route.
    FOR    ${method}    IN    GET    PUT    DELETE    PATCH
        ${response}=    Api Request    ${method}    ${WEBHOOK_PATH}
        Should Not Be Equal As Integers    ${response.status}    200
        Should Not Be Equal As Integers    ${response.status}    202
        Should Not Be Equal As Integers    ${response.status}    204
    END
