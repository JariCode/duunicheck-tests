*** Settings ***
Documentation     CV and cover-letter template management, file upload and the AI chat in the UI,
...               including the posting draft option ("Tee hakemuspohja ilmoituksesta"). The draft
...               tests replace the parse-posting response with test data (Mock Json Response, see
...               libraries/network_mocks.js), so they run without OpenAI.
Resource          ../resources/common.robot
Suite Setup       Prepare UI Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    materials


*** Variables ***
${DRAFT_SECTION}    css=.posting-draft-section
${DRAFT_TOGGLE}     css=.posting-draft-section label:has-text("Tee hakemuspohja ilmoituksesta") input[type="checkbox"]
${COMPOSER}         css=.chat-composer textarea
# The send button of the composer; the draft form has its own button with the same class.
${SEND}             css=.assistant-chat > button.chat-send
${CHAT_ERROR}       css=.assistant-chat > p.assistant-error
${DRAFT}            css=.posting-draft-message
${DRAFT_SAVE}       css=.posting-draft-message button[type="submit"]


*** Keywords ***
Prepare UI Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A

Open Materials
    Go To Section    CV & pohjat

Mock Posting Draft
    [Documentation]    Answers the next parse-posting requests with a fixed draft, so the UI path runs
    ...    without OpenAI. ${existing} is the existingApplication object of the response, or None.
    [Arguments]    ${company}    ${role}    ${link}    ${existing}=${None}
    ${body}=    Evaluate    json.dumps({'draft': {'company': $company, 'role': $role, 'place': 'Tampere', 'link': $link, 'deadline': '2027-12-15'}, 'existingApplication': $existing})    modules=json
    Mock Json Response    **/api/assistant/parse-posting    200    ${body}

Turn Posting Draft Mode On
    Check Checkbox    ${DRAFT_TOGGLE}
    Get Checkbox State    ${DRAFT_TOGGLE}    ==    checked

Send Posting Text
    [Documentation]    Pastes a posting into the message field in posting draft mode and sends it.
    [Arguments]    ${text}
    Fill Text    ${COMPOSER}    ${text}
    Wait For Elements State    ${SEND}    enabled
    Click    ${SEND}

Draft Field
    [Documentation]    Locator of a field of the posting draft message by its label.
    [Arguments]    ${label}
    RETURN    css=.posting-draft-message label:has-text("${label}") >> css=input, textarea

Application Named
    [Documentation]    Returns the application of user A with the given company, failing if there is not exactly one.
    [Arguments]    ${company}
    ${list}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $list.json if a['company'] == $company]
    Length Should Be    ${match}    1
    RETURN    ${match}[0]


*** Test Cases ***
Materials view opens without errors
    [Documentation]    TC13-001. Expected result: Materials view opens without errors.
    Open Materials
    Get Element Count    css=.api-error    ==    0

A CV can be added through the form
    [Documentation]    TC13-002. Expected result: A CV can be added through the form.
    ${name}=    Unique Name    UICV
    Open Materials
    Click    text=＋ Lisää CV >> nth=0
    Fill Text    xpath=//label[contains(., "CV:n nimi")]//input    ${name}
    # "Koko nimi" is a required field of the CV form as well.
    Fill Text    xpath=//label[contains(., "Koko nimi")]//input    ${PREFIX} Tester
    Click    text=Tallenna CV →
    Wait For Elements State    text=${name}    visible
    ${api}=    Api Request    GET    /api/cvs    user=A
    Should Contain    ${api.text}    ${name}

A cover-letter template can be added through the form
    [Documentation]    TC13-003. Expected result: A cover-letter template can be added through the form.
    ${name}=    Unique Name    UITPL
    Open Materials
    Click    text=＋ Lisää pohja >> nth=0
    # "Pohjan nimi" and the letter body are the required fields of the template form.
    Fill Text    xpath=//label[contains(., "Pohjan nimi")]//input    ${name}
    Fill Text    xpath=//label[contains(., "Hakukirjeen sisältö")]//textarea    Hei, ${name}
    Click    text=Tallenna pohja →
    Wait For Elements State    css=.template-card:has-text("${name}")    visible
    ${api}=    Api Request    GET    /api/templates    user=A
    ${match}=    Evaluate    [t for t in $api.json if t['name'] == $name]
    Length Should Be    ${match}    1
    Should Be Equal    ${match}[0][body]    Hei, ${name}

