*** Settings ***
Documentation     The context column of the AI chat (CV, Hakukirje and notes rows) and the way AI answers are
...               shown. The answer of POST /api/assistant/suggest is replaced with test data (Mock Json Response,
...               libraries/network_mocks.js), so no OpenAI call is made; the mock also records the request body,
...               which shows which context the browser asked the backend to send. All data is invented.
Resource          ../resources/common.robot
Suite Setup       Prepare Context Suite
Suite Teardown    Run Keywords    Run Keyword And Ignore Error    Delete All Data    A    AND    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    assistant


*** Variables ***
${OPTIONS}          css=.permission-list:not(.posting-draft-section)
${CV_ROW}           css=.permission-list:not(.posting-draft-section) > label:nth-of-type(2)
${LETTER_ROW}       css=.permission-list:not(.posting-draft-section) > label:nth-of-type(3)
${NOTES_ROW}        css=.permission-list:not(.posting-draft-section) > label:nth-of-type(4)
${ALLOW}            css=.permission-list:not(.posting-draft-section) label.approval-choice input
${COMPOSER}         css=.chat-composer textarea
${SEND}             css=.assistant-chat > button.chat-send
${FULL}             ROBOT Konteksti Tiedostot Oy
${APP_MATERIAL}     ROBOT Konteksti Sovellus Oy
${EMPTY_APP}        ROBOT Konteksti Tyhjä Oy


*** Keywords ***
Prepare Context Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    ${cv_file}=    Upload Text File As    A    cv    robot-cv-tiedosto.txt    Testaajan CV
    ${letter}=    Upload Text File As    A    application    robot-hakukirje.txt    Testaajan hakukirje
    ${letter2}=    Upload Text File As    A    application    robot-hakukirje-2.txt    Toinen hakukirje
    ${cv}=    Create Cv As    A    name=ROBOT Kontekstin CV
    ${template}=    Create Template As    A    name=ROBOT Kontekstin pohja
    Create Application As    A    company=${FULL}    cvFileId=${cv_file}[id]
    ...    applicationFileIds=${{ [$letter['id'], $letter2['id']] }}    notes=Kontekstin muistiinpano
    Create Application As    A    company=${APP_MATERIAL}    cvId=${cv}[id]    templateId=${template}[id]
    ...    applicationText=Hakemusteksti ilman yhteystietoja.    notes=Toinen muistiinpano
    Create Application As    A    company=${EMPTY_APP}
    Reload
    Wait For Workspace

Choose Application
    [Arguments]    ${company}
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("${company}")
    Get Text    css=.application-picker-trigger    contains    ${company}
    Wait For Elements State    ${OPTIONS}    visible

Row Should Be
    [Documentation]    Checks the text, the enabled state and the locked look of one context row.
    [Arguments]    ${row}    ${text}    ${enabled}
    Get Text    ${row}    contains    ${text}
    ${input}=    Set Variable    ${row} >> css=input[type="checkbox"]
    Get Property    ${input}    disabled    ==    ${{ not $enabled }}
    ${locked}=    Get Element Count    ${row}.is-context-locked
    Should Be Equal As Integers    ${locked}    ${{ 0 if $enabled else 1 }}

Mock Suggestion
    [Arguments]    ${suggestion}    @{notices}
    ${body}=    Evaluate    json.dumps({'suggestion': $suggestion, 'notices': list($notices)})    modules=json
    Mock Json Response    **/api/assistant/suggest    200    ${body}

Send Suggestion Request
    [Arguments]    ${message}=Paranna hakukirjettäni.
    Check Checkbox    ${ALLOW}
    Fill Text    ${COMPOSER}    ${message}
    Wait For Elements State    ${SEND}    enabled    timeout=15s
    Click    ${SEND}


