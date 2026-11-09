*** Settings ***
Documentation     CV and application template (hakemuspohja) APIs: CRUD and validation, including
...               the profile photo data URI, e-mail and link fields.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    materials


*** Test Cases ***
CV can be created, listed, updated and deleted
    [Documentation]    TC04-001. Expected result: CV can be created, listed, updated and deleted.
    ${created}=    Create Cv As    A    title=Testaaja    summary=Profiili    skills=Robot Framework\nPython
    Should Not Be Empty    ${created}[id]
    Dictionary Should Not Contain Key    ${created}    userId
    Dictionary Should Not Contain Key    ${created}    _id
    ${list}=    Api Request    GET    /api/cvs    user=A
    Status Should Be    ${list}    200
    ${ids}=    Ids Of    ${list}
    Should Contain    ${ids}    ${created}[id]
    Response Should Not Contain Internal Fields    ${list}
    ${payload}=    Cv Payload    name=${created}[name]    title=Päivitetty
    ${update}=    Api Request    PUT    /api/cvs/${created}[id]    user=A    json_body=${payload}
    Status Should Be    ${update}    200
    Should Be Equal    ${update.json}[title]    Päivitetty
    ${delete}=    Api Request    DELETE    /api/cvs/${created}[id]    user=A
    Status Should Be    ${delete}    204
    ${again}=    Api Request    DELETE    /api/cvs/${created}[id]    user=A
    Status Should Be    ${again}    404

Template can be created, listed, updated and deleted
    [Documentation]    TC04-002. Expected result: Template can be created, listed, updated and deleted.
    ${created}=    Create Template As    A    fullName=Testaaja    body=Hei maailma
    Dictionary Should Not Contain Key    ${created}    userId
    ${list}=    Api Request    GET    /api/templates    user=A
    ${ids}=    Ids Of    ${list}
    Should Contain    ${ids}    ${created}[id]
    ${payload}=    Template Payload    name=${created}[name]    body=Muokattu teksti
    ${update}=    Api Request    PUT    /api/templates/${created}[id]    user=A    json_body=${payload}
    Status Should Be    ${update}    200
    Should Be Equal    ${update.json}[body]    Muokattu teksti
    ${delete}=    Api Request    DELETE    /api/templates/${created}[id]    user=A
    Status Should Be    ${delete}    204

CV name and full name are required
    [Documentation]    TC04-003. Expected result: CV name and full name are required.
    FOR    ${field}    IN    name    fullName
        ${payload}=    Cv Payload    ${field}=${EMPTY}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
        Status Should Be    ${response}    400
        ${payload}=    Cv Payload
        Remove From Dictionary    ${payload}    ${field}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Template name is required
    [Documentation]    TC04-004. Expected result: Template name is required.
    ${payload}=    Template Payload    name=${SPACE}
    ${response}=    Api Request    POST    /api/templates    user=A    json_body=${payload}
    Status Should Be    ${response}    400

CV text length limits are enforced
    [Documentation]    TC04-005. Expected result: CV text length limits are enforced.
    ${limits}=    Create Dictionary    name=120    fullName=160    title=160    phone=40    summary=5000    skills=5000
    ...    experience=12000    education=8000    certificates=5000    courses=5000    languages=3000    hobbies=3000
    FOR    ${field}    ${limit}    IN    &{limits}
        ${over}=    Evaluate    'x' * (int($limit) + 1)
        ${payload}=    Cv Payload    ${field}=${over}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
        Status Should Be    ${response}    400
    END

Template text length limits are enforced
    [Documentation]    TC04-006. Expected result: Template text length limits are enforced.
    ${over_body}=    Evaluate    'x' * 20001
    ${payload}=    Template Payload    body=${over_body}
    ${response}=    Api Request    POST    /api/templates    user=A    json_body=${payload}
    Status Should Be    ${response}    400
    ${over_name}=    Evaluate    'x' * 121
    ${payload}=    Template Payload    name=${over_name}
    ${response}=    Api Request    POST    /api/templates    user=A    json_body=${payload}
    Status Should Be    ${response}    400

E-mail addresses are validated in CVs and templates
    [Documentation]    TC04-007. Expected result: E-mail addresses are validated in CVs and templates.
    FOR    ${email}    IN    not-an-email    @example.com    a b@example.com    <script>@x.fi
        ${cv}=    Cv Payload    email=${email}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
        Status Should Be    ${response}    400
        ${template}=    Template Payload    email=${email}
        ${response}=    Api Request    POST    /api/templates    user=A    json_body=${template}
        Status Should Be    ${response}    400
    END
    ${cv}=    Cv Payload    email=nimi@esimerkki.fi
    ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
    Status Should Be    ${response}    201

