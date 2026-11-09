*** Settings ***
Documentation     Remaining UI functions: dashboard, progress timeline, calendar, search and stage filter,
...               application details (events: add, edit, delete), status side effects, CV and template
...               editing, file download, AI chat context toggles and the mobile menu.
Resource          ../resources/common.robot
Suite Setup       Prepare Pages Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    pages


*** Keywords ***
Prepare Pages Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    ${tomorrow}=    Get Current Date    increment=1 day    result_format=%Y-%m-%d
    Set Suite Variable    ${TOMORROW}    ${tomorrow}
    ${a}=    Create Application As    A    company=ROBOT Alfa Oy    role=Kehittäjä    status=Lähetetty    next=Soita rekrytoijalle    nextDate=${tomorrow}
    ${b}=    Create Application As    A    company=ROBOT Beta Oy    role=Testaaja    status=Haastattelu sovittu
    ${c}=    Create Application As    A    company=ROBOT Gamma Oy    role=Analyytikko    status=Hylätty
    Set Suite Variable    ${APP_A}    ${a}
    Reload
    Wait For Workspace

Open Details
    [Arguments]    ${company}
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("${company}") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-card    visible

Close Details
    Click    css=.detail-card >> button:text-is("Sulje")
    Wait For Elements State    css=.detail-card    detached

Print Count Should Become
    [Documentation]    The app calls window.print() shortly after the print sheet is rendered.
    [Arguments]    ${count}
    Wait Until Keyword Succeeds    5s    250ms    Print Count Should Be    ${count}

Print Count Should Be
    [Arguments]    ${count}
    ${printed}=    Evaluate JavaScript    ${None}    () => window.__printed
    Should Be Equal As Integers    ${printed}    ${count}

Finish Printing
    [Documentation]    Fires the browser's afterprint event, which removes the print sheet.
    Evaluate JavaScript    ${None}    () => window.dispatchEvent(new Event('afterprint'))
    Wait For Elements State    css=.print-document    detached

Delete Application Named
    [Documentation]    Deletes user A's applications with the given company (teardown helper).
    [Arguments]    ${company}
    ${api}=    Api Request    GET    /api/applications    user=A
    FOR    ${app}    IN    @{api.json}
        IF    $app['company'] == $company    Api Request    DELETE    /api/applications/${app}[id]    user=A
    END

Application From Api
    [Arguments]    ${company}
    ${api}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $api.json if a['company'] == $company][0]
    RETURN    ${match}


*** Test Cases ***
Dashboard shows correct counts and the recent applications list
    [Documentation]    TC16-001. Expected result: Dashboard metrics match the stored applications and "Koko lista"
    ...    opens the list. The five metrics are in the order Hakemuksia yhteensä, Lähetetty, Haastattelut,
    ...    Hyväksytyt, Hylätyt, and Hyväksytyt is 0 because no application is accepted.
    Go To Section    Yleiskatsaus
    Get Text    css=.metrics    contains    Hakemuksia yhteensä
    ${labels}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('.metrics .metric')).map(m => m.querySelector('div > span').textContent.trim())
    Should Be Equal    ${labels}    ${{ ['Hakemuksia yhteensä', 'Lähetetty', 'Haastattelut', 'Hyväksytyt', 'Hylätyt'] }}
    Get Text    css=.metric:has-text("Hakemuksia yhteensä") b    ==    3
    Get Text    css=.metric:has-text("Lähetetty") b    ==    1
    Get Text    css=.metric:has-text("Haastattelut") b    ==    1
    Get Text    css=.metric:has-text("Hyväksytyt") b    ==    0
    Get Text    css=.metric:has-text("Hylätyt") b    ==    1
    Get Element Count    css=.recent .job-row    ==    3
    Click    css=.see-all
    Wait For Elements State    css=.list-tools    visible