A text file can be uploaded and appears in the CV file list
    [Documentation]    TC13-004. Expected result: A text file can be uploaded and appears in the CV file list.
    ${path}=    Write Test File    ${TEST_FILES}/robot-upload.txt    Robot test file
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${path}
    Sleep    2s
    ${api}=    Api Request    GET    /api/files    user=A
    Should Contain    ${api.text}    robot-upload.txt

A disallowed file type is refused by the UI or the server
    [Documentation]    TC13-005. Expected result: A disallowed file type is refused by the UI or the server.
    ${path}=    Write Test File    ${TEST_FILES}/robot-bad.exe    MZ not allowed
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${path}
    Sleep    2s
    ${api}=    Api Request    GET    /api/files    user=A
    Should Not Contain    ${api.text}    robot-bad.exe

Uploaded file can be deleted only after confirmation
    [Documentation]    TC13-006. Expected result: Uploaded file can be deleted only after confirmation.
    Open Materials
    Click    css=.file-library .delete-material >> nth=0
    Wait For Elements State    css=.confirm-dialog    visible
    Click    css=.confirm-cancel
    Wait For Elements State    css=.confirm-dialog    detached

AI chat answers local questions without calling the AI
    [Documentation]    TC13-007. Application must exist; local answers come from /conversations/:id/answer.
    ${app}=    Create Application As    A    notes=UI-CHAT-NOTE
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Get Element Count    css=.api-error    ==    0

AI chat input rejects script content by showing it as text only
    [Documentation]    TC13-008. Expected result: AI chat input rejects script content by showing it as text only.
    Go To Section    AI-chat
    Fill Text    xpath=//label[contains(., "Viesti työparille")]//textarea    <img src=x onerror="window.__xss=1">
    ${can_send}=    Run Keyword And Return Status    Wait For Elements State    css=.chat-send    enabled    timeout=2s
    IF    ${can_send}
        Click    css=.chat-send
        Sleep    2s
    END
    Script Marker Should Be Unset

Posting draft option has its own section even without a chosen application
    [Documentation]    TC13-009. Expected result: The context column shows the "Uusi hakemus ilmoituksesta"
    ...    subheading with the "Tee hakemuspohja ilmoituksesta" option and its help text, unticked, both
    ...    when no application is chosen and when one is.
    ${app}=    Create Application As    A    company=ROBOT Draft Section Oy
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Get Text    css=.application-picker-trigger    contains    Valitse hakemus
    Get Text    css=.assistant-permissions .permission-empty >> nth=0    contains    Valitse hakemus
    FOR    ${chosen}    IN    ${False}    ${True}
        IF    ${chosen}
            Click    css=.application-picker-trigger
            Click    css=[role="option"]:has-text("ROBOT Draft Section Oy")
            Get Text    css=.application-picker-trigger    contains    ROBOT Draft Section Oy
        END
        Get Text    ${DRAFT_SECTION} >> css=.application-picker-label    ==    Uusi hakemus ilmoituksesta
        Get Text    ${DRAFT_SECTION} >> css=label    ==    Tee hakemuspohja ilmoituksesta
        Get Text    ${DRAFT_SECTION} >> css=.permission-empty    ==    Liitä ilmoituksen teksti ja linkki viestikenttään. Pohja tallennetaan vasta, kun hyväksyt sen.
        Get Checkbox State    ${DRAFT_TOGGLE}    ==    unchecked
        Get Property    ${DRAFT_TOGGLE}    disabled    ==    ${False}
    END

