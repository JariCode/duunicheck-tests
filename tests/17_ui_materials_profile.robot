*** Settings ***
Documentation     Remaining materials and account UI: CV editing with list chips and photo, template editing,
...               deleting CVs and templates, file download and drop zone, AI chat context toggles and the
...               Clerk profile (manage account) dialog. Actions of Clerk's own forms that change the real
...               account (password, email, account deletion) are tested by hand.
Resource          ../resources/common.robot
Suite Setup       Prepare Materials Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    materials    profile


*** Variables ***
# Context options of the chosen application, without the posting draft section below them.
${CONTEXT_OPTIONS}    .permission-list:not(.posting-draft-section)


*** Keywords ***
Prepare Materials Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    Reload
    Wait For Workspace

Open Materials
    Go To Section    CV & pohjat

Edit Seed Cv
    [Arguments]    ${name}
    Open Materials
    Click    css=.material-card:has-text("${name}") >> button:has-text("Muokkaa")
    Wait For Elements State    text=Tallenna CV →    visible

Cv From Api
    [Arguments]    ${name}
    ${api}=    Api Request    GET    /api/cvs    user=A
    ${match}=    Evaluate    [c for c in $api.json if c['name'] == $name][0]
    RETURN    ${match}


*** Test Cases ***
CV can be edited and changes persist
    [Documentation]    TC17-001. Expected result: Editing a CV saves the new values to the account.
    ${name}=    Unique Name    EDITCV
    ${cv}=    Create Cv As    A    name=${name}    title=Vanha titteli
    Reload
    Wait For Workspace
    Edit Seed Cv    ${name}
    Fill Text    xpath=//label[contains(., "Koko nimi")]//input    Muokattu Nimi
    Fill Text    xpath=//label[contains(., "Profiiliteksti")]//textarea    Uusi profiiliteksti
    Click    text=Tallenna CV →
    Wait For Elements State    css=.overlay    detached
    ${saved}=    Cv From Api    ${name}
    Should Be Equal    ${saved}[fullName]    Muokattu Nimi
    Should Be Equal    ${saved}[summary]    Uusi profiiliteksti

CV list editor adds, edits and removes items
    [Documentation]    TC17-002. Expected result: IT skills chips can be added, edited and removed and are saved as lines.
    ${name}=    Unique Name    CHIPCV
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    Edit Seed Cv    ${name}
    Click    css=fieldset:has(legend:has-text("IT-taidot")) >> text=＋ Lisää kohta
    Fill Text    css=input[aria-label="Uusi it-taidot kohta"]    Python
    Press Keys    css=input[aria-label="Uusi it-taidot kohta"]    Enter
    Click    css=fieldset:has(legend:has-text("IT-taidot")) >> text=＋ Lisää kohta
    Fill Text    css=input[aria-label="Uusi it-taidot kohta"]    Robot Framework
    Click    css=button[aria-label="Lisää it-taidot kohta"]
    Get Element Count    css=fieldset:has(legend:has-text("IT-taidot")) .cv-list-chip    ==    2
    Fill Text    css=input[aria-label="IT-taidot, kohta 1"]    Python 3
    Click    css=button[aria-label="Poista it-taidot kohta 2"]
    Get Element Count    css=fieldset:has(legend:has-text("IT-taidot")) .cv-list-chip    ==    1
    Click    text=Tallenna CV →
    Wait For Elements State    css=.overlay    detached
    ${saved}=    Cv From Api    ${name}
    Should Be Equal    ${saved}[skills]    Python 3

CV list editor add can be cancelled with Escape and an empty item is not added
    [Documentation]    TC17-003. Expected result: Escape cancels adding and blank items are ignored.
    ${name}=    Unique Name    ESCCV
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    Edit Seed Cv    ${name}
    Click    css=fieldset:has(legend:has-text("Kurssit")) >> text=＋ Lisää kohta
    Get Property    css=button[aria-label="Lisää kurssit kohta"]    disabled    ==    ${True}
    Fill Text    css=input[aria-label="Uusi kurssit kohta"]    Hylätään
    Press Keys    css=input[aria-label="Uusi kurssit kohta"]    Escape
    Get Element Count    css=fieldset:has(legend:has-text("Kurssit")) .cv-list-chip    ==    0
    # The × button (aria-label "Peruuta lisäys") cancels the same way as Escape.
    Click    css=fieldset:has(legend:has-text("Kurssit")) >> text=＋ Lisää kohta
    Fill Text    css=input[aria-label="Uusi kurssit kohta"]    Peruutetaan
    Click    css=fieldset:has(legend:has-text("Kurssit")) >> button[aria-label="Peruuta lisäys"]
    Get Element Count    css=input[aria-label="Uusi kurssit kohta"]    ==    0
    Get Element Count    css=fieldset:has(legend:has-text("Kurssit")) .cv-list-chip    ==    0
    Click    css=.cancel