Dashboard shows the response time card and the monthly chart
    [Documentation]    TC16-002. Expected result: Response time card and 6-month chart render without errors.
    Go To Section    Yleiskatsaus
    Get Text    css=.next-paper    contains    Vastausaika
    Get Element Count    css=.live-chart-group    ==    6
    Get Element Count    css=.api-error    ==    0

Upcoming step in the dashboard opens the application details
    [Documentation]    TC16-003. Expected result: The "Seuraavaksi" button opens the details of that application.
    Go To Section    Yleiskatsaus
    Click    css=.upcoming-mini button >> nth=0
    Wait For Elements State    css=.detail-card:has-text("ROBOT Alfa Oy")    visible
    Close Details

Brand button returns to the overview
    [Documentation]    TC16-004. Expected result: Clicking the brand returns to the overview from any section.
    Go To Section    Kalenteri
    Click    css=button.brand
    Wait For Elements State    css=.metrics    visible

Search filters the list by company and role, case-insensitively
    [Documentation]    TC16-005. Expected result: The search box matches company and role text.
    Go To Section    Hakemukset
    Fill Text    css=.search-field input    alfa
    Get Element Count    css=.job-row    ==    1
    Fill Text    css=.search-field input    TESTAAJA
    Get Element Count    css=.job-row:has-text("ROBOT Beta Oy")    ==    1
    Fill Text    css=.search-field input    ei-löydy-mitään-xyz
    Get Element Count    css=.job-row    ==    0
    Fill Text    css=.search-field input    ${EMPTY}
    Get Element Count    css=.job-row    ==    3

Search text is treated as plain text and not as markup
    [Documentation]    TC16-006. Expected result: Markup typed in the search box does not run or break the page.
    Go To Section    Hakemukset
    Fill Text    css=.search-field input    <img src=x onerror=window.__searchxss=1>
    ${marker}=    Evaluate JavaScript    ${None}    () => window.__searchxss === undefined
    Should Be True    ${marker}
    Fill Text    css=.search-field input    ${EMPTY}

Stage filter shows only the chosen stage
    [Documentation]    TC16-007. Expected result: The stage filter shows only applications in that stage.
    Go To Section    Hakemukset
    Select Options By    css=select[aria-label="Suodata vaiheen mukaan"]    label    Hylätty
    Get Element Count    css=.job-row    ==    1
    Get Text    css=.job-row    contains    ROBOT Gamma Oy
    Select Options By    css=select[aria-label="Suodata vaiheen mukaan"]    label    Lähetetty
    Get Text    css=.job-row    contains    ROBOT Alfa Oy
    Select Options By    css=select[aria-label="Suodata vaiheen mukaan"]    label    Kaikki vaiheet
    Get Element Count    css=.job-row    ==    3

Search and stage filter work together
    [Documentation]    TC16-008. Expected result: Both filters must match at the same time.
    Go To Section    Hakemukset
    Fill Text    css=.search-field input    Beta
    Select Options By    css=select[aria-label="Suodata vaiheen mukaan"]    label    Hylätty
    Get Element Count    css=.job-row    ==    0
    Select Options By    css=select[aria-label="Suodata vaiheen mukaan"]    label    Kaikki vaiheet
    Fill Text    css=.search-field input    ${EMPTY}

Progress timeline lists every application with actions
    [Documentation]    TC16-009. Expected result: Timeline has one row per application and the row actions open details.
    Go To Section    Eteneminen
    Get Element Count    css=.timeline-row    ==    3
    Get Text    css=.timeline-summary    contains    3 hakemusta aikajanalla
    Click    css=.timeline-row:has-text("ROBOT Beta Oy") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-card:has-text("ROBOT Beta Oy")    visible
    Close Details