Posting draft mode locks the application picker and the context options until it is turned off
    [Documentation]    TC13-010. Expected result: While "Tee hakemuspohja ilmoituksesta" is on, the
    ...    application picker, every context option and the pasted posting field are disabled, the message
    ...    field asks for the posting (16 000 characters) and can be sent without an application. Turning the
    ...    option off restores the picker, the options, their values and the normal message field (4000).
    ${app}=    Create Application As    A    company=ROBOT Draft Lock Oy
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("ROBOT Draft Lock Oy")
    ${options}=    Set Variable    css=.permission-list:not(.posting-draft-section) input[type="checkbox"]
    Check Checkbox    css=.permission-list:not(.posting-draft-section) label:has-text("Työpaikkailmoitus") input
    Wait For Elements State    css=textarea.posting-context    visible
    Get Element Count    ${options}    ==    5
    Get Attribute    ${COMPOSER}    maxlength    ==    4000
    Turn Posting Draft Mode On
    Get Property    css=.application-picker-trigger    disabled    ==    ${True}
    Get Element Count    css=.is-context-locked    ==    2
    ${states}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('.permission-list:not(.posting-draft-section) input, textarea.posting-context')).map(e => e.disabled)
    Should Be Equal    ${states}    ${{ [True] * 6 }}
    Get Attribute    ${COMPOSER}    placeholder    ==    Liitä työpaikkailmoituksen teksti ja linkki…
    Get Attribute    ${COMPOSER}    maxlength    ==    16000
    Get Property    ${SEND}    disabled    ==    ${True}
    Fill Text    ${COMPOSER}    Ilmoituksen teksti
    Get Property    ${SEND}    disabled    ==    ${False}
    Uncheck Checkbox    ${DRAFT_TOGGLE}
    Get Property    css=.application-picker-trigger    disabled    ==    ${False}
    Get Element Count    css=.is-context-locked    ==    0
    ${states}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('.permission-list:not(.posting-draft-section) input, textarea.posting-context')).map(e => e.disabled)
    Should Be Equal    ${states}    ${{ [False] * 6 }}
    Get Checkbox State    css=.permission-list:not(.posting-draft-section) label:has-text("Työpaikkailmoitus") input    ==    checked
    Get Attribute    ${COMPOSER}    placeholder    ==    Kirjoita viesti työparille…
    Get Attribute    ${COMPOSER}    maxlength    ==    4000
    Get Text    css=.application-picker-trigger    contains    ROBOT Draft Lock Oy

Posting draft without an OpenAI key shows a safe error and keeps the page working
    [Documentation]    TC13-011. Expected result: Sending a posting in posting draft mode while the backend has
    ...    no OpenAI key shows the app's message "AI-palvelua ei ole vielä määritetty.", no draft appears,
    ...    the pasted text stays in the field and the page keeps working. Runs only with
    ...    BACKEND_HAS_OPENAI_KEY=false against a backend started without OPENAI_API_KEY (tag no-openai-key).
    [Tags]    no-openai-key
    Require Backend Without OpenAI Key
    Go To Section    AI-chat
    Turn Posting Draft Mode On
    ${text}=    Set Variable    ROBOT Avoin Oy hakee testaajaa. <img src=x onerror="window.__xss=1"> https://example.com/robot-nokey
    Send Posting Text    ${text}
    Wait For Elements State    ${CHAT_ERROR}    visible
    Get Text    ${CHAT_ERROR}    ==    ${AI_NOT_CONFIGURED_ERROR}
    Get Element Count    ${DRAFT}    ==    0
    Get Element Count    css=.user-message    ==    0
    Get Property    ${COMPOSER}    value    ==    ${text}
    Get Text    ${SEND}    ==    Lähetä viesti
    Get Property    ${SEND}    disabled    ==    ${False}
    Wait For Elements State    ${WORKSPACE}    visible
    Script Marker Should Be Unset
    ${errors}=    Get Page Errors
    Should Be Empty    ${errors}    msg=Page errors: ${errors}

