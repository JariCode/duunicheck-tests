*** Settings ***
Documentation     Applications API: create, read, update, delete and every server-side validation rule.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    applications


*** Test Cases ***
Application can be created with only the required fields
    [Documentation]    TC03-001. Expected result: Application can be created with only the required fields.
    ${payload}=    Application Payload
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[company]    ${payload}[company]
    Should Be Equal    ${response.json}[status]    Kiinnostava
    Should Not Be Empty    ${response.json}[id]
    Should Be Equal    ${response.json}[place]    ${EMPTY}
    Should Be Equal    ${response.json}[events]    ${{ [] }}
    Should Be Equal    ${response.json}[applicationFileIds]    ${{ [] }}
    Response Should Not Contain Internal Fields    ${response}

Application can be created with every field filled
    [Documentation]    TC03-002. Expected result: Application can be created with every field filled.
    &{event}=    Create Dictionary    id=1    type=Lähetetty    date=2026-01-05    note=Lähetetty sähköpostilla
    ${payload}=    Application Payload    place=Helsinki · hybridi    link=https://example.com/job/1
    ...    notes=Muistiinpano    applicationText=Hakemusteksti    status=Lähetetty    respondedAt=2026-01-10
    ...    next=Soita rekrytoijalle    nextDate=2026-01-12    added=2026-01-05    events=${{ [$event] }}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[place]    Helsinki · hybridi
    Should Be Equal    ${response.json}[events][0][note]    Lähetetty sähköpostilla
    Should Be Equal    ${response.json}[nextDate]    2026-01-12

Created application appears in the own list without private fields
    [Documentation]    TC03-003. Expected result: Created application appears in the own list without private fields.
    ${created}=    Create Application As    A
    ${list}=    Api Request    GET    /api/applications    user=A
    Status Should Be    ${list}    200
    ${ids}=    Ids Of    ${list}
    Should Contain    ${ids}    ${created}[id]
    Response Should Not Contain Internal Fields    ${list}

List is sorted by last update, newest first
    [Documentation]    TC03-004. Expected result: List is sorted by last update, newest first.
    ${first}=    Create Application As    A    company=${PREFIX}-sort-first
    ${second}=    Create Application As    A    company=${PREFIX}-sort-second
    ${payload}=    Application Payload    company=${PREFIX}-sort-first    role=Updated
    ${update}=    Api Request    PUT    /api/applications/${first}[id]    user=A    json_body=${payload}
    Status Should Be    ${update}    200
    ${list}=    Api Request    GET    /api/applications    user=A
    ${ids}=    Ids Of    ${list}
    ${first_index}=    Get Index From List    ${ids}    ${first}[id]
    ${second_index}=    Get Index From List    ${ids}    ${second}[id]
    Should Be True    ${first_index} < ${second_index}

Application can be updated and changes persist
    [Documentation]    TC03-005. Expected result: Application can be updated and changes persist.
    ${created}=    Create Application As    A
    ${payload}=    Application Payload    company=${created}[company]    role=Senior Tester    status=Haastattelu sovittu    notes=Uusi muistiinpano
    ${update}=    Api Request    PUT    /api/applications/${created}[id]    user=A    json_body=${payload}
    Status Should Be    ${update}    200
    Should Be Equal    ${update.json}[role]    Senior Tester
    ${list}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $list.json if a['id'] == $created['id']][0]
    Should Be Equal    ${match}[status]    Haastattelu sovittu
    Should Be Equal    ${match}[notes]    Uusi muistiinpano

Application can be deleted and a second delete returns 404
    [Documentation]    TC03-006. Expected result: Application can be deleted and a second delete returns 404.
    ${created}=    Create Application As    A
    ${delete}=    Api Request    DELETE    /api/applications/${created}[id]    user=A
    Status Should Be    ${delete}    204
    ${again}=    Api Request    DELETE    /api/applications/${created}[id]    user=A
    Status Should Be    ${again}    404
    ${list}=    Api Request    GET    /api/applications    user=A
    ${ids}=    Ids Of    ${list}
    Should Not Contain    ${ids}    ${created}[id]

Update and delete of a missing application return 404
    [Documentation]    TC03-007. Expected result: Update and delete of a missing application return 404.
    ${payload}=    Application Payload
    ${update}=    Api Request    PUT    /api/applications/${MISSING_ID}    user=A    json_body=${payload}
    Status Should Be    ${update}    404
    ${delete}=    Api Request    DELETE    /api/applications/${MISSING_ID}    user=A
    Status Should Be    ${delete}    404