*** Test Cases ***
Context rows are disabled when the application has no such material
    [Documentation]    TC21-001. Expected result: for an application without a CV, cover letter material or notes the
    ...    rows read "CV · ei CV:tä tällä hakemuksella", "Hakukirje · ei hakukirjettä tällä hakemuksella" and
    ...    "Muistiinpanot · ei muistiinpanoja tällä hakemuksella" and are disabled and look locked. For an application
    ...    with attached files the rows are enabled and name the files: "Valittu CV · CV-tiedosto:
    ...    robot-cv-tiedosto.txt", "Hakukirje · 2 tiedostoa" and "Tämän hakemuksen muistiinpanot". For an application
    ...    with an app CV, a template, an application text and notes they read "Valittu CV · ROBOT Kontekstin CV",
    ...    "Hakukirje · pohja ja hakemusteksti" and "Tämän hakemuksen muistiinpanot". The rows change when another
    ...    application is chosen, and a row chosen
    ...    for one application is not ticked on an application that has no such material.
    Go To Section    AI-chat
    Choose Application    ${EMPTY_APP}
    Row Should Be    ${CV_ROW}    CV · ei CV:tä tällä hakemuksella    ${False}
    Row Should Be    ${LETTER_ROW}    Hakukirje · ei hakukirjettä tällä hakemuksella    ${False}
    Row Should Be    ${NOTES_ROW}    Muistiinpanot · ei muistiinpanoja tällä hakemuksella    ${False}
    Choose Application    ${FULL}
    Row Should Be    ${CV_ROW}    Valittu CV · CV-tiedosto: robot-cv-tiedosto.txt    ${True}
    Row Should Be    ${LETTER_ROW}    Hakukirje · 2 tiedostoa    ${True}
    Get Text    ${LETTER_ROW}    contains    Yhteystiedot poistetaan ennen lähetystä.
    Row Should Be    ${NOTES_ROW}    Tämän hakemuksen muistiinpanot    ${True}
    Check Checkbox    ${CV_ROW} >> css=input
    Check Checkbox    ${LETTER_ROW} >> css=input
    Check Checkbox    ${NOTES_ROW} >> css=input
    Choose Application    ${APP_MATERIAL}
    Row Should Be    ${CV_ROW}    Valittu CV · ROBOT Kontekstin CV    ${True}
    Row Should Be    ${LETTER_ROW}    Hakukirje · pohja ja hakemusteksti    ${True}
    Row Should Be    ${NOTES_ROW}    Tämän hakemuksen muistiinpanot    ${True}
    Choose Application    ${EMPTY_APP}
    FOR    ${row}    IN    ${CV_ROW}    ${LETTER_ROW}    ${NOTES_ROW}
        Get Checkbox State    ${row} >> css=input    ==    unchecked
        Get Property    ${row} >> css=input    disabled    ==    ${True}
    END

CV and cover letter are not chosen by default
    [Documentation]    TC21-002. The privacy policy promises that choosing the CV and the cover letter is off by
    ...    default. Expected result: right after an application with a CV, cover letter files and notes is chosen,
    ...    and again after a reload, no context row is ticked (posting, CV, Hakukirje, notes, permission), and a
    ...    request sent with only the permission ticked asks for no CV, template, application text or notes.
    [Teardown]    Clear Mocked Responses
    FOR    ${round}    IN RANGE    2
        IF    ${round} == 1
            Reload
            Wait For Workspace
        END
        Go To Section    AI-chat
        Choose Application    ${FULL}
        ${states}=    Evaluate JavaScript    ${OPTIONS}    (list) => Array.from(list.querySelectorAll('input[type="checkbox"]')).map(e => e.checked)
        Should Be Equal    ${states}    ${{ [False] * 5 }}    msg=Context options ticked by default: ${states}
    END
    Mock Suggestion    Ehdotus.
    Send Suggestion Request
    Wait For Elements State    css=.assistant-message:has-text("Ehdotus.")    visible
    ${bodies}=    Get Mocked Request Bodies
    ${context}=    Evaluate    json.loads(json.loads($bodies)[-1])['context']    modules=json
    Should Be Equal    ${context}[includeCv]    ${False}
    Should Be Equal    ${context}[includeTemplate]    ${False}
    Should Be Equal    ${context}[includeApplicationText]    ${False}
    Should Be Equal    ${context}[includeApplication]    ${False}