CV photo accepts a small PNG and can be removed
    [Documentation]    TC17-004. Expected result: A valid image is stored as a data URI; removing it clears the photo.
    ${name}=    Unique Name    PHOTOCV
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    ${png}=    Make Png    16    16
    ${path}=    Write Test File    ${TEST_FILES}/robot-photo.png    ${png}
    Edit Seed Cv    ${name}
    Upload File By Selector    css=input.cv-photo-input    ${path}
    Wait For Elements State    css=.cv-photo-preview img    visible
    Click    text=Tallenna CV →
    Wait For Elements State    css=.overlay    detached
    ${saved}=    Cv From Api    ${name}
    Should Start With    ${saved}[photo]    data:image/png;base64,
    Edit Seed Cv    ${name}
    Click    css=.cv-photo-preview >> text=Poista kuva
    Click    text=Tallenna CV →
    Wait For Elements State    css=.overlay    detached
    ${saved}=    Cv From Api    ${name}
    Should Be Empty    ${saved}[photo]

CV photo larger than 512 kB is refused with a message
    [Documentation]    TC17-005. Expected result: The UI shows a size error and does not attach the image.
    ${name}=    Unique Name    BIGPHOTO
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    ${big}=    Make Bytes    600000
    ${path}=    Write Test File    ${TEST_FILES}/robot-big.png    ${big}
    Edit Seed Cv    ${name}
    Upload File By Selector    css=input.cv-photo-input    ${path}
    Get Text    css=body    contains    512 kt
    Get Element Count    css=.cv-photo-preview    ==    0
    Click    css=.cancel

CV photo with a non-image type is refused
    [Documentation]    TC17-006. Expected result: A file that is not an image is not attached as a photo.
    ${name}=    Unique Name    BADPHOTO
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    ${path}=    Write Test File    ${TEST_FILES}/robot-fake.png    <script>alert(1)</script>
    Edit Seed Cv    ${name}
    Upload File By Selector    css=input.cv-photo-input    ${path}
    Sleep    1s
    Click    text=Tallenna CV →
    Sleep    1s
    ${saved}=    Cv From Api    ${name}
    ${photo}=    Set Variable    ${saved}[photo]
    Should Not Contain    ${photo}    <script>

CV form link fields reject non-http addresses on the server
    [Documentation]    TC17-007. Expected result: javascript: links in CV fields are never stored.
    ${payload}=    Cv Payload    linkedin=javascript:alert(1)
    ${response}=    Api Request    POST    /api/cvs    user=A    json_body=${payload}
    Status Should Be    ${response}    400

CV card shows safe links with noopener and can be printed
    [Documentation]    TC17-008. Expected result: Links on a CV card open in a new tab safely; print opens the print flow.
    ${name}=    Unique Name    LINKCV
    ${cv}=    Create Cv As    A    name=${name}    github=https://github.com/example
    Reload
    Wait For Workspace
    Open Materials
    Get Attribute    css=.material-card:has-text("${name}") .cv-social-links a    rel    contains    noopener
    Get Attribute    css=.material-card:has-text("${name}") .cv-social-links a    target    ==    _blank
    Evaluate JavaScript    ${None}    () => { window.__printed = 0; window.print = () => { window.__printed += 1 } }
    Click    css=.material-card:has-text("${name}") >> button:text-is("Tulosta / tallenna PDF")
    Sleep    1s
    ${printed}=    Evaluate JavaScript    ${None}    () => window.__printed
    Should Be True    ${printed} >= 1

CV can be deleted only after confirmation
    [Documentation]    TC17-009. Expected result: Cancel keeps the CV, confirming deletes it from the account.
    ${name}=    Unique Name    DELCV
    ${cv}=    Create Cv As    A    name=${name}
    Reload
    Wait For Workspace
    Open Materials
    Click    css=.material-card:has-text("${name}") >> button.delete-material
    Get Text    css=.confirm-dialog    contains    Poistetaanko CV?
    Click    css=.confirm-cancel
    ${still}=    Api Request    GET    /api/cvs    user=A
    Should Contain    ${still.text}    ${name}
    Click    css=.material-card:has-text("${name}") >> button.delete-material
    Click    css=.confirm-danger
    Wait For Elements State    css=.material-card:has-text("${name}")    detached
    ${gone}=    Api Request    GET    /api/cvs    user=A
    Should Not Contain    ${gone.text}    ${name}

