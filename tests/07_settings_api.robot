*** Settings ***
Documentation     Theme settings API: default value, valid values, validation and per-user separation.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    settings


*** Test Cases ***
New user has the default theme
    [Documentation]    TC07-001. Expected result: New user has the default theme.
    ${response}=    Api Request    GET    /api/settings    user=A
    Status Should Be    ${response}    200
    Should Be Equal    ${response.json}[theme]    default

Each allowed theme can be saved and read back
    [Documentation]    TC07-002. Expected result: Each allowed theme can be saved and read back.
    FOR    ${theme}    IN    dark    light    default
        ${save}=    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': '${theme}'} }}
        Status Should Be    ${save}    200
        Should Be Equal    ${save.json}[theme]    ${theme}
        ${read}=    Api Request    GET    /api/settings    user=A
        Should Be Equal    ${read.json}[theme]    ${theme}
    END

Invalid themes are rejected
    [Documentation]    TC07-003. Expected result: Invalid themes are rejected.
    FOR    ${theme}    IN    blue    DARK    ${EMPTY}    <script>    default;dark    ${123}    ${None}    ${True}
        ${response}=    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': $theme} }}
        Status Should Be    ${response}    400
        Error Response Should Be Safe    ${response}
    END

Operator objects and arrays are rejected as theme
    [Documentation]    TC07-004. Expected result: Operator objects and arrays are rejected as theme.
    FOR    ${theme}    IN    ${{ {'$ne': 'x'} }}    ${{ {'$gt': ''} }}    ${{ ['dark'] }}    ${{ {'$where': 'sleep(1000)'} }}
        ${response}=    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': $theme} }}
        Status Should Be    ${response}    400
    END

Extra or missing fields are rejected
    [Documentation]    TC07-005. Expected result: Extra or missing fields are rejected.
    FOR    ${body}    IN    ${{ {} }}    ${{ {'theme': 'dark', 'isAdmin': True} }}    ${{ {'clerkId': 'user_x'} }}
    ...    ${{ {'theme': 'dark', 'clerkId': 'user_x'} }}    ${{ {'__proto__': {'theme': 'dark'}} }}
        ${response}=    Api Request    PUT    /api/settings    user=A    json_body=${body}
        Status Should Be    ${response}    400
    END

Request body must be a JSON object
    [Documentation]    TC07-006. Expected result: Request body must be a JSON object.
    FOR    ${body}    IN    []    "dark"    null    123
        ${response}=    Api Request    PUT    /api/settings    user=A    raw_body=${body}
        Status Should Be    ${response}    400
    END

Theme of one user does not change the theme of another
    [Documentation]    TC07-007. Expected result: Theme of one user does not change the theme of another.
    ${a}=    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'dark'} }}
    Status Should Be    ${a}    200
    ${b}=    Api Request    GET    /api/settings    user=B
    Should Be Equal    ${b.json}[theme]    default
    ${b_save}=    Api Request    PUT    /api/settings    user=B    json_body=${{ {'theme': 'light'} }}
    ${a_read}=    Api Request    GET    /api/settings    user=A
    Should Be Equal    ${a_read.json}[theme]    dark

Settings response contains only the theme
    [Documentation]    TC07-008. Expected result: Settings response contains only the theme.
    ${response}=    Api Request    GET    /api/settings    user=A
    ${keys}=    Get Dictionary Keys    ${response.json}
    Should Be Equal    ${keys}    ${{ ['theme'] }}

The clerkId of the user cannot be changed through settings
    [Documentation]    TC07-009. Expected result: The clerkId of the user cannot be changed through settings.
    ${before}=    Api Request    GET    /api/settings    user=A
    ${attempt}=    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'dark', 'clerkId': 'user_other'} }}
    Status Should Be    ${attempt}    400
    ${after}=    Api Request    GET    /api/settings    user=A
    Status Should Be    ${after}    200