Progress timeline can edit, change status and delete
    [Documentation]    TC16-010. Expected result: Edit, status picker and delete work from the timeline too.
    Go To Section    Eteneminen
    Click    css=.timeline-row:has-text("ROBOT Beta Oy") >> button:text-is("Muokkaa")
    Wait For Elements State    text=Tallenna muutokset →    visible
    Click    css=.application-form-overlay >> button.cancel
    Select Options By    css=.timeline-row:has-text("ROBOT Beta Oy") select    label    Hylätty
    Sleep    1s
    ${beta}=    Application From Api    ROBOT Beta Oy
    Should Be Equal    ${beta}[status]    Hylätty
    Select Options By    css=.timeline-row:has-text("ROBOT Beta Oy") select    label    Haastattelu sovittu
    Sleep    1s
    Click    css=.timeline-row:has-text("ROBOT Beta Oy") >> button:text-is("Poista")
    Wait For Elements State    css=.confirm-dialog    visible
    Click    css=.confirm-cancel
    Wait For Elements State    css=.confirm-dialog    detached
    Get Element Count    css=.timeline-row    ==    3

Progress timeline add button opens the application form
    [Documentation]    TC16-011. Expected result: "Lisää hakemus" in the timeline opens an empty form.
    Go To Section    Eteneminen
    Click    css=.timeline-add
    Wait For Elements State    text=Tallenna hakemus →    visible
    Click    css=.application-form-overlay >> button.cancel

Calendar shows the reminder in the right day and the sidebar list
    [Documentation]    TC16-012. Expected result: The next step appears on its date and in the reminders list.
    Go To Section    Kalenteri
    Get Text    css=.upcoming    contains    Soita rekrytoijalle
    Get Text    css=.upcoming    contains    ROBOT Alfa Oy

Calendar month navigation works
    [Documentation]    TC16-013. Expected result: Previous, next and today buttons change the displayed month.
    Go To Section    Kalenteri
    ${now}=    Get Text    css=.calendar-paper h2
    Click    css=button[aria-label="Seuraava kuukausi"]
    ${next}=    Get Text    css=.calendar-paper h2
    Should Not Be Equal    ${now}    ${next}
    Click    css=button[aria-label="Edellinen kuukausi"]
    Click    css=button[aria-label="Edellinen kuukausi"]
    ${previous}=    Get Text    css=.calendar-paper h2
    Should Not Be Equal    ${now}    ${previous}
    Click    css=.calendar-controls >> text=Tänään
    Get Text    css=.calendar-paper h2    ==    ${now}
    Get Element Count    css=.calendar-grid .day    >=    28

Calendar event and reminder open the application details
    [Documentation]    TC16-014. Expected result: Clicking a reminder opens the details of that application.
    Go To Section    Kalenteri
    Click    css=.upcoming-button >> nth=0
    Wait For Elements State    css=.detail-card:has-text("ROBOT Alfa Oy")    visible
    Close Details

Application details show data, close with the buttons and the backdrop
    [Documentation]    TC16-015. Expected result: Details dialog shows the application and closes with Sulje, × and a backdrop click.
    Open Details    ROBOT Alfa Oy
    Get Text    css=.detail-card    contains    Kehittäjä
    Get Text    css=.detail-status    ==    Lähetetty
    Click    css=.detail-card >> button[aria-label="Sulje"]
    Wait For Elements State    css=.detail-card    detached
    Open Details    ROBOT Alfa Oy
    Mouse Move    5    5
    Mouse Button    click    5    5
    Wait For Elements State    css=.detail-card    detached