CV form closes with Peruuta, the x button and the backdrop without saving
    [Documentation]    TC17-010. Expected result: Closing the CV form creates nothing.
    ${before}=    Api Request    GET    /api/cvs    user=A
    Open Materials
    Click    text=＋ Lisää CV >> nth=0
    Fill Text    xpath=//label[contains(., "CV:n nimi")]//input    ROBOT peruttu
    Click    css=.overlay >> button.cancel
    Wait For Elements State    css=.overlay    detached
    Click    text=＋ Lisää CV >> nth=0
    Click    css=.overlay .form-heading >> button[aria-label="Sulje"]
    Wait For Elements State    css=.overlay    detached
    Click    text=＋ Lisää CV >> nth=0
    Mouse Button    click    5    5
    Wait For Elements State    css=.overlay    detached
    ${after}=    Api Request    GET    /api/cvs    user=A
    Length Should Be    ${after.json}    ${{ len($before.json) }}

Template can be edited and changes persist
    [Documentation]    TC17-011. Expected result: Editing a template saves the new text and contact details.
    ${name}=    Unique Name    EDITTPL
    ${tpl}=    Create Template As    A    name=${name}
    Reload
    Wait For Workspace
    Open Materials
    Click    css=.template-card:has-text("${name}") >> button:text-is("Muokkaa pohjaa")
    Get Text    css=.template-editor h2    ==    Muokkaa pohjaa
    Fill Text    xpath=//label[contains(., "Hakukirjeen sisältö")]//textarea    Uusi sisältö
    Fill Text    xpath=//label[text()="Puhelin" or starts-with(normalize-space(.), "Puhelin")]//input    +358401234567
    Click    text=Tallenna pohja →
    Wait For Elements State    css=.template-editor    detached
    ${api}=    Api Request    GET    /api/templates    user=A
    ${saved}=    Evaluate    [t for t in $api.json if t['name'] == $name][0]
    Should Be Equal    ${saved}[body]    Uusi sisältö
    Should Be Equal    ${saved}[phone]    +358401234567

Template with an empty body is not saved
    [Documentation]    TC17-012. Expected result: The body is required by the form.
    ${before}=    Api Request    GET    /api/templates    user=A
    Open Materials
    Click    text=＋ Lisää pohja >> nth=0
    Fill Text    xpath=//label[contains(., "Pohjan nimi")]//input    ROBOT tyhjä
    Click    text=Tallenna pohja →
    Sleep    1s
    ${after}=    Api Request    GET    /api/templates    user=A
    Length Should Be    ${after.json}    ${{ len($before.json) }}
    Click    css=.template-editor >> button.cancel

Template can be deleted only after confirmation and printed
    [Documentation]    TC17-013. Expected result: Delete needs confirmation; print opens the print flow.
    ${name}=    Unique Name    DELTPL
    ${tpl}=    Create Template As    A    name=${name}
    Reload
    Wait For Workspace
    Open Materials
    Evaluate JavaScript    ${None}    () => { window.__printed = 0; window.print = () => { window.__printed += 1 } }
    Click    css=.template-card:has-text("${name}") >> button:text-is("Tulosta / tallenna PDF")
    Sleep    1s
    ${printed}=    Evaluate JavaScript    ${None}    () => window.__printed
    Should Be True    ${printed} >= 1
    Click    css=.template-card:has-text("${name}") >> button.delete-material
    Get Text    css=.confirm-dialog    contains    Poistetaanko hakemuspohja?
    Click    css=.confirm-cancel
    Click    css=.template-card:has-text("${name}") >> button.delete-material
    Click    css=.confirm-danger
    Wait For Elements State    css=.template-card:has-text("${name}")    detached

Uploaded file can be downloaded with the same content
    [Documentation]    TC17-014. Expected result: The Lataa button downloads the stored file unchanged.
    ${path}=    Write Test File    ${TEST_FILES}/robot-download.txt    Robot download content
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${path}
    Wait For Elements State    css=.uploaded-file-list li:has-text("robot-download.txt")    visible
    ${download}=    Promise To Wait For Download
    Click    css=.uploaded-file-list li:has-text("robot-download.txt") >> button:text-is("Lataa")
    ${file}=    Wait For    ${download}
    Should Be Equal    ${file}[suggestedFilename]    robot-download.txt
    ${content}=    Get File    ${file}[saveAs]
    Should Be Equal    ${content}    Robot download content