Malformed identifiers are rejected with 400
    [Documentation]    TC03-008. Expected result: Malformed identifiers are rejected with 400.
    ${payload}=    Application Payload
    FOR    ${bad_id}    IN    abc    123    ${MISSING_ID}0    00000000000000000000000    zzzzzzzzzzzzzzzzzzzzzzzz    %24ne    ..%2F..%2Fetc
        ${update}=    Api Request    PUT    /api/applications/${bad_id}    user=A    json_body=${payload}
        Status Should Be    ${update}    400
        ${delete}=    Api Request    DELETE    /api/applications/${bad_id}    user=A
        Status Should Be    ${delete}    400
    END

Text fields are trimmed and unicode is preserved
    [Documentation]    TC03-009. Expected result: Text fields are trimmed and unicode is preserved.
    ${created}=    Create Application As    A    company=${SPACE}${SPACE}Äö Åkesson Oy ✓${SPACE}    role=Kehittäjä
    Should Be Equal    ${created}[company]    Äö Åkesson Oy ✓

Required fields company and role must not be empty
    [Documentation]    TC03-010. Expected result: Required fields company and role must not be empty.
    FOR    ${field}    IN    company    role
        FOR    ${value}    IN    ${EMPTY}    ${SPACE}${SPACE}${SPACE}
            ${payload}=    Application Payload    ${field}=${value}
            ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
            Status Should Be    ${response}    400
            Error Response Should Be Safe    ${response}
        END
        ${payload}=    Application Payload
        Remove From Dictionary    ${payload}    ${field}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Status must be one of the five allowed values
    [Documentation]    TC03-011. Expected result: Status must be one of the five allowed values (Kiinnostava,
    ...    Lähetetty, Haastattelu sovittu, Hyväksytty, Hylätty); other spellings, old names and other types are refused.
    FOR    ${status}    IN    kiinnostava    hyväksytty    Hyväksytty${SPACE}    Accepted    Odottaa vastausta    Haastattelu    Tarjous    ${EMPTY}    <script>    ${123}
        ${payload}=    Application Payload    status=${status}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END
    ${payload}=    Application Payload
    Remove From Dictionary    ${payload}    status
    ${missing}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${missing}    400
    FOR    ${status}    IN    Kiinnostava    Lähetetty    Haastattelu sovittu    Hyväksytty    Hylätty
        ${payload}=    Application Payload    status=${status}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    201
    END

Text length limits are enforced
    [Documentation]    TC03-012. Expected result: Text length limits are enforced.
    ${too_long}=    Evaluate    'x' * 161
    ${at_limit}=    Evaluate    'x' * 160
    FOR    ${field}    IN    company    role    place
        ${payload}=    Application Payload    ${field}=${too_long}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
        ${payload}=    Application Payload    ${field}=${at_limit}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    201
    END
    ${notes}=    Evaluate    'n' * 8001
    ${payload}=    Application Payload    notes=${notes}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    ${text}=    Evaluate    't' * 20001
    ${payload}=    Application Payload    applicationText=${text}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    ${next}=    Evaluate    'x' * 201
    ${payload}=    Application Payload    next=${next}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400

Job posting link accepts only http and https URLs
    [Documentation]    TC03-013. Expected result: Job posting link accepts only http and https URLs.
    FOR    ${link}    IN    javascript:alert(1)    data:text/html,<script>alert(1)</script>    ftp://example.com/file    file:///etc/passwd
    ...    not a url    //example.com    vbscript:msgbox(1)
        ${payload}=    Application Payload    link=${link}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END
    ${long_link}=    Evaluate    'https://example.com/' + 'a' * 2040
    ${payload}=    Application Payload    link=${long_link}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    FOR    ${link}    IN    https://example.com/job?id=1    http://example.com/job    ${EMPTY}
        ${payload}=    Application Payload    link=${link}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    201
    END

Date fields require the YYYY-MM-DD format
    [Documentation]    TC03-014. Expected result: Date fields require the YYYY-MM-DD format.
    FOR    ${field}    IN    added    respondedAt    nextDate
        FOR    ${value}    IN    5.1.2026    2026/01/05    2026-1-5    tomorrow    <script>    20260105    2026-01-05T10:00:00
            ${payload}=    Application Payload    ${field}=${value}
            ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
            Status Should Be    ${response}    400
        END
    END

Impossible calendar dates are rejected
    [Documentation]    TC03-015. Expected result: Impossible calendar dates are rejected with 400. A value
    ...                such as 2026-13-45 matches the format but is not a date; the frontend formats
    ...                dates with Intl.DateTimeFormat, which throws on an invalid date and would break
    ...                the user's whole view.
    FOR    ${value}    IN    2026-13-45    2026-00-10    2026-02-30    0000-00-00    9999-99-99
        ${payload}=    Application Payload    nextDate=${value}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Unknown fields are rejected, including mass assignment attempts
    [Documentation]    TC03-016. Expected result: Unknown fields are rejected, including mass assignment attempts.
    FOR    ${field}    IN    userId    _id    id    createdAt    updatedAt    isAdmin    role2    __proto__    constructor    $set    a.b
        ${payload}=    Application Payload
        Set To Dictionary    ${payload}    ${field}=evil
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
        Error Response Should Be Safe    ${response}
    END

