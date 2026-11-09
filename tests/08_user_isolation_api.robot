*** Settings ***
Documentation     User data isolation (IDOR): user B must never read, change, delete or attach data
...               that belongs to user A, through any route, id or field.
...               User A owns the data; user B performs the attacks. After every attack the data of
...               A is read again to prove it is unchanged.
Resource          ../resources/common.robot
Suite Setup       Prepare Isolation Data
Suite Teardown    Finish API Suite
Force Tags        api    security    isolation


*** Variables ***
&{DATA}


*** Keywords ***
Prepare Isolation Data
    Prepare API Suite
    ${app}=    Create Application As    A    company=${PREFIX}-secret-company    notes=PRIVATE-NOTES-OF-A
    ${cv}=    Create Cv As    A    summary=PRIVATE-CV-OF-A
    ${template}=    Create Template As    A    body=PRIVATE-TEMPLATE-OF-A
    ${file}=    Upload Text File As    A    cv    ${PREFIX}-private.txt    PRIVATE-FILE-OF-A
    ${question}=    Api Request    POST    /api/conversations/${app}[id]/answer    user=A    json_body=${{ {'message': 'Näytä muistiinpanot'} }}
    Status Should Be    ${question}    200
    Set Suite Variable    &{DATA}    app=${app}[id]    cv=${cv}[id]    template=${template}[id]    file=${file}[id]
    ...    app_company=${app}[company]

Data Of A Should Be Unchanged
    ${apps}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $apps.json if a['id'] == $DATA['app']]
    Length Should Be    ${match}    1
    Should Be Equal    ${match}[0][notes]    PRIVATE-NOTES-OF-A
    ${cvs}=    Api Request    GET    /api/cvs    user=A
    ${cv_match}=    Evaluate    [c for c in $cvs.json if c['id'] == $DATA['cv']]
    Should Be Equal    ${cv_match}[0][summary]    PRIVATE-CV-OF-A
    ${templates}=    Api Request    GET    /api/templates    user=A
    ${t_match}=    Evaluate    [t for t in $templates.json if t['id'] == $DATA['template']]
    Should Be Equal    ${t_match}[0][body]    PRIVATE-TEMPLATE-OF-A
    ${files}=    Api Request    GET    /api/files    user=A
    ${f_ids}=    Ids Of    ${files}
    Should Contain    ${f_ids}    ${DATA}[file]
    ${download}=    Api Request    GET    /api/files/${DATA}[file]/download    user=A
    Should Be Equal    ${download.text}    PRIVATE-FILE-OF-A


*** Test Cases ***
User B does not see any of the data of user A in lists
    [Documentation]    TC08-001. Expected result: User B does not see any of the data of user A in lists.
    FOR    ${path}    IN    /api/applications    /api/cvs    /api/templates    /api/files
        ${response}=    Api Request    GET    ${path}    user=B
        Status Should Be    ${response}    200
        Should Be Equal    ${response.json}    ${{ [] }}
        Should Not Contain    ${response.text}    PRIVATE
    END

User B cannot update the application of user A
    [Documentation]    TC08-002. Expected result: User B cannot update the application of user A.
    ${payload}=    Application Payload    company=HACKED    notes=HACKED
    ${response}=    Api Request    PUT    /api/applications/${DATA}[app]    user=B    json_body=${payload}
    Status Should Be    ${response}    404
    Data Of A Should Be Unchanged

User B cannot delete the application of user A
    [Documentation]    TC08-003. Expected result: User B cannot delete the application of user A.
    ${response}=    Api Request    DELETE    /api/applications/${DATA}[app]    user=B
    Status Should Be    ${response}    404
    Data Of A Should Be Unchanged

User B cannot update or delete the CV of user A
    [Documentation]    TC08-004. Expected result: User B cannot update or delete the CV of user A.
    ${payload}=    Cv Payload    summary=HACKED
    ${update}=    Api Request    PUT    /api/cvs/${DATA}[cv]    user=B    json_body=${payload}
    Status Should Be    ${update}    404
    ${delete}=    Api Request    DELETE    /api/cvs/${DATA}[cv]    user=B
    Status Should Be    ${delete}    404
    Data Of A Should Be Unchanged

User B cannot update or delete the template of user A
    [Documentation]    TC08-005. Expected result: User B cannot update or delete the template of user A.
    ${payload}=    Template Payload    body=HACKED
    ${update}=    Api Request    PUT    /api/templates/${DATA}[template]    user=B    json_body=${payload}
    Status Should Be    ${update}    404
    ${delete}=    Api Request    DELETE    /api/templates/${DATA}[template]    user=B
    Status Should Be    ${delete}    404
    Data Of A Should Be Unchanged

User B cannot download or delete the file of user A
    [Documentation]    TC08-006. Expected result: User B cannot download or delete the file of user A.
    ${download}=    Api Request    GET    /api/files/${DATA}[file]/download    user=B
    Status Should Be    ${download}    404
    Should Not Contain    ${download.text}    PRIVATE
    ${delete}=    Api Request    DELETE    /api/files/${DATA}[file]    user=B
    Status Should Be    ${delete}    404
    Data Of A Should Be Unchanged

