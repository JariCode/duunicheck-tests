*** Settings ***
Documentation     The tool options of the AI chat in the browser: importing applications from a file
...               ("Tee hakemukset tiedostosta"), undoing an import ("Kumoa tuonti") and deleting applications
...               through the assistant ("Etsi poistettavat hakemukset"), plus the chat state across tab
...               switches, reloads and sign-out, scrolling of long messages, the privacy note and the layout
...               on small screens.
...               The OpenAI part is replaced with test data (Mock Json Response, libraries/network_mocks.js):
...               the import answer is built with the real remap route (no OpenAI call), so it has exactly the
...               shape the server returns, and the delete search answer lists real application ids. Saving
...               (POST /api/applications) and deleting (POST /api/applications/bulk-delete) always reach the real
...               backend. Test files are generated from invented data into the gitignored tmp/import-files/.
Resource          ../resources/common.robot
Library           ../libraries/ImportTestFiles.py
Suite Setup       Prepare Import UI Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    assistant    import


*** Variables ***
${TOOLS}            css=.assistant-permissions .posting-draft-section
${POSTING_TOGGLE}   css=.posting-draft-section label:has-text("Tee hakemuspohja ilmoituksesta") input[type="checkbox"]
${IMPORT_TOGGLE}    css=.posting-draft-section label:has-text("Tee hakemukset tiedostosta") input[type="checkbox"]
${DELETE_TOGGLE}    css=.posting-draft-section label:has-text("Etsi poistettavat hakemukset") input[type="checkbox"]
${COMPOSER}         css=.chat-composer textarea
${SEND}             css=.assistant-chat > button.chat-send
${ATTACH}           css=.assistant-chat > button.chat-attach
${FILE_INPUT}       css=.assistant-chat > input[type="file"]
${CHAT_ERROR}       css=.assistant-chat > p.assistant-error
${CHAT}             css=.chat-messages
${IMPORT_MESSAGE}   css=.import-message:has(> b:text-is("Työpari · hakemukset tiedostosta"))
${DELETE_MESSAGE}   css=.import-message:has(> b:text-is("Työpari · poistettavat hakemukset"))
${IMPORT_SAVE}      css=.import-message:has(> b:text-is("Työpari · hakemukset tiedostosta")) > button.chat-send
${DELETE_BUTTON}    css=.import-message:has(> b:text-is("Työpari · poistettavat hakemukset")) > button.chat-send
${UNDO}             css=.import-undo-button
${CONFIRM}          css=.confirm-dialog
${PRIVACY_NOTE}     Kun kysyt hakemuksesi tiedoista, vastaus haetaan DuuniCheckistä, eikä tietoja lähetetä tekoälylle. Kun pyydät tekoälyltä ehdotuksia, sille lähtee vain viestisi ja ne tiedot, jotka olet itse valinnut. Kun teet hakemuksen ilmoituksesta tai tiedostosta, liittämäsi teksti lähetetään tekoälylle tietojen poimimiseksi, eikä mitään tallenneta ennen kuin hyväksyt sen. Poistopyynnöissä tekoälylle lähtee vain viestisi, ja poisto tehdään vasta vahvistuksesi jälkeen. Keskustelu tallentuu valitun hakemuksen yhteyteen.
${ROWS_NOTICE}      Tiedostossa on 60 hakemusriviä. Yhteen tuontiin otetaan enintään 50, joten mukana ovat ensimmäiset 50. Tuo loput erillisenä tiedostona.


*** Keywords ***
Prepare Import UI Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    ${content}=    Make Job Search Xlsx
    ${path}=    Write Import File    robot-ui-tuonti.xlsx    ${content}
    Set Suite Variable    ${IMPORT_FILE}    ${path}

Open Assistant
    Go To Section    AI-chat
    Wait For Elements State    ${TOOLS}    visible

Import Answer Body
    [Documentation]    Builds the import answer with the real remap route (no OpenAI call) from an invented table
    ...    of ${rows} rows named "${prefix} 001 Oy"… and returns it as JSON. Api Request switches to user A's
    ...    own browser session, so in a phone session build the body before Open Mobile Workspace.
    [Arguments]    ${rows}    ${prefix}=ROBOT UI    @{notices}
    ${table}=    Remap Table    ${rows}    ${prefix}
    ${remap}=    Api Request    POST    /api/assistant/import-applications/remap    user=A    json_body=${{ {'table': $table} }}
    Status Should Be    ${remap}    200
    ${body}=    Evaluate    json.dumps(dict($remap.json, kind='table', fileName='robot-ui-tuonti.xlsx', notices=list($remap.json['notices']) + list($notices)), ensure_ascii=False)    modules=json
    RETURN    ${body}

Mock Import Answer
    [Documentation]    Makes the answer of Import Answer Body the answer of the next import requests of the active page.
    [Arguments]    ${rows}    ${prefix}=ROBOT UI    @{notices}
    ${body}=    Import Answer Body    ${rows}    ${prefix}    @{notices}
    Mock Json Response    **/api/assistant/import-applications    200    ${body}