Posting draft can be checked, edited and saved as an application
    [Documentation]    TC13-012. The parse-posting response is replaced with test data (network mock), so the
    ...    whole path runs without OpenAI. Expected result: the request carries the pasted text and the
    ...    first link without trailing punctuation; the pasted text is shown as the user's message and the
    ...    draft message has the prefilled fields and the notes "Haku päättyy: 15.12.2027" (pp.kk.vvvv).
    ...    Company and role are required. After editing, "Tallenna hakemus" saves the
    ...    application in stage Kiinnostava with the edited values, the draft is locked and the confirmation
    ...    is shown. The new application is at once available in the application picker.
    [Teardown]    Clear Mocked Responses
    ${suffix}=    Generate Random String    8    [LOWERCASE][NUMBERS]
    ${company}=    Set Variable    ROBOT Mock ${suffix} Oy
    ${link}=    Set Variable    https://example.com/robot-mock-${suffix}
    Mock Posting Draft    ${company}    Testaaja    ${link}
    Go To Section    AI-chat
    Turn Posting Draft Mode On
    ${text}=    Set Variable    ${company} hakee testaajaa Tampereelle.\nHaku päättyy 15.12.2027.\nLue lisää: ${link}.
    Send Posting Text    ${text}
    Wait For Elements State    ${DRAFT}    visible
    ${bodies}=    Get Mocked Request Bodies
    ${sent}=    Evaluate    json.loads(json.loads($bodies)[-1])    modules=json
    Should Be Equal    ${sent}    ${{ {'postingText': $text, 'link': $link} }}
    Get Text    css=.user-message >> nth=-1    contains    ${company} hakee testaajaa Tampereelle.
    Get Text    ${DRAFT} >> css=b    ==    Työpari · hakemuspohja
    Get Text    ${DRAFT} >> css=p    ==    Tarkista ja korjaa tiedot ennen tallennusta. Tyhjät kentät eivät löytyneet ilmoituksen tekstistä.
    Get Text    ${DRAFT} >> css=small    ==    Hakemus tallennetaan vaiheeseen Kiinnostava.
    Get Property    ${COMPOSER}    value    ==    ${EMPTY}
    ${company_field}=    Draft Field    Yritys
    ${role_field}=    Draft Field    Tehtävä
    ${place_field}=    Draft Field    Paikkakunta
    ${link_field}=    Draft Field    Linkki
    ${notes_field}=    Draft Field    Muistiinpanot
    Get Property    ${company_field}    value    ==    ${company}
    Get Property    ${role_field}    value    ==    Testaaja
    Get Property    ${place_field}    value    ==    Tampere
    Get Property    ${link_field}    value    ==    ${link}
    Get Property    ${notes_field}    value    ==    Haku päättyy: 15.12.2027
    Get Element Count    css=.posting-duplicate    ==    0
    # Company and role are required: the save button is disabled while either is empty.
    Fill Text    ${role_field}    ${EMPTY}
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${True}
    Fill Text    ${role_field}    Muokattu testaaja
    Fill Text    ${place_field}    Espoo
    Fill Text    ${notes_field}    Haku päättyy: 15.12.2027\nOma huomio
    Get Text    ${DRAFT_SAVE}    ==    Tallenna hakemus
    Click    ${DRAFT_SAVE}
    Wait For Elements State    css=.assistant-message:has-text("Hakemus tallennettu: ${company} · Muokattu testaaja. Löydät sen Hakemukset-sivulta vaiheesta Kiinnostava.")    visible
    Get Text    ${DRAFT} >> css=p    ==    Tämä pohja on tallennettu hakemukseksi.
    Get Element Count    ${DRAFT_SAVE}    ==    0
    Get Property    ${DRAFT} >> css=fieldset    disabled    ==    ${True}
    ${saved}=    Application Named    ${company}
    ${today}=    Get Current Date    result_format=%Y-%m-%d
    Should Be Equal    ${saved}[status]    Kiinnostava
    Should Be Equal    ${saved}[role]    Muokattu testaaja
    Should Be Equal    ${saved}[place]    Espoo
    Should Be Equal    ${saved}[link]    ${link}
    Should Be Equal    ${saved}[added]    ${today}
    Should Be Equal    ${saved}[notes]    Haku päättyy: 15.12.2027\nOma huomio
    Uncheck Checkbox    ${DRAFT_TOGGLE}
    Click    css=.application-picker-trigger
    Wait For Elements State    css=[role="option"]:has-text("${company}")    visible

