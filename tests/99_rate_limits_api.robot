*** Settings ***
Documentation     Rate limiting (abuse protection). These tests deliberately exhaust the limits of
...               user B, so this suite must run LAST. The limits are per user (or per IP), so user A
...               must stay unaffected. The assistant and the job posting parser share one AI limit.
...               Wait up to an hour (or restart the backend) before the next run.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish Rate Limit Suite
Force Tags        api    security    rate-limit    slow


*** Keywords ***
Finish Rate Limit Suite
    [Documentation]    The limits are used up, so cleanup must not wait for the rate limit window
    ...    (up to 15 minutes per request). Data left behind is ROBOT-prefixed and removed by the
    ...    Suite Setup of the next run.
    Set Suite Variable    ${AUTO_WAIT_RATE_LIMIT}    ${False}
    Finish API Suite

Hit Until Limited
    [Documentation]    Repeats a request without waiting on 429 and returns the number of the request that was limited.
    [Arguments]    ${max_requests}    ${method}    ${path}    ${json_body}=${None}    ${user}=B
    FOR    ${index}    IN RANGE    1    ${max_requests} + 1
        ${response}=    Api Request    ${method}    ${path}    user=${user}    json_body=${json_body}    retry_429=${False}
        IF    ${response.status} == 429
            RETURN    ${index}    ${response}
        END
        Should Be True    ${response.status} < 500    msg=Server error on request ${index}: ${response.text}
    END
    Fail    No 429 after ${max_requests} requests to ${path}. The limiter is missing or higher than expected.


*** Test Cases ***
AI endpoint is limited per user
    [Documentation]    TC99-001. Invalid bodies are rejected before OpenAI is called, but still count towards the limit.
    ${count}    ${response}=    Hit Until Limited    25    POST    /api/assistant/suggest    json_body=${{ {} }}
    Should Be True    ${count} <= 21    msg=AI limiter allowed ${count} requests, expected at most 20 per hour
    Should Contain    ${response.header('Content-Type')}    application/json
    Error Response Should Be Safe    ${response}

Limit of the AI endpoint does not affect another user
    [Documentation]    TC99-002. Expected result: Limit of the AI endpoint does not affect another user.
    # No waiting on 429: a wait would let the window reset and hide a shared limit.
    ${response}=    Api Request    POST    /api/assistant/suggest    user=A    json_body=${{ {} }}    retry_429=${False}
    Should Not Be Equal As Integers    ${response.status}    429    msg=User A is limited by the AI limit of user B

Job posting parser shares the AI limit of the user
    [Documentation]    TC99-008. Expected result: POST /api/assistant/parse-posting uses the same per-user AI
    ...    limiter as the assistant. User B used the whole AI limit in TC99-001, so the very first
    ...    parse-posting request of B is answered with the safe 429 of the AI limiter.
    ${response}=    Api Request    POST    /api/assistant/parse-posting    user=B    json_body=${{ {} }}    retry_429=${False}
    Safe Error Should Be    ${response}    429    ${AI_LIMIT_ERROR}
    Should Contain    ${response.header('Content-Type')}    application/json

AI limit of user B does not limit the job posting parser of user A
    [Documentation]    TC99-009. Expected result: while user B is limited, the parse-posting request of user A
    ...    is not limited; the empty body is answered with the normal validation error (400).
    # No waiting on 429: a wait would let the window reset and hide a shared limit.
    ${response}=    Api Request    POST    /api/assistant/parse-posting    user=A    json_body=${{ {} }}    retry_429=${False}
    Safe Error Should Be    ${response}    400    ${PARSE_POSTING_INVALID_ERROR}

Job posting parser requests count towards the AI limit
    [Documentation]    TC99-010. Expected result: parse-posting requests of user A use up the AI limit of A
    ...    (at most 20 per hour, A has already used two in TC99-002 and TC99-009), and once it is
    ...    full the assistant of A is limited as well. Runs after the other AI tests, because A stays
    ...    AI-limited until the window resets.
    ${count}    ${response}=    Hit Until Limited    25    POST    /api/assistant/parse-posting    json_body=${{ {} }}    user=A
    Should Be True    ${count} <= 19    msg=AI limiter allowed ${count} parse-posting requests after two earlier AI requests, expected at most 18
    Safe Error Should Be    ${response}    429    ${AI_LIMIT_ERROR}
    ${suggest}=    Api Request    POST    /api/assistant/suggest    user=A    json_body=${{ {} }}    retry_429=${False}
    Safe Error Should Be    ${suggest}    429    ${AI_LIMIT_ERROR}

File upload endpoint is limited per user
    [Documentation]    TC99-003. Expected result: File upload endpoint is limited per user.
    ...    Uploads go to POST /api/files (the category is a form field). The limiter counts every
    ...    request before validation, so empty bodies (answered with 400) exhaust it as well.
    ${count}    ${response}=    Hit Until Limited    35    POST    /api/files
    Should Be True    ${count} <= 31    msg=Upload limiter allowed ${count} requests, expected at most 30 per hour
    Error Response Should Be Safe    ${response}

Upload limit does not affect another user
    [Documentation]    TC99-004. Expected result: Upload limit does not affect another user: user A can
    ...    still upload a file while user B is limited.
    ${response}=    Upload File    A    cv    ${PREFIX}-limit-other-user.txt    Robot upload    text/plain
    ...    retry_429=${False}
    Status Should Be    ${response}    201

General API limit answers with a safe 429 and rate limit headers
    [Documentation]    TC99-005. Expected result: General API limit answers with a safe 429 and rate limit headers.
    ${limit}=    Convert To Integer    ${API_RATE_LIMIT}
    ${count}    ${response}=    Hit Until Limited    ${limit + 10}    GET    /api/settings
    Should Be True    ${count} <= ${limit} + 1    msg=General limiter allowed ${count} requests, expected ${limit}
    Error Response Should Be Safe    ${response}
    ${headers}=    Set Variable    ${response.header('RateLimit')}${response.header('RateLimit-Policy')}${response.header('Retry-After')}
    Should Not Be Empty    ${headers}    msg=429 response carries no rate limit headers

General API limit is per user and does not lock out another user
    [Documentation]    TC99-006. Expected result: General API limit is per user and does not lock out another user.
    # No waiting on 429: a wait would let the window reset and hide a shared limit.
    ${response}=    Api Request    GET    /api/settings    user=A    retry_429=${False}
    Status Should Be    ${response}    200

Health check stays available while a user is limited
    [Documentation]    TC99-007. Expected result: Health check stays available while a user is limited.
    ${response}=    Api Request    GET    /api/health
    Status Should Be    ${response}    200