Import Mocked File
    [Documentation]    Turns the import option on, attaches the generated workbook and sends it; waits for the list.
    Check Checkbox    ${IMPORT_TOGGLE}
    Upload File By Selector    ${FILE_INPUT}    ${IMPORT_FILE}
    Wait For Elements State    css=.chat-attachment:has-text("robot-ui-tuonti.xlsx")    visible
    Click    ${SEND}
    Wait For Elements State    ${IMPORT_MESSAGE}    visible

Mock Delete Answer
    [Documentation]    Answer of the delete search with the given applications (dicts from the API).
    [Arguments]    ${applications}    ${needs_detail}=${False}    @{description}
    ${rows}=    Evaluate    [{'id': a['id'], 'company': a['company'], 'role': a['role'], 'status': a['status'], 'added': a.get('added', '')} for a in $applications]
    ${body}=    Evaluate    json.dumps({'criteria': {}, 'description': list($description), 'needsDetail': $needs_detail, 'applications': $rows}, ensure_ascii=False)    modules=json
    Mock Json Response    **/api/assistant/find-applications    200    ${body}

Search Deletable
    [Arguments]    ${text}
    Check Checkbox    ${DELETE_TOGGLE}
    Fill Text    ${COMPOSER}    ${text}
    Click    ${SEND}
    Wait For Elements State    ${DELETE_MESSAGE}    visible

Company Names Of A
    ${list}=    Api Request    GET    /api/applications    user=A
    ${names}=    Evaluate    sorted(a['company'] for a in $list.json)
    RETURN    ${names}

Before Unload Is Blocked
    [Documentation]    Dispatches a cancelable beforeunload event and returns whether the page cancelled it,
    ...    which is what makes the browser ask before leaving.
    ${blocked}=    Evaluate JavaScript    ${None}    () => { const e = new Event('beforeunload', { cancelable: true }); window.dispatchEvent(e); return e.defaultPrevented }
    RETURN    ${blocked}

Chat Scroll State
    ${state}=    Evaluate JavaScript    ${CHAT}    (c) => ({ top: c.scrollTop, height: c.scrollHeight, client: c.clientHeight, firstTop: c.firstElementChild.getBoundingClientRect().top, chatTop: c.getBoundingClientRect().top })
    RETURN    ${state}

Sign In Without Reload
    [Documentation]    Signs user A in from the landing page that is already open, without loading the page again
    ...    (Sign In of common.robot opens the landing page first, which would reload it).
    Click    text=Avaa DuuniCheck >> nth=0
    Wait For Elements State    input[name="identifier"]    visible    timeout=15s
    Fill Text    input[name="identifier"]    ${USER_A_EMAIL}
    Click    .cl-formButtonPrimary
    Fill Text    input[name="password"]    ${USER_A_PASSWORD}
    Click    .cl-formButtonPrimary
    ${submitted}=    Run Keyword And Return Status
    ...    Wait For Elements State    input[name="password"]    hidden    timeout=10s
    IF    not ${submitted}    Click    .cl-formButtonPrimary
    Enter Verification Code If Asked
    Wait For Workspace

Message Area Should Not Grow
    [Documentation]    The message area must stay within the app's own height limit however long the list is:
    ...    its height may not exceed its computed max-height (430 px on wide screens, 55vh at 740 px or less).
    ...    Where a layout sets no max-height, the area must end inside the viewport.
    ${size}=    Evaluate JavaScript    ${CHAT}
    ...    (c) => { const max = getComputedStyle(c).maxHeight; return { height: c.getBoundingClientRect().height, max: max === 'none' ? null : parseFloat(max), bottom: c.getBoundingClientRect().bottom + window.scrollY, viewport: window.innerHeight, scrollHeight: c.scrollHeight } }
    Should Be True    ${size}[scrollHeight] > ${size}[height]    msg=The list does not overflow the message area, so its growth cannot be checked
    IF    $size['max'] is not None
        Should Be True    ${size}[height] <= ${size}[max] + 1    msg=The message area grew to ${size}[height] px, its limit is ${size}[max] px
    ELSE
        Should Be True    ${size}[height] <= ${size}[viewport]    msg=The message area (${size}[height] px) is taller than the viewport (${size}[viewport] px)
    END

Finish Mocked Test
    Run Keyword And Ignore Error    Clear Mocked Responses
    Run Keyword And Ignore Error    Stop Recording Requests