Posting draft warns about an application with the same link
    [Documentation]    TC13-013. The parse-posting response is replaced with test data (network mock).
    ...    Expected result: when the user already has an application with the draft's link, the warning
    ...    names it and saving is blocked until "Tallenna silti uutena hakemuksena" is ticked. Changing
    ...    the link removes the warning; changing it back brings the warning back unconfirmed. A confirmed
    ...    save creates a second application with the same link.
    [Teardown]    Clear Mocked Responses
    ${suffix}=    Generate Random String    8    [LOWERCASE][NUMBERS]
    ${link}=    Set Variable    https://jobs.example.com/robot-dup-${suffix}
    ${existing}=    Create Application As    A    company=ROBOT Dup ${suffix} Oy    role=Vanha tehtävä    link=${link}
    ${server_duplicate}=    Create Dictionary    id=${existing}[id]    company=${existing}[company]    role=${existing}[role]
    Mock Posting Draft    ROBOT Dup Uusi ${suffix} Oy    Uusi tehtävä    ${link}    ${server_duplicate}
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Turn Posting Draft Mode On
    Send Posting Text    ROBOT Dup Uusi ${suffix} Oy hakee. ${link}
    Wait For Elements State    css=.posting-duplicate    visible
    Get Text    css=.posting-duplicate span    ==    Sinulla on jo hakemus tällä linkillä: ROBOT Dup ${suffix} Oy · Vanha tehtävä.
    Get Attribute    css=.posting-duplicate    role    ==    alert
    ${confirm}=    Set Variable    css=.posting-duplicate label:has-text("Tallenna silti uutena hakemuksena") input
    Get Checkbox State    ${confirm}    ==    unchecked
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${True}
    Check Checkbox    ${confirm}
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${False}
    Uncheck Checkbox    ${confirm}
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${True}
    ${link_field}=    Draft Field    Linkki
    Fill Text    ${link_field}    https://example.com/robot-other-${suffix}
    Get Element Count    css=.posting-duplicate    ==    0
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${False}
    Fill Text    ${link_field}    ${link}
    Wait For Elements State    css=.posting-duplicate    visible
    Get Checkbox State    ${confirm}    ==    unchecked
    Get Property    ${DRAFT_SAVE}    disabled    ==    ${True}
    Check Checkbox    ${confirm}
    Click    ${DRAFT_SAVE}
    Wait For Elements State    css=.assistant-message:has-text("Hakemus tallennettu: ROBOT Dup Uusi ${suffix} Oy")    visible
    Get Element Count    css=.posting-duplicate    ==    0
    ${list}=    Api Request    GET    /api/applications    user=A
    ${same_link}=    Evaluate    sorted([a['company'] for a in $list.json if a['link'] == $link])
    Should Be Equal    ${same_link}    ${{ sorted([$existing['company'], 'ROBOT Dup Uusi ' + $suffix + ' Oy']) }}

Posting draft layout does not scroll horizontally on small screens
    [Documentation]    TC13-014. The parse-posting response is replaced with test data (network mock).
    ...    Expected result: at 320, 360, 390 and 768 px the AI chat with the posting draft option on, and
    ...    the draft message with a long company name and the duplicate warning, fit the screen width.
    ${suffix}=    Generate Random String    8    [LOWERCASE][NUMBERS]
    ${link}=    Set Variable    https://example.com/robot-mobile-${suffix}/a-very-long-path-segment-without-any-spaces-to-wrap
    ${existing}=    Create Application As    A    company=ROBOT Mobile ${suffix} Oy    link=${link}
    ${server_duplicate}=    Create Dictionary    id=${existing}[id]    company=${existing}[company]    role=${existing}[role]
    ${long_company}=    Set Variable    ROBOT-Pitkänimisenyrityksenkonsernipalvelutosakeyhtiö-${suffix}
    FOR    ${width}    IN    @{MOBILE_WIDTHS}
        Open Mobile Workspace    ${width}
        Mock Posting Draft    ${long_company}    Testiautomaatioinsinööri    ${link}    ${server_duplicate}
        Go To Section    AI-chat
        Turn Posting Draft Mode On
        Page Should Not Scroll Horizontally
        Send Posting Text    ${long_company} hakee. ${link}
        Wait For Elements State    css=.posting-duplicate    visible
        Page Should Not Scroll Horizontally
        Clear Mocked Responses
        Close Mobile Workspace
    END
    [Teardown]    Run Keywords    Run Keyword And Ignore Error    Clear Mocked Responses
    ...    AND    Close Mobile Workspace
