*** Settings ***
Documentation     Suite 12b: Account deletion.
...               When Clerk reports user.deleted, ALL data of that user must be removed and
...               nobody else's data may be touched. DuuniCheck is invite-only, so the test users
...               cannot be created again by the tests. Instead the signed webhook is sent straight
...               to the backend for player B (the real Clerk user id is read from B's browser
...               session): the data is deleted and the Clerk account stays, so it can be used again.
...               Needs CLERK_WEBHOOK_SIGNING_SECRET in .env equal to the backend's value.
...               Deleting the real account in Clerk and receiving the webhook through a public
...               address (Render) is checked by hand, see the README.
...               Covers test cases TC12B-001 - TC12B-006.
Resource          ../resources/common.robot
Suite Setup       Prepare Deletion Suite
Suite Teardown    Finish API Suite
Force Tags        api    security    webhook    deletion


*** Keywords ***
Prepare Deletion Suite
    Prepare API Suite
    Require Config    CLERK_WEBHOOK_SIGNING_SECRET
    Switch To Player    B
    ${b_id}=    Get Current User Id
    Set Suite Variable    ${B_CLERK_ID}    ${b_id}

Seed Data For B
    [Documentation]    Gives player B an application, CV, template, file, conversation and theme.
    Delete All Data    B
    ${app}=    Create Application As    B    notes=B-SEEDED-DATA
    Create Cv As    B    summary=B-SEEDED-DATA
    Create Template As    B    body=B-SEEDED-DATA
    Upload Text File As    B    cv    ${PREFIX}-b-seeded.txt    B-SEEDED-DATA
    Api Request    POST    /api/conversations/${app}[id]/answer    user=B    json_body=${{ {'message': 'Näytä muistiinpanot'} }}
    Api Request    PUT    /api/settings    user=B    json_body=${{ {'theme': 'dark'} }}
    RETURN    ${app}[id]

Send Deletion Webhook
    [Arguments]    ${clerk_id}
    ${body}=    Set Variable    {"type":"user.deleted","object":"event","data":{"id":"${clerk_id}","deleted":true}}
    ${headers}=    Sign Webhook    ${body}
    ${response}=    Api Request    POST    /api/webhooks/clerk    raw_body=${body}    headers=${headers}
    RETURN    ${response}

B Data Should Be Gone
    [Documentation]    Polls because the deletion runs as a background job.
    FOR    ${attempt}    IN RANGE    15
        ${total}=    Set Variable    ${0}
        FOR    ${path}    IN    /api/applications    /api/cvs    /api/templates    /api/files
            ${listing}=    Api Request    GET    ${path}    user=B
            ${total}=    Evaluate    $total + len($listing.json)
        END
        IF    ${total} == 0    RETURN
        Sleep    1s
    END
    Fail    Player B's data still exists (${total} items) after the deletion webhook.


*** Test Cases ***
Deletion webhook removes all data of the deleted user
    [Documentation]    TC12B-001. Expected result: the webhook is accepted (202) and the user's
    ...    applications, CVs, templates, files, conversation and theme are gone.
    [Tags]    api    security
    ${app_id}=    Seed Data For B
    ${response}=    Send Deletion Webhook    ${B_CLERK_ID}
    Status Should Be    ${response}    202
    B Data Should Be Gone
    ${history}=    Api Request    GET    /api/conversations/${app_id}    user=B
    Status Should Be    ${history}    404
    ${settings}=    Api Request    GET    /api/settings    user=B
    Should Be Equal    ${settings.json}[theme]    default

Deleted user's file can no longer be downloaded
    [Documentation]    TC12B-002. Expected result: the file of a deleted user answers 404 and
    ...    its content is not returned.
    [Tags]    api    security
    Seed Data For B
    ${files}=    Api Request    GET    /api/files    user=B
    ${file_id}=    Set Variable    ${files.json}[0][id]
    Send Deletion Webhook    ${B_CLERK_ID}
    B Data Should Be Gone
    ${download}=    Api Request    GET    /api/files/${file_id}/download    user=B
    Status Should Be    ${download}    404
    Should Not Contain    ${download.text}    B-SEEDED-DATA

Deleting one user does not touch the data of other users
    [Documentation]    TC12B-003. Expected result: player A's data is still there after
    ...    player B's data was deleted.
    [Tags]    api    security
    Create Application As    A    notes=KEEP-ME-A
    Seed Data For B
    Send Deletion Webhook    ${B_CLERK_ID}
    B Data Should Be Gone
    ${a}=    Api Request    GET    /api/applications    user=A
    Should Contain    ${a.text}    KEEP-ME-A

Deletion webhook for an unknown user is harmless
    [Documentation]    TC12B-004. Expected result: 202 or 204 and nobody's data changes.
    [Tags]    api    security
    Create Application As    A    notes=KEEP-ME-A
    ${response}=    Send Deletion Webhook    user_robotneverexisted1
    Status Should Be One Of    ${response}    202    204
    ${a}=    Api Request    GET    /api/applications    user=A
    Should Contain    ${a.text}    KEEP-ME-A

Repeating the deletion webhook is harmless
    [Documentation]    TC12B-005. Expected result: a second webhook for the same user does not
    ...    fail and the server keeps running.
    [Tags]    api    security
    Seed Data For B
    Send Deletion Webhook    ${B_CLERK_ID}
    B Data Should Be Gone
    ${again}=    Send Deletion Webhook    ${B_CLERK_ID}
    Status Should Be One Of    ${again}    202    204
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

Wildcard-like ids in the deletion webhook cannot delete other users' data
    [Documentation]    TC12B-006. Expected result: ids such as user_* or .* delete nothing.
    [Tags]    api    security
    Create Application As    A    notes=KEEP-ME-A
    FOR    ${bad_id}    IN    user_*    user_    .*    ${EMPTY}
        ${body}=    Set Variable    {"type":"user.deleted","object":"event","data":{"id":"${bad_id}"}}
        ${headers}=    Sign Webhook    ${body}
        ${response}=    Api Request    POST    /api/webhooks/clerk    raw_body=${body}    headers=${headers}
        Should Be True    ${response.status} < 500    msg=${bad_id}: ${response.text}
    END
    ${list}=    Api Request    GET    /api/applications    user=A
    Should Contain    ${list.text}    KEEP-ME-A