*** Test Cases ***
Tool options are listed under their own subheadings in the context column
    [Documentation]    TC19-001. Expected result: the context column has the subheadings "Uusi hakemus ilmoituksesta",
    ...    "Tuo hakemuksia tiedostosta" and "Poista hakemuksia" in this order, each with its option ("Tee
    ...    hakemuspohja ilmoituksesta", "Tee hakemukset tiedostosta", "Etsi poistettavat hakemukset") and help
    ...    text; all are off and enabled, and the paperclip is not shown.
    Open Assistant
    ${headings}=    Evaluate JavaScript    ${TOOLS}    (s) => Array.from(s.querySelectorAll('.application-picker-label')).map(e => e.textContent.trim())
    Should Be Equal    ${headings}    ${{ ['Uusi hakemus ilmoituksesta', 'Tuo hakemuksia tiedostosta', 'Poista hakemuksia'] }}
    ${labels}=    Evaluate JavaScript    ${TOOLS}    (s) => Array.from(s.querySelectorAll('label')).map(e => e.textContent.trim())
    Should Be Equal    ${labels}    ${{ ['Tee hakemuspohja ilmoituksesta', 'Tee hakemukset tiedostosta', 'Etsi poistettavat hakemukset'] }}
    ${help}=    Evaluate JavaScript    ${TOOLS}    (s) => Array.from(s.querySelectorAll('.permission-empty')).map(e => e.textContent.trim())
    Should Be Equal    ${help}    ${{ ['Liitä ilmoituksen teksti ja linkki viestikenttään. Pohja tallennetaan vasta, kun hyväksyt sen.', 'Liitä Excel-, CSV-, Word-, PDF- tai tekstitiedosto viestikenttään.', 'Kerro, mitkä hakemukset haluat poistaa. Mitään ei poisteta ilman vahvistustasi.'] }}
    FOR    ${toggle}    IN    ${POSTING_TOGGLE}    ${IMPORT_TOGGLE}    ${DELETE_TOGGLE}
        Get Checkbox State    ${toggle}    ==    unchecked
        Get Property    ${toggle}    disabled    ==    ${False}
    END
    Get Element Count    ${ATTACH}    ==    0
    Get Element Count    ${FILE_INPUT}    ==    0

Each tool option locks the others and only the import option shows the paperclip
    [Documentation]    TC19-002. Expected result: while one tool option is on, the other two and the application
    ...    picker are disabled and marked locked; the paperclip and the file input exist only in import mode,
    ...    where the message field is read-only and asks for a file; delete mode asks for a description of at
    ...    most 2000 characters. Turning the option off enables everything again and hides the paperclip.
    Create Application As    A    company=ROBOT Lukitus Oy
    Reload
    Wait For Workspace
    Open Assistant
    FOR    ${on}    ${first}    ${second}    IN
    ...    ${POSTING_TOGGLE}    ${IMPORT_TOGGLE}    ${DELETE_TOGGLE}
    ...    ${IMPORT_TOGGLE}    ${POSTING_TOGGLE}    ${DELETE_TOGGLE}
    ...    ${DELETE_TOGGLE}    ${POSTING_TOGGLE}    ${IMPORT_TOGGLE}
        Check Checkbox    ${on}
        Get Property    ${first}    disabled    ==    ${True}
        Get Property    ${second}    disabled    ==    ${True}
        Get Property    css=.application-picker-trigger    disabled    ==    ${True}
        Get Element Count    css=.application-picker.is-context-locked    ==    1
        ${is_import}=    Evaluate    $on == $IMPORT_TOGGLE
        IF    ${is_import}
            Wait For Elements State    ${ATTACH}    visible
            Get Attribute    ${ATTACH}    aria-label    ==    Liitä tiedosto
            Get Element Count    ${FILE_INPUT}    ==    1
            Get Attribute    ${FILE_INPUT}    accept    ==    .xlsx,.csv,.docx,.pdf,.txt
            Get Property    ${COMPOSER}    readOnly    ==    ${True}
            Get Attribute    ${COMPOSER}    placeholder    ==    Liitä tiedosto paperiliittimellä tai vedä se tähän.
            Get Property    ${SEND}    disabled    ==    ${True}
        ELSE
            Get Element Count    ${ATTACH}    ==    0
            Get Element Count    ${FILE_INPUT}    ==    0
        END
        IF    $on == $DELETE_TOGGLE
            Get Attribute    ${COMPOSER}    placeholder    ==    Esim. poista eilen lisätyt hylätyt hakemukset…
            Get Attribute    ${COMPOSER}    maxlength    ==    2000
        END
        Uncheck Checkbox    ${on}
        Get Property    ${first}    disabled    ==    ${False}
        Get Property    ${second}    disabled    ==    ${False}
        Get Property    css=.application-picker-trigger    disabled    ==    ${False}
        Get Element Count    css=.is-context-locked    ==    0
        Get Element Count    ${ATTACH}    ==    0
    END

The privacy note of the context column is the new plain-language version
    [Documentation]    TC19-003. Expected result: the privacy note under the context options is exactly the new
    ...    plain-language text that covers database questions, AI suggestions, posting and file drafts and delete
    ...    requests.
    Open Assistant
    Get Text    css=.assistant-permissions .privacy-note    ==    ${PRIVACY_NOTE}

A file that is not supported is refused in the browser before sending
    [Documentation]    TC19-004. Expected result: attaching an .exe in import mode shows "Sallittuja tiedostomuotoja
    ...    ovat Excel (.xlsx), CSV, Word (.docx), PDF ja TXT.", no attachment is shown, the send button stays
    ...    disabled and no import request is sent.
    [Teardown]    Finish Mocked Test
    ${exe}=    Make Exe
    ${path}=    Write Import File    robot-ui.exe    ${exe}
    Open Assistant
    Start Recording Requests    /api/assistant/import-applications
    Check Checkbox    ${IMPORT_TOGGLE}
    Upload File By Selector    ${FILE_INPUT}    ${path}
    Wait For Elements State    ${CHAT_ERROR}    visible
    Get Text    ${CHAT_ERROR}    ==    Sallittuja tiedostomuotoja ovat Excel (.xlsx), CSV, Word (.docx), PDF ja TXT.
    Get Element Count    css=.chat-attachment    ==    0
    Get Property    ${SEND}    disabled    ==    ${True}
    ${requests}=    Get Recorded Requests
    Should Be Equal    ${{ json.loads($requests) }}    ${{ [] }}

Imported list is checked before saving and only the selected rows are saved
    [Documentation]    TC19-005. The import answer is mocked (built with the remap route). User A already has
    ...    "ROBOT UI 003 Oy · Testaaja". Expected result: the attachment chip shows the file name; after sending,
    ...    the chat shows the file as the user's message and the list of three applications; the third row is
    ...    marked "Duplikaatti", names the existing application and is not selected; nothing is saved before
    ...    "Tallenna valitut (2)"; saving creates exactly the two selected applications, marks them "Tallennettu"
    ...    and reports "Tallennettiin 2 hakemusta. Löydät ne Hakemukset-sivulta."
    [Teardown]    Finish Mocked Test
    Create Application As    A    company=ROBOT UI 003 Oy    role=Testaaja
    Reload
    Wait For Workspace
    Mock Import Answer    3
    Open Assistant
    ${before}=    Company Names Of A
    Import Mocked File
    Get Text    css=.user-message >> nth=-1    contains    Liitetty tiedosto: robot-ui-tuonti.xlsx
    Get Text    ${IMPORT_MESSAGE} >> css=p >> nth=0    ==    Löysin tiedostosta robot-ui-tuonti.xlsx 3 hakemusta. Tarkista valinnat ennen tallennusta: mitään ei tallenneta ennen kuin painat Tallenna valitut.
    Get Element Count    ${IMPORT_MESSAGE} >> css=.import-row    ==    3
    Get Checkbox State    ${IMPORT_MESSAGE} >> css=.import-row >> nth=0 >> css=input[type="checkbox"]    ==    checked
    Get Checkbox State    ${IMPORT_MESSAGE} >> css=.import-row >> nth=1 >> css=input[type="checkbox"]    ==    checked
    Get Checkbox State    ${IMPORT_MESSAGE} >> css=.import-row >> nth=2 >> css=input[type="checkbox"]    ==    unchecked
    Get Text    ${IMPORT_MESSAGE} >> css=.import-row >> nth=2 >> css=.import-flag.duplicate    ==    Duplikaatti
    Get Text    ${IMPORT_MESSAGE} >> css=.import-row >> nth=2 >> css=.import-flags small    ==    Sinulla on jo: ROBOT UI 003 Oy · Testaaja
    Get Property    ${COMPOSER}    value    ==    ${EMPTY}
    ${unsaved}=    Company Names Of A
    Should Be Equal    ${unsaved}    ${before}    msg=Applications were saved before "Tallenna valitut"
    Get Text    ${IMPORT_SAVE}    ==    Tallenna valitut (2)
    Click    ${IMPORT_SAVE}
    Wait For Elements State    css=.assistant-message:has-text("Tallennettiin 2 hakemusta. Löydät ne Hakemukset-sivulta.")    visible
    ${after}=    Company Names Of A
    Should Be Equal    ${after}    ${{ sorted($before + ['ROBOT UI 001 Oy', 'ROBOT UI 002 Oy']) }}
    Get Element Count    ${IMPORT_MESSAGE} >> css=.import-flag.saved    ==    2
    Get Text    ${IMPORT_SAVE}    ==    Tallenna valitut (0)
    Get Property    ${IMPORT_SAVE}    disabled    ==    ${True}
    Wait For Elements State    ${UNDO}    visible

Undo import deletes only the imported applications after confirmation
    [Documentation]    TC19-006. The import answer is mocked; saving and deleting use the real backend. User A also
    ...    has "ROBOT UI Muu Oy", which is not in the file. Expected result: after saving two imported rows,
    ...    "Kumoa tuonti" opens the dialog "Poistetaanko 2 tuotua hakemusta?" with "Tätä ei voi perua."; Peruuta
    ...    closes it and deletes nothing; confirming deletes exactly the two imported applications in one
    ...    bulk-delete request, reports "Tuonti kumottu: poistettiin 2 tuotua hakemusta.", marks the rows
    ...    "Tuonti kumottu" and removes the undo button; the other applications stay.
    [Teardown]    Finish Mocked Test
    Create Application As    A    company=ROBOT UI Muu Oy    role=Muu tehtävä
    Reload
    Wait For Workspace
    Mock Import Answer    2    ROBOT UI Kumoa
    Open Assistant
    Import Mocked File
    Click    ${IMPORT_SAVE}
    Wait For Elements State    css=.assistant-message:has-text("Tallennettiin 2 hakemusta.")    visible
    ${saved}=    Company Names Of A
    Should Contain    ${saved}    ROBOT UI Kumoa 001 Oy
    Should Contain    ${saved}    ROBOT UI Kumoa 002 Oy
    Get Text    css=.import-undo small    ==    Kumoaminen on mahdollista, kunnes sivu ladataan uudelleen.
    Click    ${UNDO}
    Wait For Elements State    ${CONFIRM}    visible
    Get Text    css=#confirm-dialog-title    ==    Poistetaanko 2 tuotua hakemusta?
    Get Text    css=#confirm-dialog-description    ==    Tätä ei voi perua.
    Click    css=.confirm-cancel
    Wait For Elements State    ${CONFIRM}    detached
    ${kept}=    Company Names Of A
    Should Be Equal    ${kept}    ${saved}    msg=Peruuta deleted applications
    Start Recording Requests    /api/applications/bulk-delete
    Click    ${UNDO}
    Wait For Elements State    ${CONFIRM}    visible
    Click    css=.confirm-danger
    Wait For Elements State    css=.assistant-message:has-text("Tuonti kumottu: poistettiin 2 tuotua hakemusta.")    visible
    ${after}=    Company Names Of A
    Should Be Equal    ${after}    ${{ sorted(n for n in $saved if not n.startswith('ROBOT UI Kumoa')) }}
    Should Contain    ${after}    ROBOT UI Muu Oy
    ${requests}=    Get Recorded Requests
    ${requests}=    Evaluate    json.loads($requests)    modules=json
    Length Should Be    ${requests}    1
    Get Element Count    ${IMPORT_MESSAGE} >> css=.import-flag.incomplete:text-is("Tuonti kumottu")    ==    2
    Get Element Count    ${UNDO}    ==    0

Long import list can be scrolled to the top and a new message scrolls to the bottom
    [Documentation]    TC19-007. The import answer is mocked with 50 rows and the 50 row notice. Expected result:
    ...    the notice is shown; the message area stays at most 430 px high and as wide as before; after the list
    ...    arrives it is scrolled to the bottom; scrolled to the top, the first message (the assistant's welcome)
    ...    is fully reachable; after saving one row the new summary message scrolls the area to the bottom.
    [Teardown]    Finish Mocked Test
    Mock Import Answer    50    ROBOT UI Pitkä    ${ROWS_NOTICE}
    Open Assistant
    ${width_before}=    Get BoundingBox    css=.assistant-chat    width
    Import Mocked File
    Get Text    ${IMPORT_MESSAGE} >> css=.import-notice    ==    ${ROWS_NOTICE}
    Get Element Count    ${IMPORT_MESSAGE} >> css=.import-row    ==    50
    ${state}=    Chat Scroll State
    Should Be True    ${state}[client] <= 430    msg=The message area grew to ${state}[client] px
    Should Be True    ${state}[height] > ${state}[client]    msg=The list does not overflow, the scroll test is meaningless
    Should Be True    ${state}[top] + ${state}[client] >= ${state}[height] - 2    msg=The new list was not scrolled into view
    ${width_after}=    Get BoundingBox    css=.assistant-chat    width
    Should Be True    abs(${width_after} - ${width_before}) <= 1    msg=The chat column changed width from ${width_before} to ${width_after}
    Evaluate JavaScript    ${CHAT}    (c) => { c.scrollTop = 0 }
    ${state}=    Chat Scroll State
    Should Be Equal As Numbers    ${state}[top]    0
    Should Be True    ${state}[firstTop] >= ${state}[chatTop] - 1    msg=The start of the messages cannot be reached by scrolling
    Get Text    ${CHAT} >> css=.assistant-message >> nth=0    contains    Voin ehdottaa hakemukseen kohdennettuja muutoksia
    Click    ${IMPORT_MESSAGE} >> css=.import-toolbar button:text-is("Poista valinnat")
    Check Checkbox    ${IMPORT_MESSAGE} >> css=.import-row >> nth=0 >> css=input[type="checkbox"]
    Evaluate JavaScript    ${CHAT}    (c) => { c.scrollTop = 0 }
    Click    ${IMPORT_SAVE}
    Wait For Elements State    css=.assistant-message:has-text("Tallennettiin 1 hakemusta.")    visible
    Sleep    500ms
    ${state}=    Chat Scroll State
    Should Be True    ${state}[top] + ${state}[client] >= ${state}[height] - 2    msg=The new message did not scroll the area to the bottom
    Should Be True    ${state}[client] <= 430

Chat is kept across tab switches and cleared by a reload
    [Documentation]    TC19-008. The import answer is mocked. Expected result: after unticking the first row and
    ...    visiting Hakemukset and Eteneminen, the AI chat still has the import option on, the list and the
    ...    unticked row; after a reload the chat is empty and every tool option is off.
    [Teardown]    Finish Mocked Test
    Mock Import Answer    3    ROBOT UI Säilyy
    Open Assistant
    Import Mocked File
    Uncheck Checkbox    ${IMPORT_MESSAGE} >> css=.import-row >> nth=0 >> css=input[type="checkbox"]
    FOR    ${section}    IN    Hakemukset    Eteneminen
        Go To Section    ${section}
        Get Element Count    ${IMPORT_MESSAGE}    ==    0
    END
    Open Assistant
    Get Element Count    ${IMPORT_MESSAGE}    ==    1
    Get Checkbox State    ${IMPORT_TOGGLE}    ==    checked
    Get Element Count    ${IMPORT_MESSAGE} >> css=.import-row    ==    3
    Get Checkbox State    ${IMPORT_MESSAGE} >> css=.import-row >> nth=0 >> css=input[type="checkbox"]    ==    unchecked
    Get Checkbox State    ${IMPORT_MESSAGE} >> css=.import-row >> nth=1 >> css=input[type="checkbox"]    ==    checked
    Get Text    ${IMPORT_SAVE}    ==    Tallenna valitut (2)
    Reload
    Wait For Workspace
    Open Assistant
    Get Element Count    ${IMPORT_MESSAGE}    ==    0
    Get Element Count    css=.user-message    ==    0
    FOR    ${toggle}    IN    ${POSTING_TOGGLE}    ${IMPORT_TOGGLE}    ${DELETE_TOGGLE}
        Get Checkbox State    ${toggle}    ==    unchecked
    END

Unsaved import list makes leaving the page ask first
    [Documentation]    TC19-009. The import answer is mocked. Expected result: the page does not cancel beforeunload
    ...    without a list; while the imported list has unsaved rows it cancels beforeunload (the browser asks
    ...    before reloading or closing), also after a tab switch; after "Sulje lista" it no longer does.
    [Teardown]    Finish Mocked Test
    Mock Import Answer    2    ROBOT UI Varoitus
    Open Assistant
    ${blocked}=    Before Unload Is Blocked
    Should Be Equal    ${blocked}    ${False}
    Import Mocked File
    ${blocked}=    Before Unload Is Blocked
    Should Be Equal    ${blocked}    ${True}    msg=An unsaved import list does not warn before leaving
    Go To Section    Hakemukset
    ${blocked}=    Before Unload Is Blocked
    Should Be Equal    ${blocked}    ${True}    msg=The warning is lost when the AI chat tab is left
    Open Assistant
    Click    ${IMPORT_MESSAGE} >> css=button.message-close
    Get Element Count    ${IMPORT_MESSAGE}    ==    0
    ${blocked}=    Before Unload Is Blocked
    Should Be Equal    ${blocked}    ${False}

Delete search lists the matches and deletes only the confirmed ones once
    [Documentation]    TC19-010. The search answer is mocked with three real applications of user A; deleting uses
    ...    the real backend. Expected result: the request carries the typed message; the chat shows the criteria
    ...    and "Löysin 3 hakemusta…" with all rows selected and "Poista valitut (3)"; nothing is deleted by the
    ...    search; after unticking one row the dialog says "Poistetaanko 2 hakemusta?" and names both companies;
    ...    Peruuta deletes nothing; confirming (double click) sends exactly one bulk-delete request with the two
    ...    selected ids, reports "Poistettiin 2 hakemusta.", marks them "Poistettu" and removes the delete button,
    ...    so it cannot be pressed again; the unticked and the other applications stay.
    [Teardown]    Finish Mocked Test
    ${d1}=    Create Application As    A    company=ROBOT Poista Yksi Oy    status=Hylätty
    ${d2}=    Create Application As    A    company=ROBOT Poista Kaksi Oy    status=Hylätty
    ${d3}=    Create Application As    A    company=ROBOT Poista Kolme Oy    status=Hylätty
    Create Application As    A    company=ROBOT Poista Muu Oy    status=Lähetetty
    Reload
    Wait For Workspace
    Mock Delete Answer    ${{ [$d1, $d2, $d3] }}    ${False}    Tila: Hylätty
    Open Assistant
    ${before}=    Company Names Of A
    Search Deletable    Poista hylätyt hakemukset
    ${bodies}=    Get Mocked Request Bodies
    ${sent}=    Evaluate    json.loads(json.loads($bodies)[-1])    modules=json
    Should Be Equal    ${sent}    ${{ {'message': 'Poista hylätyt hakemukset'} }}
    Get Text    ${DELETE_MESSAGE} >> css=p >> nth=0    ==    Ymmärsin hakuehdot: Tila: Hylätty
    Get Text    ${DELETE_MESSAGE} >> css=p >> nth=1    ==    Löysin 3 hakemusta. Valitse poistettavat. Mitään ei poisteta ennen vahvistustasi.
    Get Element Count    ${DELETE_MESSAGE} >> css=.import-row input:checked    ==    3
    Get Text    ${DELETE_BUTTON}    ==    Poista valitut (3)
    ${unchanged}=    Company Names Of A
    Should Be Equal    ${unchanged}    ${before}
    Uncheck Checkbox    ${DELETE_MESSAGE} >> css=.import-row:has-text("ROBOT Poista Kolme Oy") input
    Get Text    ${DELETE_BUTTON}    ==    Poista valitut (2)
    Click    ${DELETE_BUTTON}
    Wait For Elements State    ${CONFIRM}    visible
    Get Text    css=#confirm-dialog-title    ==    Poistetaanko 2 hakemusta?
    Get Text    css=#confirm-dialog-description    ==    Tätä ei voi perua. Poistettavat: ROBOT Poista Yksi Oy, ROBOT Poista Kaksi Oy.
    Click    css=.confirm-cancel
    Wait For Elements State    ${CONFIRM}    detached
    ${cancelled}=    Company Names Of A
    Should Be Equal    ${cancelled}    ${before}    msg=Peruuta deleted applications
    Start Recording Requests    /api/applications/bulk-delete
    Click    ${DELETE_BUTTON}
    Wait For Elements State    ${CONFIRM}    visible
    Click With Options    css=.confirm-danger    left    clickCount=2
    Wait For Elements State    css=.assistant-message:has-text("Poistettiin 2 hakemusta.")    visible
    Sleep    1s
    ${requests}=    Get Recorded Requests
    ${requests}=    Evaluate    json.loads($requests)    modules=json
    Length Should Be    ${requests}    1    msg=The delete was sent more than once: ${requests}
    ${ids}=    Evaluate    sorted(json.loads($requests[0]['body'])['ids'])    modules=json
    Should Be Equal    ${ids}    ${{ sorted([$d1['id'], $d2['id']]) }}
    ${after}=    Company Names Of A
    Should Be Equal    ${after}    ${{ sorted(n for n in $before if n not in ('ROBOT Poista Yksi Oy', 'ROBOT Poista Kaksi Oy')) }}
    Get Element Count    ${DELETE_MESSAGE} >> css=.import-flag:text-is("Poistettu")    ==    2
    Get Element Count    ${DELETE_BUTTON}    ==    0
    Get Element Count    ${CONFIRM}    ==    0
    Get Property    ${DELETE_MESSAGE} >> css=.import-row:has-text("ROBOT Poista Kolme Oy") input    disabled    ==    ${True}

Delete search with no matches or no criteria shows a message without a delete button
    [Documentation]    TC19-011. The search answer is mocked. Expected result: an answer with no applications shows
    ...    "Ehdoilla ei löytynyt yhtään hakemusta." and an answer that needs more detail shows the request to be
    ...    more specific; neither has a delete button or rows, and nothing is deleted.
    [Teardown]    Finish Mocked Test
    Create Application As    A    company=ROBOT Ei Osumaa Oy
    Reload
    Wait For Workspace
    ${before}=    Company Names Of A
    Mock Delete Answer    ${{ [] }}    ${False}    Yritys sisältää "ei-ole-olemassa"
    Open Assistant
    Search Deletable    Poista yrityksen ei-ole-olemassa hakemukset
    Get Text    ${DELETE_MESSAGE} >> css=p >> nth=1    ==    Ehdoilla ei löytynyt yhtään hakemusta.
    Get Element Count    ${DELETE_BUTTON}    ==    0
    Get Element Count    ${DELETE_MESSAGE} >> css=.import-row    ==    0
    Clear Mocked Responses
    Mock Delete Answer    ${{ [] }}    ${True}
    Fill Text    ${COMPOSER}    Poista ne
    Click    ${SEND}
    Wait For Elements State    ${DELETE_MESSAGE} >> nth=1    visible
    Get Text    ${DELETE_MESSAGE} >> nth=1 >> css=p    ==    En löytänyt pyynnöstä yhtään selvää hakuehtoa, joten en hae kaikkia hakemuksia. Tarkenna, esimerkiksi tila, yritys tai päivämäärä.
    Get Element Count    ${DELETE_BUTTON}    ==    0
    ${after}=    Company Names Of A
    Should Be Equal    ${after}    ${before}

Import and delete lists fit small screens without horizontal scrolling
    [Documentation]    TC19-012. The answers are mocked. Expected result: at 320, 360, 390 and 768 px the AI chat with
    ...    the import option on, a 50 row import list with long names, and then a delete list in the same chat fit
    ...    the screen width, and the message area stays within its own height limit (55vh on these widths,
    ...    Message Area Should Not Grow).
    [Teardown]    Run Keywords    Finish Mocked Test    AND    Close Mobile Workspace
    ${long}=    Create Application As    A    company=ROBOT-Pitkänimisenyrityksenkonsernipalvelutosakeyhtiö-poistettava
    # Built before the phone session: Api Request switches to user A's own desktop session.
    ${import_body}=    Import Answer Body    50    ROBOT-Pitkänimisenyrityksenkonsernipalvelutosakeyhtiö    ${ROWS_NOTICE}
    FOR    ${width}    IN    @{MOBILE_WIDTHS}
        Open Mobile Workspace    ${width}
        ${viewport}=    Get Viewport Size
        Should Be Equal As Integers    ${viewport}[width]    ${width}    msg=The test is not running in the phone session
        Mock Json Response    **/api/assistant/import-applications    200    ${import_body}
        Mock Delete Answer    ${{ [$long] }}    ${False}    Yritys sisältää "Pitkänimisen"
        Open Assistant
        Page Should Not Scroll Horizontally
        Import Mocked File
        Page Should Not Scroll Horizontally
        Click    ${IMPORT_MESSAGE} >> css=.import-row >> nth=0 >> css=.import-row-toggle
        Wait For Elements State    ${IMPORT_MESSAGE} >> css=.import-row-editor    visible
        Page Should Not Scroll Horizontally
        Uncheck Checkbox    ${IMPORT_TOGGLE}
        Search Deletable    Poista pitkänimisen yrityksen hakemus
        Page Should Not Scroll Horizontally
        Message Area Should Not Grow
        Clear Mocked Responses
        Close Mobile Workspace
    END

File import without an OpenAI key shows the app's error and keeps the page working
    [Documentation]    TC19-013. Runs only against a backend without OPENAI_API_KEY (tag no-openai-key); the real
    ...    import route is used. Expected result: sending a valid workbook shows "AI-palvelua ei ole vielä
    ...    määritetty.", no list appears, the attachment stays so it can be sent again, and nothing is saved.
    [Tags]    no-openai-key
    Require Backend Without OpenAI Key
    ${before}=    Company Names Of A
    Open Assistant
    Check Checkbox    ${IMPORT_TOGGLE}
    Upload File By Selector    ${FILE_INPUT}    ${IMPORT_FILE}
    Click    ${SEND}
    Wait For Elements State    ${CHAT_ERROR}    visible
    Get Text    ${CHAT_ERROR}    ==    ${AI_NOT_CONFIGURED_ERROR}
    Get Element Count    ${IMPORT_MESSAGE}    ==    0
    Wait For Elements State    css=.chat-attachment:has-text("robot-ui-tuonti.xlsx")    visible
    Get Property    ${SEND}    disabled    ==    ${False}
    ${after}=    Company Names Of A
    Should Be Equal    ${after}    ${before}
    ${errors}=    Get Page Errors
    Should Be Empty    ${errors}

The workspace names no job site
    [Documentation]    TC19-014. Expected result: the text of every workspace section (overview, applications,
    ...    timeline, calendar, materials and the AI chat with its context column) contains no web address other
    ...    than the service's own (Text Should Name No Job Site).
    [Tags]    privacy
    FOR    ${section}    IN    Yleiskatsaus    Hakemukset    Eteneminen    Kalenteri    CV & pohjat    AI-chat
        Go To Section    ${section}
        ${text}=    Get Text    css=body
        Text Should Name No Job Site    ${text}    The section ${section}
    END

Signing out clears the chat
    [Documentation]    TC19-015. Runs last, because it signs user A out and in again in the same browser session.
    ...    The import answer is mocked. Expected result: after an import list is shown, signing out returns to the
    ...    landing page, and after signing in again (without reloading the page) the AI chat is empty and every
    ...    tool option is off.
    [Teardown]    Finish Mocked Test
    Mock Import Answer    2    ROBOT UI Ulos
    Open Assistant
    Import Mocked File
    Click    css=.cl-userButtonTrigger
    Click    text=Kirjaudu ulos
    Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible    timeout=30s
    Get Element Count    ${IMPORT_MESSAGE}    ==    0
    Sign In Without Reload
    Open Assistant
    Get Element Count    ${IMPORT_MESSAGE}    ==    0
    Get Element Count    css=.user-message    ==    0
    FOR    ${toggle}    IN    ${POSTING_TOGGLE}    ${IMPORT_TOGGLE}    ${DELETE_TOGGLE}
        Get Checkbox State    ${toggle}    ==    unchecked
    END