Event types can be added, edited and deleted, and the status follows
    [Documentation]    TC16-016. Expected result: Adding "Haastattelu sovittu" moves the status; editing and deleting events persists.
    Open Details    ROBOT Alfa Oy
    Select Options By    css=.event-form select    label    Haastattelu sovittu
    Fill Text    css=.event-form input[maxlength="300"]    Robot-muistio
    # The form's heading has the same text as its submit button, so the button is chosen by type.
    Click    css=.event-form button[type="submit"]
    Wait For Elements State    css=.history li:has-text("Robot-muistio")    visible
    ${alfa}=    Application From Api    ROBOT Alfa Oy
    Should Be Equal    ${alfa}[status]    Haastattelu sovittu
    Click    css=.history li:has-text("Robot-muistio") >> button:text-is("Muokkaa")
    Fill Text    css=.history li input[aria-label="Tapahtuman lisätieto"]    Muokattu muistio
    Click    css=.history li >> button:text-is("Tallenna") >> nth=0
    Wait For Elements State    css=.history li:has-text("Muokattu muistio")    visible
    Click    css=.history li:has-text("Muokattu muistio") >> button:text-is("Poista")
    Wait For Elements State    css=.event-delete-confirm    visible
    Click    css=.event-delete-confirm >> text=Peruuta
    Get Text    css=.history    contains    Muokattu muistio
    Click    css=.history li:has-text("Muokattu muistio") >> button:text-is("Poista")
    Click    css=.event-delete-confirm >> text=Poista merkintä
    Wait For Elements State    css=.history li:has-text("Muokattu muistio")    detached
    Close Details

Adding an event is impossible without choosing its type
    [Documentation]    TC16-017. Expected result: The add button stays disabled until an event type is chosen.
    Open Details    ROBOT Alfa Oy
    Get Property    css=.event-form button[type="submit"]    disabled    ==    ${True}
    Close Details

Event note longer than the field limit cannot be typed
    [Documentation]    TC16-018. Expected result: The note field limits input to 300 characters.
    Open Details    ROBOT Alfa Oy
    ${long}=    Evaluate    'x' * 400
    Fill Text    css=.event-form input[maxlength="300"]    ${long}
    ${value}=    Get Property    css=.event-form input[maxlength="300"]    value
    Length Should Be    ${value}    300
    Close Details

Print buttons in the details call the print dialog with the right content
    [Documentation]    TC16-019. Expected result: Print buttons open a print sheet; the real PDF output is checked by hand.
    Open Details    ROBOT Alfa Oy
    Evaluate JavaScript    ${None}    () => { window.__printed = 0; window.print = () => { window.__printed += 1 } }
    Click    css=.detail-print-actions >> text=Tulosta muistiinpanot / PDF
    Sleep    1s
    ${printed}=    Evaluate JavaScript    ${None}    () => window.__printed
    Should Be True    ${printed} >= 1
    Close Details

Details open the AI chat for the same application
    [Documentation]    TC16-020. Expected result: "Avaa AI-chat tällä hakemuksella" opens the chat with that application selected.
    Open Details    ROBOT Alfa Oy
    Click    css=.detail-print-actions >> text=Avaa AI-chat tällä hakemuksella
    Wait For Elements State    css=.assistant-page    visible
    Get Text    css=.application-picker-trigger    contains    ROBOT Alfa Oy

Details link opens only safe http(s) job postings in a new tab
    [Documentation]    TC16-021. Expected result: The posting link has target=_blank and rel=noopener noreferrer.
    ${created}=    Create Application As    A    company=ROBOT Linkki Oy    link=https://example.com/job
    Reload
    Wait For Workspace
    Open Details    ROBOT Linkki Oy
    Get Attribute    css=.detail-actions a    target    ==    _blank
    Get Attribute    css=.detail-actions a    rel    contains    noopener
    Close Details

Changing status to Lähetetty or Hylätty records an event with today's date
    [Documentation]    TC16-022. Expected result: Status change through the picker adds a matching history event.
    ${created}=    Create Application As    A    company=ROBOT Tapahtuma Oy
    Reload
    Wait For Workspace
    Go To Section    Hakemukset
    Select Options By    css=select[aria-label="Vaihda hakemuksen ROBOT Tapahtuma Oy vaihe"]    label    Lähetetty
    Sleep    1s
    ${app}=    Application From Api    ROBOT Tapahtuma Oy
    ${types}=    Evaluate    [e['type'] for e in $app['events']]
    Should Contain    ${types}    Lähetetty
    Select Options By    css=select[aria-label="Vaihda hakemuksen ROBOT Tapahtuma Oy vaihe"]    label    Hylätty
    Sleep    1s
    ${app}=    Application From Api    ROBOT Tapahtuma Oy
    Should Be Equal    ${app}[status]    Hylätty
    Should Not Be Empty    ${app}[respondedAt]

