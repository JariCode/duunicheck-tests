*** Settings ***
Documentation     Application tracking in the UI as a logged-in user: add, edit, change status,
...               add events, delete, validation messages and persistence after reload.
Resource          ../resources/common.robot
Suite Setup       Prepare UI Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    applications


*** Keywords ***
Prepare UI Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A

Open Application Form
    Go To Section    Hakemukset
    Click    text=＋ Lisää hakemus >> nth=0
    Wait For Elements State    text=Tallenna hakemus →    visible

Add Application Through UI
    [Arguments]    ${company}    ${role}
    Open Application Form
    Fill Text    xpath=//label[contains(., "Yritys")]//input    ${company}
    Fill Text    xpath=//label[contains(., "Tehtävä")]//input    ${role}
    Click    text=Tallenna hakemus →
    Wait For Elements State    css=.job-row:has-text("${company}")    visible


*** Test Cases ***
Empty workspace shows the overview without errors
    [Documentation]    TC12-001. Expected result: Empty workspace shows the overview without errors.
    Wait For Workspace
    Get Element Count    css=.api-error    ==    0

A new application can be added and is shown in the list
    [Documentation]    TC12-002. Expected result: A new application can be added and is shown in the list.
    ${company}=    Unique Name    UI
    Add Application Through UI    ${company}    Testaaja
    Get Text    css=body    contains    ${company}
    ${api}=    Api Request    GET    /api/applications    user=A
    ${names}=    Evaluate    [a['company'] for a in $api.json]
    Should Contain    ${names}    ${company}

Application is still there after reloading the page
    [Documentation]    TC12-003. Expected result: Application is still there after reloading the page.
    ${company}=    Unique Name    UIRELOAD
    Add Application Through UI    ${company}    Kehittäjä
    Reload
    Wait For Workspace
    Go To Section    Hakemukset
    Get Text    css=body    contains    ${company}

Required fields are validated and nothing is saved when empty
    [Documentation]    TC12-004. Expected result: Required fields are validated and nothing is saved when empty.
    ${before}=    Api Request    GET    /api/applications    user=A
    Open Application Form
    Click    text=Tallenna hakemus →
    Sleep    1s
    # The browser's required-field check keeps the form open and shows the first empty field.
    Wait For Elements State    css=.application-form-overlay    visible
    ${missing}=    Evaluate JavaScript    xpath=//label[contains(., "Yritys")]//input    (input) => input.validity.valueMissing
    Should Be True    ${missing}    msg=Empty company field was not reported as missing
    ${after}=    Api Request    GET    /api/applications    user=A
    Length Should Be    ${after.json}    ${{ len($before.json) }}
    Click    css=.application-form-overlay >> button.cancel
    Wait For Elements State    css=.application-form-overlay    detached

Application can be edited
    [Documentation]    TC12-005. Expected result: Application can be edited.
    ${company}=    Unique Name    UIEDIT
    Add Application Through UI    ${company}    Vanha rooli
    Click    css=.job-row:has-text("${company}") >> button:text-is("Muokkaa")
    Fill Text    xpath=//label[contains(., "Tehtävä")]//input    Uusi rooli
    Click    text=Tallenna muutokset →
    Wait For Elements State    css=.job-row:has-text("Uusi rooli")    visible

Status can be changed from the status picker
    [Documentation]    TC12-006. Expected result: Status can be changed from the status picker.
    ${company}=    Unique Name    UISTATUS
    Add Application Through UI    ${company}    Status
    Select Options By    css=[aria-label="Vaihda hakemuksen ${company} vaihe"]    label    Lähetetty
    Sleep    1s
    ${api}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $api.json if a['company'] == $company][0]
    Should Be Equal    ${match}[status]    Lähetetty

Application can be deleted only after confirmation
    [Documentation]    TC12-007. Expected result: Application can be deleted only after confirmation.
    ${company}=    Unique Name    UIDELETE
    Add Application Through UI    ${company}    Poistettava
    Click    css=.job-row:has-text("${company}") >> button:text-is("Poista")
    Wait For Elements State    css=.confirm-dialog >> text=Poistetaanko hakemus?    visible
    Click    css=.confirm-cancel
    ${still}=    Api Request    GET    /api/applications    user=A
    Should Contain    ${still.text}    ${company}
    Click    css=.job-row:has-text("${company}") >> button:text-is("Poista")
    Click    css=.confirm-danger
    Wait For Elements State    css=.job-row:has-text("${company}")    detached
    ${gone}=    Api Request    GET    /api/applications    user=A
    Should Not Contain    ${gone.text}    ${company}

Event can be added to an application
    [Documentation]    TC12-008. Expected result: Event can be added to an application.
    ${company}=    Unique Name    UIEVENT
    Add Application Through UI    ${company}    Tapahtuma
    Click    css=.job-row:has-text("${company}") >> button:text-is("Tiedot")
    # The event form's heading and submit button share the text "Lisää tapahtuma".
    Wait For Elements State    css=.detail-card .event-form h3:text-is("Lisää tapahtuma")    visible
    Select Options By    css=.event-form select    label    Lähetetty
    Fill Text    css=.event-form input[maxlength="300"]    UI-tapahtuma
    Click    css=.event-form button[type="submit"]
    Wait For Elements State    css=.history li:has-text("UI-tapahtuma")    visible
    ${api}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $api.json if a['company'] == $company][0]
    ${notes}=    Evaluate    [e.get('note') for e in $match['events']]
    Should Contain    ${notes}    UI-tapahtuma

Progress and calendar views open without errors
    [Documentation]    TC12-009. Expected result: Progress and calendar views open without errors.
    FOR    ${section}    IN    Eteneminen    Kalenteri    Yleiskatsaus
        Go To Section    ${section}
        Get Element Count    css=.api-error    ==    0
    END

Application list handles a very long company name without breaking the layout
    [Documentation]    TC12-010. Expected result: Application list handles a very long company name without breaking the layout.
    ${long}=    Evaluate    'Pitkä' * 30
    ${payload}=    Application Payload    company=${long}
    ${response}=    Api Request    POST    /api/applications    user=A    json_body=${payload}
    Should Be True    ${response.status} in (201, 400)
    Reload
    Wait For Workspace
    Go To Section    Hakemukset
    Page Should Not Scroll Horizontally

Lists stay usable on small screens
    [Documentation]    TC12-011. Expected result: Lists stay usable on small screens.
    ...    Each width is opened as an emulated phone (see Open Mobile Workspace).
    FOR    ${width}    IN    320    390
        Open Mobile Workspace    ${width}
        Go To Section    Hakemukset
        Wait For Elements State    css=.list-tools    visible
        Page Should Not Scroll Horizontally
        Close Mobile Workspace
    END
    [Teardown]    Close Mobile Workspace