Application documents can be uploaded to the second library
    [Documentation]    TC17-015. Expected result: The application documents library accepts files separately from CV files.
    ${path}=    Write Test File    ${TEST_FILES}/robot-hakemus.txt    Hakemusteksti
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: Hakemustiedostot"]    ${path}
    Wait For Elements State    css=.uploaded-file-list li:has-text("robot-hakemus.txt")    visible
    ${api}=    Api Request    GET    /api/files    user=A
    ${file}=    Evaluate    [f for f in $api.json if f['name'] == 'robot-hakemus.txt'][0]
    Should Be Equal    ${file}[category]    application

Several files can be uploaded at once and an oversize file is refused
    [Documentation]    TC17-016. Expected result: Multiple files are all saved; a file over 10 MB is refused with a message.
    ${one}=    Write Test File    ${TEST_FILES}/robot-multi1.txt    yksi
    ${two}=    Write Test File    ${TEST_FILES}/robot-multi2.txt    kaksi
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${one}    ${two}
    Wait For Elements State    css=.uploaded-file-list li:has-text("robot-multi2.txt")    visible
    Get Element Count    css=.uploaded-file-list li:has-text("robot-multi1.txt")    ==    1
    ${huge}=    Make Bytes    10600000
    ${path}=    Write Test File    ${TEST_FILES}/robot-huge.txt    ${huge}
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${path}
    Sleep    3s
    ${api}=    Api Request    GET    /api/files    user=A
    Should Not Contain    ${api.text}    robot-huge.txt

File names with markup are shown as text
    [Documentation]    TC17-017. Expected result: A hostile file name is displayed as text and runs no script.
    ${path}=    Write Test File    ${TEST_FILES}/robot-img-onerror.txt    x
    Open Materials
    Upload File By Selector    css=input[aria-label="Lisää tiedostoja: CV-tiedostot"]    ${path}
    Wait For Elements State    css=.uploaded-file-list li:has-text("robot-img-onerror.txt")    visible
    Script Marker Should Be Unset

AI chat context options can be toggled for a chosen application
    [Documentation]    TC17-018. Expected result: Application picker and every context option can be switched on and off.
    # The posting draft section is also a .permission-list and its label contains "hakemuspohja",
    # so the context options are located without it.
    ${cv}=    Create Cv As    A    name=ROBOT Chat CV
    ${app}=    Create Application As    A    company=ROBOT Chat Oy    cvId=${cv}[id]    link=https://example.com/job
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Get Property    css=button.chat-send    disabled    ==    ${True}
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("ROBOT Chat Oy")
    Get Text    css=.application-picker-trigger    contains    ROBOT Chat Oy
    FOR    ${label}    IN    Työpaikkailmoitus    Valittu CV    Hakemuspohja    Tämän hakemuksen muistiinpanot
        Check Checkbox    css=${CONTEXT_OPTIONS} label:has-text("${label}") input
        Get Checkbox State    css=${CONTEXT_OPTIONS} label:has-text("${label}") input    ==    checked
        Uncheck Checkbox    css=${CONTEXT_OPTIONS} label:has-text("${label}") input
        Get Checkbox State    css=${CONTEXT_OPTIONS} label:has-text("${label}") input    ==    unchecked
    END
    Check Checkbox    css=${CONTEXT_OPTIONS} label:has-text("Työpaikkailmoitus") input
    Wait For Elements State    css=textarea.posting-context    visible
    Uncheck Checkbox    css=${CONTEXT_OPTIONS} label:has-text("Työpaikkailmoitus") input

AI chat application picker closes with Escape
    [Documentation]    TC17-019. Expected result: Escape closes the application list.
    Go To Section    AI-chat
    Click    css=.application-picker-trigger
    Wait For Elements State    css=.application-picker-options    visible
    Keyboard Key    press    Escape
    Wait For Elements State    css=.application-picker-options    detached

AI chat sends with Enter and keeps a new line with Shift+Enter, answering local questions
    [Documentation]    TC17-020. Expected result: Enter sends the message; the question about stored data is answered without OpenAI.
    Go To Section    AI-chat
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("ROBOT Chat Oy")
    Fill Text    css=.chat-composer textarea    Mikä on hakemuksen tila?
    # The app ignores Enter while the chat history of the chosen application is still loading;
    # the send button becomes enabled once the message can really be sent.
    Wait For Elements State    css=button.chat-send    enabled    timeout=15s
    Keyboard Key    press    Shift+Enter
    ${value}=    Get Property    css=.chat-composer textarea    value
    Should Be Equal    ${value}    Mikä on hakemuksen tila?\n    msg=Shift+Enter did not add a new line
    Sleep    1s
    Get Element Count    css=.user-message:has-text("Mikä on hakemuksen tila?")    ==    0
    Keyboard Key    press    Enter
    Wait For Elements State    css=.user-message:has-text("Mikä on hakemuksen tila?")    visible
    Wait For Elements State    css=.assistant-message >> nth=1    visible
    Get Element Count    css=.assistant-error    ==    0

