*** Settings ***
Documentation     Stored XSS in the UI: hostile strings are stored through the API and then rendered
...               by the real frontend. No script may run, no handler attribute may appear, and
...               external links must not give the target page access to the app window.
Resource          ../resources/common.robot
Suite Setup       Prepare UI Suite
Suite Teardown    Prepare Cleanup
Force Tags        ui    browser    security    xss


*** Variables ***
@{SECTIONS}    Yleiskatsaus    Hakemukset    Eteneminen    Kalenteri    CV & pohjat    AI-chat
@{XSS}
...    <script>window.__xss=1</script>
...    <img src=x onerror="window.__xss=1">
...    "><svg onload=window.__xss=1>
...    <a href="javascript:window.__xss=1">x</a>
...    <iframe srcdoc="<script>parent.__xss=1</script>"></iframe>
...    <details open ontoggle=window.__xss=1>


*** Keywords ***
Prepare UI Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    FOR    ${payload}    IN    @{XSS}
        ${app}=    Application Payload    company=${payload}    role=${payload}    notes=${payload}    place=${payload}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${app}
        Status Should Be    ${response}    201
        ${cv}=    Cv Payload    title=${payload}    summary=${payload}
        Api Request    POST    /api/cvs    user=A    json_body=${cv}
        ${tpl}=    Template Payload    body=${payload}
        Api Request    POST    /api/templates    user=A    json_body=${tpl}
    END
    Handle Dialogs Dismissing
    Reload
    Wait For Workspace

Prepare Cleanup
    Run Keyword And Ignore Error    Delete All Data    A
    Close Browser    ALL


*** Test Cases ***
Hostile application data does not execute scripts in any view
    [Documentation]    TC15-001. Expected result: Hostile application data does not execute scripts in any view.
    FOR    ${section}    IN    @{SECTIONS}
        Go To Section    ${section}
        Script Marker Should Be Unset
    END

Hostile strings are shown as text, not as elements
    [Documentation]    TC15-002. Expected result: Hostile strings are shown as text, not as elements.
    Go To Section    Hakemukset
    Get Element Count    css=main script    ==    0
    Get Element Count    css=main img[src="x"]    ==    0
    Get Element Count    css=main iframe    ==    0
    Get Element Count    css=main svg[onload]    ==    0

No element in the page has an inline event handler from user data
    [Documentation]    TC15-003. Expected result: No element in the page has an inline event handler from user data.
    ...    Every section is checked, so the result does not depend on the view an earlier test left open.
    FOR    ${section}    IN    @{SECTIONS}
        Go To Section    ${section}
        ${handlers}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('*')).filter(e => Array.from(e.attributes).some(a => /^on/i.test(a.name))).length
        Should Be Equal As Integers    ${handlers}    0    msg=Inline event handler found in ${section}
    END

No link from user data uses a javascript: URL
    [Documentation]    TC15-004. Expected result: No link from user data uses a javascript: URL.
    ...    Every section is checked, so the result does not depend on the view an earlier test left open.
    FOR    ${section}    IN    @{SECTIONS}
        Go To Section    ${section}
        ${bad}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('a[href], [src]')).filter(e => /^\\s*javascript:/i.test(e.getAttribute('href') || e.getAttribute('src') || '')).length
        Should Be Equal As Integers    ${bad}    0    msg=javascript: URL found in ${section}
    END

External links open with noopener so the target cannot control the app
    [Documentation]    TC15-005. Expected result: External links open with noopener so the target cannot control the app.
    ...    Every section is checked, so the result does not depend on the view an earlier test left open.
    FOR    ${section}    IN    @{SECTIONS}
        Go To Section    ${section}
        ${unsafe}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('a[target="_blank"]')).filter(a => !/noopener/.test(a.rel)).length
        Should Be Equal As Integers    ${unsafe}    0    msg=Link without noopener found in ${section}
    END

Job posting links with unsafe schemes are rejected by the API
    [Documentation]    TC15-006. Expected result: Job posting links with unsafe schemes are rejected by the API.
    FOR    ${link}    IN    javascript:alert(1)    data:text/html,<script>alert(1)</script>    file:///etc/passwd    vbscript:x
        ${payload}=    Application Payload    link=${link}
        ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
        Should Be True    ${response.status} in (201, 400)
        IF    ${response.status} == 201
            Should Not Match Regexp    ${response.json}[link]    (?i)^\\s*(javascript|data|file|vbscript):
        END
    END

Page has no console errors caused by hostile data
    [Documentation]    TC15-007. Expected result: Page has no console errors caused by hostile data.
    ${log}=    Get Console Log    full=${False}
    ${errors}=    Evaluate    [m for m in $log if m['type'] == 'error' and 'xss' in m['text'].lower()]
    Should Be Empty    ${errors}