Application form lists own CVs and templates and saves the selection
    [Documentation]    TC16-023. Expected result: Form shows own CVs and can store a CV and a template on the application.
    ${cv}=    Create Cv As    A    name=ROBOT Lomake CV
    ${template}=    Create Template As    A    name=ROBOT Lomakepohja
    Reload
    Wait For Workspace
    Go To Section    Hakemukset
    Click    text=＋ Lisää hakemus >> nth=0
    Fill Text    xpath=//label[contains(., "Yritys")]//input    ROBOT Liitteet Oy
    Fill Text    xpath=//label[contains(., "Tehtävä")]//input    Liitetty
    Select Options By    xpath=//label[contains(., "CV liitteeksi")]//select    label    ROBOT Lomake CV
    Select Options By    xpath=//label[contains(., "Hakukirje liitteeksi")]//select    label    ROBOT Lomakepohja
    Click    text=Tallenna hakemus →
    Wait For Elements State    css=.job-row:has-text("ROBOT Liitteet Oy")    visible
    ${app}=    Application From Api    ROBOT Liitteet Oy
    Should Be Equal    ${app}[cvId]    ${cv}[id]
    Should Be Equal    ${app}[templateId]    ${template}[id]

Application form closes with Peruuta and the backdrop without saving
    [Documentation]    TC16-024. Expected result: Cancelling the form saves nothing.
    ${before}=    Api Request    GET    /api/applications    user=A
    Go To Section    Hakemukset
    Click    text=＋ Lisää hakemus >> nth=0
    Fill Text    xpath=//label[contains(., "Yritys")]//input    ROBOT Peruttu Oy
    Click    css=.application-form-overlay >> button.cancel
    Wait For Elements State    css=.application-form-overlay    detached
    Click    text=＋ Lisää hakemus >> nth=0
    Mouse Button    click    5    5
    Wait For Elements State    css=.application-form-overlay    detached
    ${after}=    Api Request    GET    /api/applications    user=A
    Length Should Be    ${after.json}    ${{ len($before.json) }}

Application form limits field lengths in the browser
    [Documentation]    TC16-025. Expected result: Company field cannot exceed its maxlength.
    Go To Section    Hakemukset
    Click    text=＋ Lisää hakemus >> nth=0
    ${long}=    Evaluate    'y' * 400
    Fill Text    xpath=//label[contains(., "Yritys")]//input    ${long}
    ${value}=    Get Property    xpath=//label[contains(., "Yritys")]//input    value
    Should Be True    len($value) <= 160
    Click    css=.application-form-overlay >> button.cancel

Mobile menu opens, navigates and closes
    [Documentation]    TC16-026. Expected result: The hamburger menu opens, a section can be chosen and the backdrop closes it.
    ...    Runs as an emulated phone (see Open Mobile Workspace).
    Open Mobile Workspace    390    800
    Wait For Elements State    ${NAV}    hidden    timeout=5s
    Click    css=button.mobile-nav-toggle
    Get Attribute    css=button.mobile-nav-toggle    aria-expanded    ==    true
    Click    ${NAV} >> text=Kalenteri
    Wait For Elements State    css=.calendar-paper    visible
    # Choosing a section closes the menu.
    Get Attribute    css=button.mobile-nav-toggle    aria-expanded    ==    false
    Wait For Elements State    ${NAV}    hidden    timeout=5s
    Click    css=button.mobile-nav-toggle
    Wait For Elements State    ${NAV}    visible    timeout=5s
    Mouse Button    click    385    700
    Get Attribute    css=button.mobile-nav-toggle    aria-expanded    ==    false
    Wait For Elements State    ${NAV}    hidden
    [Teardown]    Close Mobile Workspace