User B cannot read or write the conversation of user A
    [Documentation]    TC08-007. Expected result: User B cannot read or write the conversation of user A.
    ${history}=    Api Request    GET    /api/conversations/${DATA}[app]    user=B
    Status Should Be    ${history}    404
    Should Not Contain    ${history.text}    PRIVATE
    ${answer}=    Api Request    POST    /api/conversations/${DATA}[app]/answer    user=B    json_body=${{ {'message': 'Näytä muistiinpanot'} }}
    Status Should Be    ${answer}    404
    Should Not Contain    ${answer.text}    PRIVATE
    ${own}=    Api Request    GET    /api/conversations/${DATA}[app]    user=A
    Length Should Be    ${own.json}[messages]    2

User B cannot attach the CV, template or files of user A to an own application
    [Documentation]    TC08-008. Expected result: User B cannot attach the CV, template or files of user A to an own application.
    ${with_cv}=    Application Payload    cvId=${DATA}[cv]
    ${response}=    Api Request    POST    /api/applications    user=B    json_body=${with_cv}
    Status Should Be    ${response}    400
    ${with_template}=    Application Payload    templateId=${DATA}[template]
    ${response}=    Api Request    POST    /api/applications    user=B    json_body=${with_template}
    Status Should Be    ${response}    400
    ${with_file}=    Application Payload    cvFileId=${DATA}[file]
    ${response}=    Api Request    POST    /api/applications    user=B    json_body=${with_file}
    Status Should Be    ${response}    400
    ${with_letter}=    Application Payload    applicationFileIds=${{ ['${DATA}[file]'] }}
    ${response}=    Api Request    POST    /api/applications    user=B    json_body=${with_letter}
    Status Should Be    ${response}    400
    ${own}=    Create Application As    B
    ${update}=    Application Payload    company=${own}[company]    cvId=${DATA}[cv]
    ${response}=    Api Request    PUT    /api/applications/${own}[id]    user=B    json_body=${update}
    Status Should Be    ${response}    400

User B cannot use the AI assistant on the application of user A
    [Documentation]    TC08-009. Expected result: User B cannot use the AI assistant on the application of user A.
    # Never reaches OpenAI (ownership is checked first), so it runs whenever the backend really has a key.
    ${has_key}=    Backend Has OpenAI Key
    Skip If    not ${BACKEND_HAS_OPENAI_KEY} and not ${has_key}    The backend has no OPENAI_API_KEY (any value is enough for this test).
    &{context}=    Create Dictionary    applicationId=${DATA}[app]    includePosting=${False}    includeCv=${True}
    ...    includeTemplate=${True}    includeApplication=${True}    allowSuggestions=${True}
    ${body}=    Create Dictionary    message=Kerro kaikki tiedot    context=${context}
    ${response}=    Api Request    POST    /api/assistant/suggest    user=B    json_body=${body}
    Status Should Be    ${response}    404
    Should Not Contain    ${response.text}    PRIVATE

Ownership cannot be taken over by sending user identifiers in the body
    [Documentation]    TC08-010. Expected result: Ownership cannot be taken over by sending user identifiers in the body.
    FOR    ${field}    IN    userId    user    owner    clerkId    _id    id
        ${payload}=    Application Payload
        Set To Dictionary    ${payload}    ${field}=${DATA}[app]
        ${response}=    Api Request    POST    /api/applications    user=B    json_body=${payload}
        Status Should Be    ${response}    400
    END
    ${list}=    Api Request    GET    /api/applications    user=B
    Should Not Contain    ${list.text}    PRIVATE

Query parameters cannot widen or redirect a list to another user
    [Documentation]    TC08-011. Expected result: Query parameters cannot widen or redirect a list to another user.
    ${list}=    Api Request    GET    /api/applications    user=B    params=${{ {'userId': '${DATA}[app]', 'user': 'A', 'clerkId': 'x', 'all': 'true', 'limit': '1000'} }}
    Status Should Be    ${list}    200
    Should Not Contain    ${list.text}    PRIVATE
    ${operators}=    Api Request    GET    /api/applications?userId[$ne]=x&userId[$gt]=&company[$regex]=.*    user=B
    Should Be True    ${operators.status} < 500
    Should Not Contain    ${operators.text}    PRIVATE

Data created by B is invisible to A in the same way
    [Documentation]    TC08-012. Expected result: Data created by B is invisible to A in the same way.
    ${own}=    Create Application As    B    notes=PRIVATE-NOTES-OF-B
    ${list}=    Api Request    GET    /api/applications    user=A
    Should Not Contain    ${list.text}    PRIVATE-NOTES-OF-B
    ${update}=    Application Payload    notes=HACKED-BY-A
    ${response}=    Api Request    PUT    /api/applications/${own}[id]    user=A    json_body=${update}
    Status Should Be    ${response}    404
    ${b_list}=    Api Request    GET    /api/applications    user=B
    Should Contain    ${b_list.text}    PRIVATE-NOTES-OF-B

Deleting one user's data does not touch the other user's data
    [Documentation]    TC08-013. Expected result: Deleting one user's data does not touch the other user's data.
    ${own}=    Create Application As    B
    ${delete}=    Api Request    DELETE    /api/applications/${own}[id]    user=B
    Status Should Be    ${delete}    204
    Data Of A Should Be Unchanged