Wrong JSON types for text fields are rejected
    [Documentation]    TC03-017. Expected result: Wrong JSON types for text fields are rejected.
    FOR    ${value}    IN    ${123}    ${True}    ${None}    ${{ ['a'] }}    ${{ {'a': 1} }}
        ${payload}=    Application Payload    company=${value}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Request body must be a JSON object
    [Documentation]    TC03-018. Expected result: Request body must be a JSON object.
    FOR    ${body}    IN    []    "text"    123    null    true    ${EMPTY}
        ${response}=    Api Request    POST    /api/applications    user=A    raw_body=${body}
        Status Should Be    ${response}    400
        Error Response Should Be Safe    ${response}
    END

Event history validation
    [Documentation]    TC03-019. Expected result: Event history validation.
    ${long_note}=    Evaluate    'n' * 2001
    ${long_type}=    Evaluate    't' * 101
    &{valid}=    Create Dictionary    type=Lähetetty    date=2026-01-05    note=ok
    &{bad_note}=    Create Dictionary    type=Lähetetty    date=2026-01-05    note=${long_note}
    &{bad_type}=    Create Dictionary    type=${long_type}    date=2026-01-05
    &{bad_date}=    Create Dictionary    type=Lähetetty    date=5.1.2026
    &{bad_key}=    Create Dictionary    type=Lähetetty    date=2026-01-05    extra=x
    &{bad_id}=    Create Dictionary    id=${{ {'$ne': 1} }}    type=Lähetetty    date=2026-01-05
    ${ok}=    Application Payload    events=${{ [$valid] }}
    ${accepted}=    Api Request    POST    /api/applications    user=A    json_body=${ok}
    Status Should Be    ${accepted}    201
    FOR    ${event}    IN    ${bad_note}    ${bad_type}    ${bad_date}    ${bad_key}    ${bad_id}
        ${payload}=    Application Payload    events=${{ [$event] }}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Event history is limited to 300 entries
    [Documentation]    TC03-020. Expected result: Event history is limited to 300 entries.
    &{event}=    Create Dictionary    type=Lähetetty    date=2026-01-05
    ${events_ok}=    Evaluate    [dict($event) for _ in range(300)]
    ${events_too_many}=    Evaluate    [dict($event) for _ in range(301)]
    ${payload}=    Application Payload    events=${events_too_many}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    ${payload}=    Application Payload    events=${events_ok}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    201

Failed update leaves the stored application unchanged
    [Documentation]    TC03-021. Expected result: Failed update leaves the stored application unchanged.
    ${created}=    Create Application As    A    notes=original
    ${bad}=    Application Payload    company=${created}[company]    notes=changed    status=Invalid
    ${response}=    Api Request    PUT    /api/applications/${created}[id]    user=A    json_body=${bad}
    Status Should Be    ${response}    400
    ${list}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $list.json if a['id'] == $created['id']][0]
    Should Be Equal    ${match}[notes]    original

Application can reference an own CV and an own template
    [Documentation]    TC03-022. Expected result: Application can reference an own CV and an own template.
    ${cv}=    Create Cv As    A
    ${template}=    Create Template As    A
    ${payload}=    Application Payload    cvId=${cv}[id]    templateId=${template}[id]
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[cvId]    ${cv}[id]

References to missing or malformed CV and template ids are rejected
    [Documentation]    TC03-023. Expected result: References to missing or malformed CV and template ids are rejected.
    FOR    ${field}    IN    cvId    templateId
        FOR    ${value}    IN    ${MISSING_ID}    abc    {"$ne":null}
            ${payload}=    Application Payload    ${field}=${value}
            ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
            Status Should Be    ${response}    400
            Error Response Should Be Safe    ${response}
        END
    END

CV file and app CV cannot be combined, nor template and letter file
    [Documentation]    TC03-024. Expected result: CV file and app CV cannot be combined, nor template and letter file.
    ${cv}=    Create Cv As    A
    ${template}=    Create Template As    A
    ${cv_file}=    Upload Text File As    A    cv    ${PREFIX}-cv.txt
    ${letter_file}=    Upload Text File As    A    application    ${PREFIX}-letter.txt
    ${both_cv}=    Application Payload    cvId=${cv}[id]    cvFileId=${cv_file}[id]
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${both_cv}
    Status Should Be    ${response}    400
    ${both_letter}=    Application Payload    templateId=${template}[id]    applicationFileIds=${{ ['${letter_file}[id]'] }}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${both_letter}
    Status Should Be    ${response}    400
    ${valid}=    Application Payload    cvFileId=${cv_file}[id]    applicationFileIds=${{ ['${letter_file}[id]'] }}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${valid}
    Status Should Be    ${response}    201