Browser back button follows the visited sections
    [Documentation]    TC16-027. Expected result: The URL keeps the section so back/forward and reload stay in place.
    Go To Section    Hakemukset
    Go To Section    Kalenteri
    Go Back
    Wait For Elements State    css=.list-tools    visible
    Reload
    Wait For Workspace
    Wait For Elements State    css=.list-tools    visible

Details print the attached CV, the cover letter and the whole application
    [Documentation]    TC16-028. Expected result: "Tulosta sovelluksen CV", "Tulosta hakukirje" and
    ...    "Tulosta hakemus / PDF" each open the print dialog with the matching print sheet. The
    ...    print dialog is replaced by a counter; the real PDF output is checked by hand.
    ${cv}=    Create Cv As    A    name=ROBOT Tulostus CV    fullName=Robot Tulostaja    title=Testiammattilainen
    ${template}=    Create Template As    A    name=ROBOT Tulostuspohja    body=Hei,\n\nRobot-kirjeen sisältö.
    Create Application As    A    company=ROBOT Tulostus Oy    role=Tulostaja    cvId=${cv}[id]    templateId=${template}[id]
    Reload
    Wait For Workspace
    Open Details    ROBOT Tulostus Oy
    Evaluate JavaScript    ${None}    () => { window.__printed = 0; window.print = () => { window.__printed += 1 } }
    Click    css=.detail-document:has-text("Tulosta sovelluksen CV: ROBOT Tulostus CV")
    Print Count Should Become    1
    Get Text    css=.print-document.print-cv    contains    Robot Tulostaja
    Get Text    css=.print-document.print-cv    contains    Testiammattilainen
    Finish Printing
    Click    css=.detail-document:has-text("Tulosta hakukirje: ROBOT Tulostuspohja")
    Print Count Should Become    2
    Get Text    css=.print-document.print-application    contains    Robot-kirjeen sisältö.
    Get Text    css=.print-document.print-application    contains    ROBOT Tulostus Oy
    Finish Printing
    Click    css=.detail-print-actions >> text=Tulosta hakemus / PDF
    Print Count Should Become    3
    Get Text    css=.print-document.print-application    contains    ROBOT Tulostus Oy
    Get Text    css=.print-document.print-application    contains    Tulostaja
    Finish Printing
    Close Details

Details download the attached CV file and cover letter file unchanged
    [Documentation]    TC16-029. Expected result: "Lataa CV-tiedosto" and "Lataa hakukirje" in the
    ...    details download the stored files with their names and content unchanged.
    ${cv_file}=    Upload Text File As    A    cv    ROBOT-details-cv.txt    Details CV content
    ${letter}=    Upload Text File As    A    application    ROBOT-details-letter.txt    Details letter content
    ${letter_ids}=    Create List    ${letter}[id]
    Create Application As    A    company=ROBOT Lataus Oy    cvFileId=${cv_file}[id]    applicationFileIds=${letter_ids}
    Reload
    Wait For Workspace
    Open Details    ROBOT Lataus Oy
    FOR    ${label}    ${name}    ${content}    IN
    ...    Lataa CV-tiedosto    ROBOT-details-cv.txt    Details CV content
    ...    Lataa hakukirje    ROBOT-details-letter.txt    Details letter content
        ${download}=    Promise To Wait For Download
        Click    css=.detail-document:has-text("${label}: ${name}")
        ${file}=    Wait For    ${download}
        Should Be Equal    ${file}[suggestedFilename]    ${name}
        ${saved}=    Get File    ${file}[saveAs]
        Should Be Equal    ${saved}    ${content}
    END
    Close Details