AI chat history is stored per application and survives reload
    [Documentation]    TC17-021. Expected result: Messages are loaded again from the account after a reload.
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("ROBOT Chat Oy")
    Wait For Elements State    css=.user-message:has-text("Mikä on hakemuksen tila?")    visible

AI chat message limit is enforced by the field
    [Documentation]    TC17-022. Expected result: The message field accepts at most 4000 characters.
    Go To Section    AI-chat
    ${long}=    Evaluate    'm' * 4500
    Fill Text    css=.chat-composer textarea    ${long}
    ${value}=    Get Property    css=.chat-composer textarea    value
    Length Should Be    ${value}    4000

Manage account dialog opens from the user menu and shows the account sections
    [Documentation]    TC17-023. Expected result: Clerk's profile dialog opens with profile and security sections and closes again.
    Click    css=.cl-userButtonTrigger
    Click    css=.cl-userButtonPopoverActionButton:has-text("Hallitse tiliä")
    Wait For Elements State    css=.cl-modalContent    visible
    Get Text    css=.cl-modalContent    contains    Profiili
    # Clerk's Finnish localization names the security page "Turvallisuus".
    Get Text    css=.cl-modalContent    contains    Turvallisuus
    Get Text    css=.cl-modalContent    contains    ${USER_A_EMAIL}
    Click    css=.cl-modalContent >> text=Turvallisuus
    Get Text    css=.cl-modalContent    contains    Salasana
    Keyboard Key    press    Escape
    Wait For Elements State    css=.cl-modalContent    detached

Manage account dialog does not show the API tokens or secret data
    [Documentation]    TC17-024. Expected result: No token, session id or secret key text is visible in the profile dialog.
    Click    css=.cl-userButtonTrigger
    Click    css=.cl-userButtonPopoverActionButton:has-text("Hallitse tiliä")
    Wait For Elements State    css=.cl-modalContent    visible
    ${text}=    Get Text    css=.cl-modalContent
    Should Not Contain    ${text}    sk_test_
    Should Not Contain    ${text}    eyJ
    Keyboard Key    press    Escape

User menu opens the legal documents from the profile menu
    [Documentation]    TC17-025. Expected result: Terms and privacy policy open as dialogs from the user menu and close with Escape.
    FOR    ${item}    IN    Käyttöehdot    Tietosuojaseloste
        Click    css=.cl-userButtonTrigger
        # Custom menu items do not use the class of Clerk's built-in actions, so the button is
        # chosen by its text inside the popover card.
        Click    css=.cl-userButtonPopoverCard >> button:has-text("${item}")
        Wait For Elements State    css=#legal-modal-title    visible
        Keyboard Key    press    Escape
        Wait For Elements State    css=#legal-modal-title    detached
    END

File chooser button uploads the chosen file
    [Documentation]    TC17-026. Expected result: The "Valitse tiedostot" button opens the file chooser
    ...    and the chosen file is saved in that library.
    ${path}=    Write Test File    ${TEST_FILES}/robot-chooser.txt    Chooser content
    Open Materials
    ${upload}=    Promise To Upload File    ${path}
    Click    css=.file-library:has(input[aria-label="Lisää tiedostoja: Hakemustiedostot"]) >> button:text-is("Valitse tiedostot")
    Wait For    ${upload}
    Wait For Elements State    css=.uploaded-file-list li:has-text("robot-chooser.txt")    visible
    ${api}=    Api Request    GET    /api/files    user=A
    ${file}=    Evaluate    [f for f in $api.json if f['name'] == 'robot-chooser.txt'][0]
    Should Be Equal    ${file}[category]    application

AI chat application choice can be cleared
    [Documentation]    TC17-027. Expected result: Choosing "Valitse hakemus" in the picker clears the
    ...    chosen application, and a message cannot be sent without one.
    Go To Section    AI-chat
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("ROBOT Chat Oy")
    Get Text    css=.application-picker-trigger    contains    ROBOT Chat Oy
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("Valitse hakemus")
    Get Text    css=.application-picker-trigger    contains    Valitse hakemus
    Fill Text    css=.chat-composer textarea    Mikä on hakemuksen tila?
    Get Property    css=button.chat-send    disabled    ==    ${True}