Attached files must come from the matching library
    [Documentation]    TC03-025. Expected result: Attached files must come from the matching library.
    ${cv_file}=    Upload Text File As    A    cv    ${PREFIX}-cv2.txt
    ${letter_file}=    Upload Text File As    A    application    ${PREFIX}-letter2.txt
    ${wrong_cv}=    Application Payload    cvFileId=${letter_file}[id]
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${wrong_cv}
    Status Should Be    ${response}    400
    ${wrong_letter}=    Application Payload    applicationFileIds=${{ ['${cv_file}[id]'] }}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${wrong_letter}
    Status Should Be    ${response}    400

File id lists are validated
    [Documentation]    TC03-026. Expected result: File id lists are validated.
    ${too_many}=    Evaluate    ['a' * 24 for _ in range(11)]
    ${payload}=    Application Payload    applicationFileIds=${too_many}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    FOR    ${bad}    IN    not-an-id    ${{ {'$ne': 1} }}    ${123}
        ${payload}=    Application Payload    applicationFileIds=${{ [$bad] }}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END
    ${payload}=    Application Payload    cvFileId=not-an-id
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${response}    400

Deleting an application also removes its conversation
    [Documentation]    TC03-027. Expected result: Deleting an application also removes its conversation.
    ${created}=    Create Application As    A
    ${question}=    Api Request    POST    /api/conversations/${created}[id]/answer    user=A    json_body=${{ {'message': 'Mikä on tila?'} }}
    Status Should Be    ${question}    200
    ${delete}=    Api Request    DELETE    /api/applications/${created}[id]    user=A
    Status Should Be    ${delete}    204
    ${history}=    Api Request    GET    /api/conversations/${created}[id]    user=A
    Status Should Be    ${history}    404

Application limit of 500 per user is enforced
    [Documentation]    TC03-028. Creates 500 applications, so it only runs when RUN_SLOW=true in .env.
    [Tags]    slow
    Skip If    not ${RUN_SLOW}    Set RUN_SLOW=true in .env to run the limit test.
    Clean Up User A
    FOR    ${index}    IN RANGE    500
        ${payload}=    Application Payload
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Status Should Be    ${response}    201
    END
    ${payload}=    Application Payload
    ${over}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Status Should Be    ${over}    413
    [Teardown]    Clean Up User A

Status Hyväksytty is stored, returned and can be set with an update
    [Documentation]    TC03-029. Expected result: an application created with status Hyväksytty and a
    ...    Hyväksytty event is stored and returned as such in the own list, an application in stage Lähetetty
    ...    can be updated to Hyväksytty, and an unknown status in an update is still refused with 400 and
    ...    leaves the stored status unchanged.
    &{event}=    Create Dictionary    id=1    type=Hyväksytty    date=2026-04-01    note=Työsopimus allekirjoitettu
    ${created}=    Create Application As    A    status=Hyväksytty    respondedAt=2026-04-01    events=${{ [$event] }}
    Should Be Equal    ${created}[status]    Hyväksytty
    Should Be Equal    ${created}[events][0][type]    Hyväksytty
    ${list}=    Api Request    GET    /api/applications    user=A
    ${stored}=    Evaluate    [a for a in $list.json if a['id'] == $created['id']][0]
    Should Be Equal    ${stored}[status]    Hyväksytty
    Should Be Equal    ${stored}[respondedAt]    2026-04-01
    ${sent}=    Create Application As    A    status=Lähetetty
    ${payload}=    Application Payload    company=${sent}[company]    role=${sent}[role]    status=Hyväksytty
    ${updated}=    Api Request    PUT    /api/applications/${sent}[id]    user=A    json_body=${payload}
    Status Should Be    ${updated}    200
    Should Be Equal    ${updated.json}[status]    Hyväksytty
    ${payload}=    Application Payload    company=${sent}[company]    role=${sent}[role]    status=Tarjous hyväksytty
    ${refused}=    Api Request    PUT    /api/applications/${sent}[id]    user=A    json_body=${payload}
    Status Should Be    ${refused}    400
    Error Response Should Be Safe    ${refused}
    ${list}=    Api Request    GET    /api/applications    user=A
    ${after}=    Evaluate    [a for a in $list.json if a['id'] == $sent['id']][0]
    Should Be Equal    ${after}[status]    Hyväksytty