Calendar day entry and the company name in the list open the application details
    [Documentation]    TC16-030. Expected result: The reminder shown in the calendar grid and the
    ...    company name button of a list row both open the details of that application.
    Go To Section    Kalenteri
    ${entry}=    Set Variable    css=.calendar-grid .calendar-event[aria-label*="ROBOT Alfa Oy"]
    # The reminder is tomorrow, which is in the next month on the last day of a month.
    ${shown}=    Get Element Count    ${entry}
    IF    ${shown} == 0    Click    css=button[aria-label="Seuraava kuukausi"]
    Click    ${entry}
    Wait For Elements State    css=.detail-card:has-text("ROBOT Alfa Oy")    visible
    Close Details
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("ROBOT Gamma Oy") >> button.company-button
    Wait For Elements State    css=.detail-card:has-text("ROBOT Gamma Oy")    visible
    Close Details

Status Hyväksytty can be chosen in the form, the list, the stage filter and the timeline in the right order
    [Documentation]    TC16-031. Expected result: the status options of the application form, of the status
    ...    picker of a list row and of the timeline, the stage filter and the timeline legend all list the
    ...    stages in the order Kiinnostava, Lähetetty, Haastattelu sovittu, Hyväksytty, Hylätty. An application
    ...    saved with Hyväksytty in the form is stored with that status, the list picker shows it in the
    ...    accepted colour class, can change it away and back, and the stage filter Hyväksytty shows only it.
    ${stages}=    Create List    Kiinnostava    Lähetetty    Haastattelu sovittu    Hyväksytty    Hylätty
    ${company}=    Set Variable    ROBOT Hyväksytty Lomake Oy
    Go To Section    Hakemukset
    Click    text=＋ Lisää hakemus >> nth=0
    Wait For Elements State    text=Tallenna hakemus →    visible
    ${form_select}=    Set Variable    xpath=//label[contains(., "Hakemuksen vaihe")]//select
    ${options}=    Get Select Options    ${form_select}
    ${labels}=    Evaluate    [option['label'] for option in $options]
    Should Be Equal    ${labels}    ${stages}
    Fill Text    xpath=//label[contains(., "Yritys")]//input    ${company}
    Fill Text    xpath=//label[contains(., "Tehtävä")]//input    Hyväksyjä
    Select Options By    ${form_select}    label    Hyväksytty
    Click    text=Tallenna hakemus →
    Wait For Elements State    css=.job-row:has-text("${company}")    visible
    ${saved}=    Application From Api    ${company}
    Should Be Equal    ${saved}[status]    Hyväksytty
    ${picker}=    Set Variable    css=select[aria-label="Vaihda hakemuksen ${company} vaihe"]
    ${options}=    Get Select Options    ${picker}
    ${labels}=    Evaluate    [option['label'] for option in $options]
    Should Be Equal    ${labels}    ${stages}
    Get Attribute    ${picker}    class    contains    accepted
    Select Options By    ${picker}    label    Lähetetty
    Wait For Condition    Attribute    ${picker}    class    contains    sent
    Select Options By    ${picker}    label    Hyväksytty
    Wait For Condition    Attribute    ${picker}    class    contains    accepted
    Sleep    1s
    ${saved}=    Application From Api    ${company}
    Should Be Equal    ${saved}[status]    Hyväksytty
    ${filter}=    Set Variable    css=select[aria-label="Suodata vaiheen mukaan"]
    ${options}=    Get Select Options    ${filter}
    ${labels}=    Evaluate    [option['label'] for option in $options]
    Should Be Equal    ${labels}    ${{ ['Kaikki vaiheet'] + $stages }}
    Select Options By    ${filter}    label    Hyväksytty
    Get Element Count    css=.job-row    ==    1
    Get Text    css=.job-row    contains    ${company}
    Select Options By    ${filter}    label    Kaikki vaiheet
    Go To Section    Eteneminen
    ${legend}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('.timeline-legend span')).map(s => s.textContent.trim())
    Should Be Equal    ${legend}    ${stages}
    ${row_picker}=    Set Variable    css=.timeline-row:has-text("${company}") select
    ${options}=    Get Select Options    ${row_picker}
    ${labels}=    Evaluate    [option['label'] for option in $options]
    Should Be Equal    ${labels}    ${stages}
    Get Element Count    css=.timeline-row:has-text("${company}") .timeline-end.accepted    ==    1
    [Teardown]    Delete Application Named    ${company}