Chosen CV and cover letter are sent as one request with every cover letter part
    [Documentation]    TC21-003. Expected result: when the CV and Hakukirje rows are ticked, the request asks for the
    ...    CV (includeCv) and for the whole cover letter material with one choice (includeTemplate and
    ...    includeApplicationText), but not for the notes, which were not ticked.
    [Teardown]    Clear Mocked Responses
    Go To Section    AI-chat
    Choose Application    ${FULL}
    Check Checkbox    ${CV_ROW} >> css=input
    Check Checkbox    ${LETTER_ROW} >> css=input
    Mock Suggestion    Ehdotus kirjeeseen.
    Send Suggestion Request
    Wait For Elements State    css=.assistant-message:has-text("Ehdotus kirjeeseen.")    visible
    ${bodies}=    Get Mocked Request Bodies
    ${context}=    Evaluate    json.loads(json.loads($bodies)[-1])['context']    modules=json
    Should Be Equal    ${context}[includeCv]    ${True}
    Should Be Equal    ${context}[includeTemplate]    ${True}
    Should Be Equal    ${context}[includeApplicationText]    ${True}
    Should Be Equal    ${context}[includeApplication]    ${False}

AI answer markdown is formatted safely and notices are shown with the answer
    [Documentation]    TC21-004. The suggest answer is mocked. Expected result: a heading (###), bold, italic and a
    ...    bullet list are shown formatted (h4, strong, em, two li items) and no raw "**" or "###" is visible; an
    ...    http(s) link becomes a link that opens in a new tab with rel noopener; a javascript: link, a <script> and
    ...    an <img onerror> are shown as plain text and never run; the user's own message stays plain text; the
    ...    Finnish notices of the answer are shown under it.
    [Teardown]    Clear Mocked Responses
    ${markdown}=    Catenate    SEPARATOR=\n
    # A cell that starts with # is a comment in Robot, so the heading marks are escaped.
    ...    \### Ehdotettu otsikko
    ...    ${EMPTY}
    ...    Tämä on **tärkeä** kohta ja *kursiivi* sana.
    ...    ${EMPTY}
    ...    - Ensimmäinen kohta
    ...    - Toinen kohta
    ...    ${EMPTY}
    # One __ per line, so the markers are not read as __bold__.
    ...    <script>window.__xss=1</script>
    ...    <img src=x onerror="window.__xss=2">
    ...    [Klikkaa tästä](javascript:window.__xss=3) ja [ohje](https://example.com/ohje)
    Mock Suggestion    ${markdown}    Tiedoston robot-hakukirje.txt teksti lyhennettiin: AI:lle lähetettiin ensimmäiset 8 000 merkkiä.
    Go To Section    AI-chat
    Choose Application    ${FULL}
    Send Suggestion Request    Paranna **tätä** tekstiä.
    ${answer}=    Set Variable    css=.assistant-message:has(.markdown-text) >> nth=-1
    Wait For Elements State    ${answer}    visible
    Get Text    ${answer} >> css=.markdown-text h4    ==    Ehdotettu otsikko
    Get Text    ${answer} >> css=.markdown-text strong    ==    tärkeä
    Get Text    ${answer} >> css=.markdown-text em    ==    kursiivi
    Get Element Count    ${answer} >> css=.markdown-text ul > li    ==    2
    Get Text    ${answer} >> css=.markdown-text ul > li >> nth=0    ==    Ensimmäinen kohta
    ${text}=    Get Text    ${answer} >> css=.markdown-text
    Should Not Contain    ${text}    **
    Should Not Contain    ${text}    \###
    Should Contain    ${text}    <script>window.__xss=1</script>
    Should Contain    ${text}    Klikkaa tästä (javascript:window.__xss=3)
    Get Element Count    css=.chat-messages script    ==    0
    Get Element Count    css=.chat-messages img    ==    0
    Get Element Count    css=.chat-messages a[href^="javascript"]    ==    0
    Get Attribute    ${answer} >> css=.markdown-text a    href    ==    https://example.com/ohje
    Get Attribute    ${answer} >> css=.markdown-text a    target    ==    _blank
    Get Attribute    ${answer} >> css=.markdown-text a    rel    contains    noopener
    Get Text    css=.user-message >> nth=-1 >> css=p    ==    Paranna **tätä** tekstiä.
    ${notice}=    Get Text    ${answer} >> css=.assistant-notice
    ${notice}=    Evaluate    $notice.replace(chr(0xa0), ' ')
    Should Be Equal    ${notice}    Tiedoston robot-hakukirje.txt teksti lyhennettiin: AI:lle lähetettiin ensimmäiset 8 000 merkkiä.
    Click    ${answer} >> text=Klikkaa tästä
    Script Marker Should Be Unset