Profile links accept only http and https URLs
    [Documentation]    TC04-008. Expected result: Profile links accept only http and https URLs.
    FOR    ${field}    IN    linkedin    github    portfolio    website
        FOR    ${link}    IN    javascript:alert(1)    data:text/html,x    ftp://example.com    not a url
            ${cv}=    Cv Payload    ${field}=${link}
            ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
            Status Should Be    ${response}    400
            ${template}=    Template Payload    ${field}=${link}
            ${response}=    Api Request    POST    /api/templates    user=A    json_body=${template}
            Status Should Be    ${response}    400
        END
        ${cv}=    Cv Payload    ${field}=https://example.com/profile
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
        Status Should Be    ${response}    201
    END

Valid PNG profile photo is accepted
    [Documentation]    TC04-009. Expected result: Valid PNG profile photo is accepted.
    ${photo}=    Png Data Uri    8    8
    ${cv}=    Cv Payload    photo=${photo}
    ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[photo]    ${photo}

Dangerous or malformed profile photos are rejected
    [Documentation]    TC04-010. Expected result: Dangerous or malformed profile photos are rejected.
    ${svg}=    Evaluate    'data:image/svg+xml;base64,' + __import__('base64').b64encode(b'<svg onload=alert(1)>').decode()
    ${html}=    Set Variable    data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
    ${gif}=    Set Variable    data:image/gif;base64,R0lGODlhAQABAAAAACw=
    ${bad_chars}=    Set Variable    data:image/png;base64,@@@@@@
    ${remote}=    Set Variable    https://example.com/photo.png
    ${script}=    Set Variable    javascript:alert(1)
    ${spaces}=    Set Variable    data:image/png;base64,AAAA AAAA
    FOR    ${photo}    IN    ${svg}    ${html}    ${gif}    ${bad_chars}    ${remote}    ${script}    ${spaces}
        ${cv}=    Cv Payload    photo=${photo}
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
        Status Should Be    ${response}    400
    END

Oversized profile photo is rejected
    [Documentation]    TC04-011. Expected result: Oversized profile photo is rejected.
    ${huge}=    Evaluate    'data:image/png;base64,' + 'A' * 700001
    ${cv}=    Cv Payload    photo=${huge}
    ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
    Status Should Be    ${response}    400

Unknown fields are rejected in CVs and templates
    [Documentation]    TC04-012. Expected result: Unknown fields are rejected in CVs and templates.
    FOR    ${field}    IN    userId    _id    id    isAdmin    __proto__    $where
        ${cv}=    Cv Payload
        Set To Dictionary    ${cv}    ${field}=evil
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${cv}
        Status Should Be    ${response}    400
        ${template}=    Template Payload
        Set To Dictionary    ${template}    ${field}=evil
        ${response}=    Api Request    POST    /api/templates    user=A    json_body=${template}
        Status Should Be    ${response}    400
    END

Malformed ids are rejected and missing ids return 404
    [Documentation]    TC04-013. Expected result: Malformed ids are rejected and missing ids return 404.
    FOR    ${resource}    IN    cvs    templates
        ${payload}=    Cv Payload
        ${bad}=    Api Request    PUT    /api/${resource}/abc    user=A    json_body=${payload}
        Status Should Be    ${bad}    400
        ${delete_bad}=    Api Request    DELETE    /api/${resource}/abc    user=A
        Status Should Be    ${delete_bad}    400
        ${missing}=    Api Request    DELETE    /api/${resource}/${MISSING_ID}    user=A
        Status Should Be    ${missing}    404
    END

CV limit of 25 per user is enforced
    [Documentation]    TC04-014. Creates 25 CVs, so it only runs when RUN_SLOW=true in .env.
    ...    Starts from an empty account, because earlier tests of the suite leave CVs behind.
    [Tags]    slow
    Skip If    not ${RUN_SLOW}    Set RUN_SLOW=true in .env to run the limit test.
    Clean Up User A
    ${cvs}=    Api Request    GET    /api/cvs    user=A
    Should Be Empty    ${cvs.json}    msg=User A still has CVs before the limit test
    FOR    ${index}    IN RANGE    25
        ${payload}=    Cv Payload
        ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
        Status Should Be    ${response}    201
    END
    ${payload}=    Cv Payload
    ${over}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
    Status Should Be    ${over}    413
    [Teardown]    Clean Up User A