Overview counts accepted applications in every theme without horizontal scrolling on phones
    [Documentation]    TC16-032. An application with status Hyväksytty and a Hyväksytty event dated today is added.
    ...    Expected result: in the default, dark and light theme the metric "Hyväksytyt" shows the number of
    ...    accepted applications of the API, the chart legend lists Hakemuksia, Lähetetty, Haastattelut,
    ...    Hyväksytyt, Hylätyt, every month has an accepted bar and this month's title counts the accepted
    ...    application, the accepted status picker has its own colour different from the other stages, and at
    ...    320, 360, 390 and 768 px the overview, the list and the timeline do not scroll horizontally.
    ${today}=    Get Current Date    result_format=%Y-%m-%d
    &{event}=    Create Dictionary    id=1    type=Hyväksytty    date=${today}    note=${EMPTY}
    Create Application As    A    company=ROBOT Hyväksytty Teema Oy    status=Hyväksytty    added=${today}
    ...    respondedAt=${today}    events=${{ [$event] }}
    ${list}=    Api Request    GET    /api/applications    user=A
    ${accepted}=    Evaluate    str(len([a for a in $list.json if a['status'] == 'Hyväksytty' or any(e['type'] == 'Hyväksytty' for e in a['events'])]))
    FOR    ${theme}    IN    default    dark    light
        Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': $theme} }}
        Reload
        Wait For Workspace
        Get Attribute    css=html    data-duunicheck-theme    ==    ${theme}
        Go To Section    Yleiskatsaus
        Get Text    css=.metric:has-text("Hyväksytyt") b    ==    ${accepted}
        Wait For Elements State    css=.metric:has-text("Hyväksytyt")    visible
        ${legend}=    Evaluate JavaScript    ${None}    () => Array.from(document.querySelectorAll('.legend span')).map(s => s.textContent.trim())
        Should Be Equal    ${legend}    ${{ ['Hakemuksia', 'Lähetetty', 'Haastattelut', 'Hyväksytyt', 'Hylätyt'] }}
        Get Element Count    css=.live-chart-group .bar-accepted    ==    6
        Get Attribute    css=.live-chart-group >> nth=-1    title    contains    1 hyväksytty
        Go To Section    Hakemukset
        ${colours}=    Evaluate JavaScript    ${None}
        ...    () => { const look = (e) => getComputedStyle(e).backgroundColor + '|' + getComputedStyle(e).color; return { accepted: Array.from(document.querySelectorAll('.status-picker.accepted')).map(look), others: Array.from(document.querySelectorAll('.status-picker:not(.accepted)')).map(look) } }
        Should Not Be Empty    ${colours}[accepted]
        Should Not Be Empty    ${colours}[others]
        FOR    ${colour}    IN    @{colours}[accepted]
            Should Not Contain    ${colours}[others]    ${colour}    msg=Theme ${theme}: the accepted status has the same colours as another stage
        END
    END
    FOR    ${width}    IN    @{MOBILE_WIDTHS}
        Open Mobile Workspace    ${width}
        FOR    ${section}    IN    Yleiskatsaus    Hakemukset    Eteneminen
            Go To Section    ${section}
            Page Should Not Scroll Horizontally
        END
        Close Mobile Workspace
    END
    [Teardown]    Run Keywords    Close Mobile Workspace
    ...    AND    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'default'} }}
    ...    AND    Delete Application Named    ROBOT Hyväksytty Teema Oy
