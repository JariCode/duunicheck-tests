*** Settings ***
Documentation     Printing on the device types the app tells apart (frontend/src/utils/printTarget.js) and the
...               dashboard metric cards on phones. The iOS home screen app makes the PDF on the device and
...               hands it to the share sheet, Safari and the Dock app on a Mac open the PDF in a new tab (or
...               download it when the tab is blocked), and other browsers keep calling window.print(). The
...               devices are emulated in Chromium (see Emulate Print Device); the real share sheet, Safari's
...               PDF view and the paper output are checked by hand (MANUAL_TESTS.md).
Resource          ../resources/print_pdf.robot
Suite Setup       Prepare Print Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    pdf-print


*** Variables ***
${CV_NAME}          ROBOT Tulostus-CV
${FULL_NAME}        Väinö Testinen
${TEMPLATE_NAME}    ROBOT Tulostuspohja
${COMPANY}          ROBOT Tulostin Oy
# printPdf.js pdfFileName: CV_<full name>, Hakemus_<company> for the cover letter ("Tulosta hakukirje"),
# Hakemus_<company>_<role> for the application summary ("Tulosta yhteenveto / PDF"), spaces as underscores.
${CV_PDF}           CV_Väinö_Testinen.pdf
${APPLICATION_PDF}    Hakemus_ROBOT_Tulostin_Oy.pdf
${SUMMARY_PDF}      Hakemus_ROBOT_Tulostin_Oy_Testaaja.pdf
# The application summary tests (TC23-014..020). Every name, address and number is made up.
${FULL_COMPANY}     ROBOT Esimerkki Oy
${FULL_ROLE}        Frontend-kehittäjä
${FULL_LINK}        https://example.com/tyopaikat/frontend-kehittaja
${FULL_NOTES}       Rekrytoija: Matti Meikäläinen, matti.meikalainen@example.com\nPuhelin +358 00 000 0000\n\nKysy etätyön mahdollisuudesta.
${FULL_TEMPLATE}    ROBOT Yhteenvedon pohja
${FULL_PDF}         Hakemus_ROBOT_Esimerkki_Oy_Frontend-kehittäjä.pdf
${MINIMAL_COMPANY}    ROBOT Vähäinen Oy
${DELETED_COMPANY}    ROBOT Poistettu Liite Oy
${DELETED_CV_NAME}    ROBOT Poistuva CV
${KEPT_LETTER}      robot-yhteenveto-kirje.txt
${DELETED_LETTER}    robot-poistuva-kirje.txt
${OLD_TEXT_COMPANY}    ROBOT Vanha Teksti Oy
${OLD_TEXT_NOTES}    Oma muistiinpano: soita rekrytoijalle.
${OLD_TEXT_PDF}     Hakemus_ROBOT_Vanha_Teksti_Oy_Myyjä.pdf
# The CVs and the template of the layout tests (TC23-008..013). Every name and address is made up.
${PERSON}           Matti Meikäläinen
${PERSON_EMAIL}     matti.meikalainen@example.com
# Area code 00 does not exist, so this can never be a real number.
${PERSON_PHONE}     +358 00 000 0000
${SHORT_CV_NAME}    ROBOT Lyhyt CV
${LONG_CV_NAME}     ROBOT Pitkä CV
${PERSON_CV_PDF}    CV_Matti_Meikäläinen.pdf
${LETTER_TEMPLATE}    ROBOT Kirjepohja ilman hakemusta
# A template printed from CV & pohjat has no application, so the file is named after its full name.
${TEMPLATE_PDF}     Hakemus_Matti_Meikäläinen.pdf


*** Keywords ***
Prepare Print Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    Prepare Layout Data
    Prepare Summary Data
    Prepare Print Data    ${CV_NAME}    ${FULL_NAME}    ${TEMPLATE_NAME}    ${COMPANY}

Prepare Summary Data
    [Documentation]    The applications of the summary tests, saved before Prepare Print Data, which reloads the
    ...    workspace: a full one (every fact, an app CV and a template, three events, notes), a minimal one
    ...    (only company and role), one whose CV and one of two cover letter files are hidden from the app in
    ...    TC23-019, and one with an old application text too long to be moved into its notes.
    ${template}=    Create Template As    A    name=${FULL_TEMPLATE}
    ${expr}=    Catenate
    ...    [
    ...    {'id': '1', 'type': 'Lähetetty', 'date': '2026-11-02', 'note': 'Lähetetty sähköpostilla'},
    ...    {'id': '2', 'type': 'Vastaus saatu', 'date': '2026-11-05', 'note': ''},
    ...    {'id': '3', 'type': 'Haastattelu sovittu', 'date': '2026-11-10', 'note': 'Etähaastattelu klo 10'}]
    ${events}=    Evaluate    ${expr}
    Create Application As    A    company=${FULL_COMPANY}    role=${FULL_ROLE}    place=Helsinki    link=${FULL_LINK}
    ...    status=Haastattelu sovittu    added=2026-11-02    respondedAt=2026-11-05    next=Valmistaudu haastatteluun
    ...    nextDate=2026-11-20    notes=${FULL_NOTES}    cvId=${SHORT_CV}[id]    templateId=${template}[id]
    ...    events=${events}
    Create Application As    A    company=${MINIMAL_COMPANY}    role=Harjoittelija
    ${cv}=    Create Cv As    A    name=${DELETED_CV_NAME}
    ${kept}=    Upload Text File As    A    application    ${KEPT_LETTER}    Säilyvä hakukirje
    ${deleted}=    Upload Text File As    A    application    ${DELETED_LETTER}    Poistuva hakukirje
    Create Application As    A    company=${DELETED_COMPANY}    role=Testaaja    cvId=${cv}[id]
    ...    applicationFileIds=${{ [$kept['id'], $deleted['id']] }}
    Set Suite Variable    ${DELETED_CV_ID}    ${cv}[id]
    Set Suite Variable    ${DELETED_LETTER_ID}    ${deleted}[id]
    ${text}=    Evaluate
    ...    '\\n\\n'.join(f'Kappale {n}. Olen kiinnostunut tehtävästä, koska haluan kehittää asiakaspalvelua ja myyntiä yhdessä tiimin kanssa.' for n in range(1, 81))
    Should Be True    len($OLD_TEXT_NOTES) + len($text) + 17 > 8000 and len($text) <= 20000
    Create Application As    A    company=${OLD_TEXT_COMPANY}    role=Myyjä    notes=${OLD_TEXT_NOTES}
    ...    applicationText=${text}
    Set Suite Variable    ${OLD_TEXT}    ${text}

Full Summary
    [Documentation]    What the summary of the full application (Prepare Summary Data) shows: the facts in
    ...    their order, the attachments by name, the events newest first, the notes; the link without its scheme.
    ${expr}=    Catenate
    ...    {
    ...    'title': $FULL_ROLE, 'subtitle': $FULL_COMPANY + ' · Helsinki',
    ...    'headings': ['Perustiedot', 'Liitteet', 'Tapahtumahistoria', 'Muistiinpanot'],
    ...    'facts': [['Yritys', $FULL_COMPANY], ['Tehtävä', $FULL_ROLE], ['Sijainti', 'Helsinki'],
    ...    ['Ilmoituksen linkki', 'example.com/tyopaikat/frontend-kehittaja'], ['Vaihe', 'Haastattelu sovittu'],
    ...    ['Lähetyspäivä', '02.11.2026'], ['Vastauspäivä', '05.11.2026'],
    ...    ['Seuraava tehtävä', 'Valmistaudu haastatteluun'], ['Muistutuspäivä', '20.11.2026']],
    ...    'attachments': [['Sovelluksen CV', $SHORT_CV_NAME], ['Hakemuspohja', $FULL_TEMPLATE]],
    ...    'events': [['10.11.2026', 'Haastattelu sovittu', 'Etähaastattelu klo 10'], ['05.11.2026', 'Vastaus saatu', ''],
    ...    ['02.11.2026', 'Lähetetty', 'Lähetetty sähköpostilla']],
    ...    'notes': $FULL_NOTES, 'applicationText': None,
    ...    'link': {'href': $FULL_LINK, 'text': 'example.com/tyopaikat/frontend-kehittaja'}}
    ${expected}=    Evaluate    ${expr}
    RETURN    ${expected}

Minimal Summary
    ${expr}=    Catenate
    ...    {
    ...    'title': 'Harjoittelija', 'subtitle': $MINIMAL_COMPANY, 'headings': ['Perustiedot'],
    ...    'facts': [['Yritys', $MINIMAL_COMPANY], ['Tehtävä', 'Harjoittelija'], ['Vaihe', 'Kiinnostava']],
    ...    'attachments': None, 'events': None, 'notes': None, 'applicationText': None, 'link': None}
    ${expected}=    Evaluate    ${expr}
    RETURN    ${expected}

Old Text Summary
    ${expr}=    Catenate
    ...    {
    ...    'title': 'Myyjä', 'subtitle': $OLD_TEXT_COMPANY,
    ...    'headings': ['Perustiedot', 'Muistiinpanot', 'Vanha hakemusteksti'],
    ...    'facts': [['Yritys', $OLD_TEXT_COMPANY], ['Tehtävä', 'Myyjä'], ['Vaihe', 'Kiinnostava']],
    ...    'attachments': None, 'events': None, 'notes': $OLD_TEXT_NOTES, 'applicationText': $OLD_TEXT, 'link': None}
    ${expected}=    Evaluate    ${expr}
    RETURN    ${expected}

Mock Lists Without
    [Documentation]    Makes the app's GET /api/cvs and GET /api/files answer the real lists without the given
    ...    CV and file, as if they had been deleted while the application still points to them. The workspace
    ...    is reloaded afterwards. The lists are read before the device session is opened, because Api Request
    ...    switches back to player A's own session.
    [Arguments]    ${cvs}    ${files}    ${cv_id}    ${file_id}
    ${cv_body}=    Evaluate    json.dumps([c for c in $cvs if c['id'] != $cv_id])    modules=json
    ${file_body}=    Evaluate    json.dumps([f for f in $files if f['id'] != $file_id])    modules=json
    Mock Json Response    **/api/cvs    200    ${cv_body}
    Mock Json Response    **/api/files    200    ${file_body}
    Reload
    Wait For Workspace

Prepare Layout Data
    [Documentation]    A short CV that fits on one page even with the largest gaps (1.8), a long CV that does
    ...    not fit on one page even with the smallest gaps (0.6) but fits on two, and a template with its own
    ...    name and contact details. Saved before Prepare Print Data, which reloads the workspace.
    ${photo}=    Png Data Uri    64    80
    ${short}=    Create Cv As    A    name=${SHORT_CV_NAME}    fullName=${PERSON}    title=Ohjelmistotestaaja
    ...    email=${PERSON_EMAIL}    phone=${PERSON_PHONE}    photo=${photo}
    ...    summary=Testaaja, joka rakentaa automaattisia testejä verkkosovelluksille ja kertoo löydöksistä selkeästi.
    ...    skills=Robot Framework\nPlaywright\nPython    languages=Suomi, äidinkieli\nEnglanti, sujuva
    ...    experience=Testaaja, Esimerkki Oy, 2022–2026\nTestiautomaation rakentaminen ja ylläpito.
    ...    education=Tradenomi, tietojenkäsittely
    ${jobs}=    Evaluate
    ...    '\\n\\n'.join(f'Testaaja {n}, Esimerkkiyritys {n} Oy, {2000 + n}–{2001 + n}\\nTestiautomaation rakentaminen ja ylläpito verkkopalvelulle.\\nRegressiotestien suunnittelu ja ajaminen ennen julkaisuja.\\nVirheraporttien kirjoittaminen ja kehittäjien tukeminen.' for n in range(1, 15))
    ${skills}=    Evaluate    '\\n'.join(f'Testaustaito {n}' for n in range(1, 19))
    ${education}=    Evaluate    '\\n'.join(f'Koulutusohjelma {n}, Esimerkkiopisto' for n in range(1, 7))
    ${certificates}=    Evaluate    '\\n'.join(f'Sertifikaatti {n}' for n in range(1, 9))
    ${courses}=    Evaluate    '\\n'.join(f'Verkkokurssi {n}' for n in range(1, 11))
    ${long}=    Create Cv As    A    name=${LONG_CV_NAME}    fullName=${PERSON}    title=Ohjelmistotestaaja
    ...    email=${PERSON_EMAIL}    phone=${PERSON_PHONE}    photo=${photo}
    ...    summary=Kokenut testaaja, joka on rakentanut testiautomaatiota neljäntoista vuoden ajan ja kouluttanut kehittäjiä testaamaan omaa koodiaan.
    ...    skills=${skills}    languages=Suomi, äidinkieli\nEnglanti, sujuva\nRuotsi, tyydyttävä\nSaksa, alkeet
    ...    experience=${jobs}    education=${education}    certificates=${certificates}    courses=${courses}
    ...    hobbies=Suunnistus, shakki, valokuvaus ja vapaaehtoistyö paikallisessa urheiluseurassa.
    Set Suite Variable    ${SHORT_CV}    ${short}
    Set Suite Variable    ${LONG_CV}    ${long}
    # Long enough, with links, to make a PDF of a real letter's size (over MIN_PDF_BYTES): pdfmake embeds only the
    # glyphs used.
    Create Template As    A    name=${LETTER_TEMPLATE}    fullName=${PERSON}
    ...    email=${PERSON_EMAIL}    phone=${PERSON_PHONE}
    ...    github=https://github.com/example    portfolio=https://example.com/portfolio
    ...    body=Hei,\n\nHaen avointa testaajan tehtävää. Rakennan testiautomaatiota verkkosovelluksille ja kirjoitan selkeitä virheraportteja (Robot Framework, Playwright, Python, JavaScript, REST-rajapinnat, Git, CI/CD).\n\n# Miksi juuri minä\nOlen työskennellyt kuusi vuotta kehitystiimeissä, joissa julkaisut tehtiin viikoittain. Löysin vaikeat virheet ajoissa, automatisoin 80 % regressiotesteistä ja kuvasin löydökset niin, että kehittäjät korjasivat ne nopeasti. Zoom- ja Q&A-tilaisuuksissa kerroin testauksen tuloksista myös asiakkaille.\n\nKerron mielelläni lisää haastattelussa; voin aloittaa heti tai sopimuksen mukaan.\n\nYstävällisin terveisin,\n{{nimi}}

Share Pdf On iPhone
    [Documentation]    In the iPhone session: the PDF dialog gets ready, "Tulosta / jaa PDF" hands exactly
    ...    one PDF with the right name and title to the share sheet, the dialog closes and the app window
    ...    never prints. Returns the text of every page of the shared PDF.
    [Arguments]    ${file_name}    ${title}
    Pdf Dialog Should Become Ready    ${file_name}    ${SHARE_PDF_BUTTON}
    Get Text    ${PDF_DIALOG_TEXT}    contains    Valitse jakovalikosta Tulosta tai Tallenna tiedostoihin.
    Get Element Count    ${OPEN_PDF_BUTTON}    ==    0
    Click    ${SHARE_PDF_BUTTON}
    ${shared}=    Shared File Should Be    ${file_name}
    Should Be Equal    ${shared}[title]    ${title}
    ${capture}=    Print Capture
    Length Should Be    ${capture}[canShareCalls]    1
    Should Be Equal    ${capture}[canShareCalls][0][name]    ${file_name}
    Wait For Elements State    ${PDF_DIALOG}    detached
    App Window Should Not Print
    Get Element Count    css=.print-document    ==    0
    ${capture}=    Print Capture
    Should Be Empty    ${capture}[opened]
    ${pages}=    Shared Pdf Pages
    RETURN    ${pages}

Open Pdf On Mac Safari
    [Documentation]    In the Mac Safari session: the PDF dialog gets ready, "Avaa PDF" opens the PDF's blob
    ...    URL in a new tab (_blank), the dialog closes and the app window never prints. Returns the text
    ...    of every page of the opened PDF.
    [Arguments]    ${file_name}    ${min_bytes}=${MIN_PDF_BYTES}
    Pdf Dialog Should Become Ready    ${file_name}    ${OPEN_PDF_BUTTON}
    Get Text    ${PDF_DIALOG_TEXT}    contains    Paina Avaa PDF
    Get Element Count    ${SHARE_PDF_BUTTON}    ==    0
    Click    ${OPEN_PDF_BUTTON}
    Wait For Elements State    ${PDF_DIALOG}    detached
    ${capture}=    Print Capture
    Length Should Be    ${capture}[opened]    1
    ${opened}=    Set Variable    ${capture}[opened][0]
    Should Start With    ${opened}[url]    blob:
    Should Be Equal    ${opened}[target]    _blank
    Blob Should Be A Pdf    ${opened}[url]    ${min_bytes}
    App Window Should Not Print
    Get Element Count    css=.print-document    ==    0
    ${capture}=    Print Capture
    Should Be Empty    ${capture}[shares]
    Should Be Empty    ${capture}[canShareCalls]
    ${pages}=    Opened Pdf Pages    ${opened}[url]
    RETURN    ${pages}

Wait For Chrome Print
    [Documentation]    In the Chrome session: window.print() has been called once and the print sheet of the
    ...    given class is rendered.
    [Arguments]    ${sheet}
    Wait Until Keyword Succeeds    5s    200ms    Print Count Should Be    1
    Get Element Count    css=.print-document.${sheet}    ==    1

Finish Chrome Print
    [Documentation]    Fires afterprint, which removes the print sheet, and forgets the recorded calls.
    Evaluate JavaScript    ${None}    () => window.dispatchEvent(new Event('afterprint'))
    Wait For Elements State    css=.print-document    detached
    Clear Print Capture

Close Pdf Dialog
    Click    ${PDF_DIALOG} >> button:text-is("Sulje")
    Wait For Elements State    ${PDF_DIALOG}    detached

Print Count Should Be
    [Arguments]    ${count}
    ${capture}=    Print Capture
    Should Be Equal As Integers    ${capture}[prints]    ${count}

Print In Chrome
    [Documentation]    In the Chrome session: the print sheet of the given class is rendered and window.print()
    ...    is called exactly once, no PDF dialog opens and nothing is shared or opened. afterprint removes the
    ...    print sheet again.
    [Arguments]    ${sheet}    ${text}
    Wait Until Keyword Succeeds    5s    200ms    Print Count Should Be    1
    Get Text    css=.print-document.${sheet}    contains    ${text}
    Get Element Count    ${PDF_DIALOG}    ==    0
    Evaluate JavaScript    ${None}    () => window.dispatchEvent(new Event('afterprint'))
    Wait For Elements State    css=.print-document    detached
    Sleep    1s
    Print Count Should Be    1
    Get Element Count    ${PDF_DIALOG}    ==    0
    ${capture}=    Print Capture
    Should Be Empty    ${capture}[shares]
    Should Be Empty    ${capture}[opened]

Metric Should Be Tilted
    [Arguments]    ${index}
    ${transform}=    Metric Transform    ${index}
    Should Not Be Equal    ${transform}    none    msg=Metric card ${index} does not tilt on mouse hover


*** Test Cases ***
iPhone home screen app shares the CV and the application summary as PDF files
    [Documentation]    TC23-001. The app runs as an iPhone home screen app (iPhone user agent,
    ...    navigator.standalone = true, phone session 390 px). Expected result: "Tulosta / tallenna PDF" of the
    ...    CV card and "Tulosta yhteenveto / PDF" in the application details open the PDF dialog, which goes from
    ...    "Luodaan PDF:ää…" to "PDF on valmis" and shows "Tulosta / jaa PDF". The button hands one file to
    ...    navigator.share: CV_Väinö_Testinen.pdf and Hakemus_ROBOT_Tulostin_Oy_Testaaja.pdf (title "Hakemus –
    ...    ROBOT Tulostin Oy"), type application/pdf,
    ...    over 10 kB, after navigator.canShare has accepted the same file. The dialog then closes, no print
    ...    sheet is rendered and window.print() is never called.
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Cv From Materials    ${CV_NAME}
    Share Pdf On iPhone    ${CV_PDF}    CV – ${FULL_NAME}
    Clear Print Capture
    Print Summary From Details    ${COMPANY}
    Share Pdf On iPhone    ${SUMMARY_PDF}    Hakemus – ${COMPANY}
    [Teardown]    Close Mobile Workspace

iPhone home screen app explains when the PDF cannot be shared
    [Documentation]    TC23-002. navigator.canShare answers false. Expected result: "Tulosta / jaa PDF" shows
    ...    "Jakaminen ei ole käytettävissä" with the advice to open the service in Safari, the button is
    ...    removed, navigator.share is not called, the dialog stays open until "Sulje" and nothing is printed.
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Set Print Capture    canShareResult    ${False}
    Print Cv From Materials    ${CV_NAME}
    Pdf Dialog Should Become Ready    ${CV_PDF}    ${SHARE_PDF_BUTTON}
    Click    ${SHARE_PDF_BUTTON}
    Get Text    ${PDF_DIALOG_TITLE}    ==    Jakaminen ei ole käytettävissä
    Get Text    ${PDF_DIALOG_TEXT}    contains    ${SAFARI_HELP}
    Wait For Elements State    ${SHARE_PDF_BUTTON}    detached
    ${capture}=    Print Capture
    Length Should Be    ${capture}[canShareCalls]    1
    Should Be Empty    ${capture}[shares]
    Wait For Elements State    ${PDF_DIALOG}    visible
    App Window Should Not Print
    Close Pdf Dialog
    [Teardown]    Close Mobile Workspace

iPhone home screen app keeps the dialog open when sharing is cancelled and shows a share error
    [Documentation]    TC23-003. Expected result: when navigator.share is rejected with AbortError (the user
    ...    closed the share sheet), no error is shown and the dialog stays open with "PDF on valmis" and the
    ...    button. When it is rejected with another error (NotAllowedError), the dialog shows "Jakaminen
    ...    epäonnistui" and keeps the button, so sharing can be tried again; a retry that succeeds closes the
    ...    dialog. window.print() is never called.
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Set Print Capture    shareResult    abort
    Print Cv From Materials    ${CV_NAME}
    Pdf Dialog Should Become Ready    ${CV_PDF}    ${SHARE_PDF_BUTTON}
    Click    ${SHARE_PDF_BUTTON}
    Shared File Should Be    ${CV_PDF}
    Sleep    1s
    Wait For Elements State    ${PDF_DIALOG}    visible
    Get Text    ${PDF_DIALOG_TITLE}    ==    ${PDF_READY_TITLE}
    Get Text    ${PDF_DIALOG_TEXT}    not contains    epäonnistui
    Wait For Elements State    ${SHARE_PDF_BUTTON}    visible
    Clear Print Capture
    Set Print Capture    shareResult    error
    Click    ${SHARE_PDF_BUTTON}
    Shared File Should Be    ${CV_PDF}
    Get Text    ${PDF_DIALOG_TITLE}    ==    Jakaminen epäonnistui
    Get Text    ${PDF_DIALOG_TEXT}    contains    Yritä uudelleen.
    Wait For Elements State    ${SHARE_PDF_BUTTON}    visible
    Clear Print Capture
    Set Print Capture    shareResult    resolve
    Click    ${SHARE_PDF_BUTTON}
    Shared File Should Be    ${CV_PDF}
    Wait For Elements State    ${PDF_DIALOG}    detached
    App Window Should Not Print
    [Teardown]    Close Mobile Workspace

Mac Safari opens the CV and the application summary PDF in a new tab
    [Documentation]    TC23-004. The app runs as Safari on a Mac (Mac Safari user agent, no
    ...    navigator.userAgentData, maxTouchPoints 0). Expected result: printing the CV and the application
    ...    summary ("Tulosta yhteenveto / PDF", Hakemus_ROBOT_Tulostin_Oy_Testaaja.pdf) opens the PDF dialog with "Avaa PDF" (not the share button). "Avaa PDF" calls window.open with the
    ...    blob URL of the PDF and the target _blank, the blob is a PDF of over 10 kB, the dialog closes,
    ...    nothing is shared and window.print() of the app window is never called. The new tab is a stand-in
    ...    that never loads; the print dialog of the real PDF tab is checked by hand.
    Open Print Device Workspace    mac-safari
    ${data}=    Evaluate JavaScript    ${None}    () => ({ ua: navigator.userAgent, uaData: navigator.userAgentData === undefined, touch: navigator.maxTouchPoints })
    Should Contain    ${data}[ua]    Macintosh
    Should Be True    ${data}[uaData]    msg=navigator.userAgentData is still there
    Should Be Equal As Integers    ${data}[touch]    0
    Print Cv From Materials    ${CV_NAME}
    Open Pdf On Mac Safari    ${CV_PDF}
    Clear Print Capture
    Print Summary From Details    ${COMPANY}
    Open Pdf On Mac Safari    ${SUMMARY_PDF}
    ${capture}=    Print Capture
    Should Be Equal As Integers    ${capture}[stubPrints]    0
    [Teardown]    Close Mobile Workspace

Mac Safari downloads the PDF when the new tab is blocked
    [Documentation]    TC23-005. window.open returns null (the browser blocked the new tab). Expected result:
    ...    "Avaa PDF" downloads the PDF as CV_Väinö_Testinen.pdf (a real PDF of over 10 kB), the dialog stays
    ...    open with the title "PDF ladattiin tiedostona" and the advice to find the file in Lataukset, the
    ...    button stays for a new try and window.print() is never called.
    Open Print Device Workspace    mac-safari
    Set Print Capture    openResult    null
    Print Cv From Materials    ${CV_NAME}
    Pdf Dialog Should Become Ready    ${CV_PDF}    ${OPEN_PDF_BUTTON}
    ${download}=    Promise To Wait For Download
    Click    ${OPEN_PDF_BUTTON}
    ${file}=    Wait For    ${download}
    Should Be Equal    ${file}[suggestedFilename]    ${CV_PDF}
    ${size}=    Get File Size    ${file}[saveAs]
    Should Be True    ${size} > ${MIN_PDF_BYTES}    msg=The downloaded PDF has only ${size} bytes
    ${head}=    Evaluate    open($file['saveAs'], 'rb').read(5)
    Should Be Equal    ${head}    ${{ b'%PDF-' }}
    Get Text    ${PDF_DIALOG_TITLE}    ==    PDF ladattiin tiedostona
    Get Text    ${PDF_DIALOG_TEXT}    contains    ${CV_PDF} ladattiin Lataukset-kansioon.
    Wait For Elements State    ${OPEN_PDF_BUTTON}    visible
    ${capture}=    Print Capture
    Length Should Be    ${capture}[opened]    1
    Should Start With    ${capture}[opened][0][url]    blob:
    Should Be Equal    ${capture}[opened][0][target]    _blank
    App Window Should Not Print
    Close Pdf Dialog
    [Teardown]    Close Mobile Workspace

Chrome still prints with window.print without the PDF dialog
    [Documentation]    TC23-006. The browser is Chromium as it is (not Safari, not iOS). Expected result: printing
    ...    the CV and the application summary renders the print sheet (print-cv, print-applicationSummary) and
    ...    calls window.print() exactly once each; the PDF dialog never opens, nothing is shared and no new tab
    ...    is opened.
    Open Print Device Workspace    chrome
    Print Cv From Materials    ${CV_NAME}
    Print In Chrome    print-cv    ${FULL_NAME}
    Clear Print Capture
    Print Summary From Details    ${COMPANY}
    Print In Chrome    print-applicationSummary    ${COMPANY}
    [Teardown]    Close Mobile Workspace

Metric cards have equal font sizes on phones and do not stay tilted after a tap
    [Documentation]    TC23-007. Expected result: in a phone session (touch, no mouse hover) of 390 px every one of
    ...    the five dashboard metric cards has the font sizes 9/27/8 px (label row div / number b / note
    ...    small), at 600 px 10/30/9 px, and a tapped card has no transform afterwards (it does not stay
    ...    tilted). At 1300 px with a mouse every card has 11/40/10 px, and a hovered card still tilts.
    FOR    ${width}    ${div}    ${b}    ${small}    IN
    ...    390    9px    27px    8px
    ...    600    10px    30px    9px
        Open Mobile Workspace    ${width}
        Go To Section    Yleiskatsaus
        Wait For Elements State    css=.metrics    visible
        ${hover}=    Evaluate JavaScript    ${None}    () => window.matchMedia('(hover: hover)').matches
        Should Be Equal    ${hover}    ${False}
        ...    msg=The ${width} px phone session reports hover: hover, so it does not test a touch screen
        Metric Font Sizes Should Be    ${div}    ${b}    ${small}    ${width} px
        FOR    ${index}    IN RANGE    5
            Tap    css=.metrics .metric >> nth=${index}
            Sleep    400ms
            ${transform}=    Metric Transform    ${index}
            Should Be Equal    ${transform}    none    msg=${width} px: metric card ${index} has the transform ${transform} after a tap
        END
        Close Mobile Workspace
    END
    Set Viewport Size    1300    900
    Go To Section    Yleiskatsaus
    Wait For Elements State    css=.metrics    visible
    Metric Font Sizes Should Be    11px    40px    10px    1300 px
    Hover    css=.metrics .metric >> nth=1
    Wait Until Keyword Succeeds    3s    200ms    Metric Should Be Tilted    1
    [Teardown]    Close Mobile Workspace

Chrome prints the CV with the contact line and the profile, a short CV on one page and a long CV on two
    [Documentation]    TC23-008. The CV print sheet in Chrome (window.print). Expected result: the header has the
    ...    name, the title, one contact line "email · phone" and the photo, but not the summary; the full-width
    ...    section "Profiili" with the summary comes right after the header, and there is no separate
    ...    Yhteystiedot box. Laid out for print, the short CV has the --cv-gap that the app's cvGapScale gives
    ...    it, over 1 and at most 1.8, its columns end within the A4 page (297 mm) and the profile's bottom
    ...    margin is 4 mm * --cv-gap. The long CV has --cv-gap 1, its columns continue past 297 mm (onto the
    ...    second page) and the profile margin is 4 mm. The name (20 pt) and the body text (8.5 pt) have the
    ...    same font sizes in both CVs.
    [Tags]    cv-print
    Open Print Device Workspace    chrome
    Print Cv From Materials    ${SHORT_CV_NAME}
    Wait For Chrome Print    print-cv
    Cv Print Sheet Should Have The New Layout    ${SHORT_CV}
    ${short}=    Print Sheet Layout
    ${scale}=    App Cv Gap Scale    ${SHORT_CV}
    Should Be True    1 < ${scale} <= 1.8    msg=The short CV got the gap scale ${scale}
    Should Be Equal As Numbers    ${short}[gap]    ${scale}    msg=--cv-gap of the print sheet is "${short}[gap]"
    Should Be True    ${short}[end] <= ${A4_HEIGHT_MM}    msg=The short CV ends at ${short}[end] mm
    Should Be True    abs(${short}[profileMargin] - 4 * ${scale}) < 0.05
    ...    msg=The profile margin is ${short}[profileMargin] mm with the gap scale ${scale}
    Finish Chrome Print
    Print Cv From Materials    ${LONG_CV_NAME}
    Wait For Chrome Print    print-cv
    Cv Print Sheet Should Have The New Layout    ${LONG_CV}
    ${long}=    Print Sheet Layout
    ${scale}=    App Cv Gap Scale    ${LONG_CV}
    Should Be Equal As Numbers    ${scale}    1
    Should Be Equal As Numbers    ${long}[gap]    1    msg=--cv-gap of the print sheet is "${long}[gap]"
    Should Be True    ${long}[end] > ${A4_HEIGHT_MM}    msg=The long CV ends at ${long}[end] mm, on the first page
    Should Be True    abs(${long}[profileMargin] - 4) < 0.05    msg=The profile margin is ${long}[profileMargin] mm
    Should Be Equal    ${long}[nameSize]    ${short}[nameSize]
    Should Be Equal    ${long}[textSize]    ${short}[textSize]
    Should Be True    abs(float($short['nameSize'][:-2]) - 20 * 4 / 3) < 0.01    msg=Name size ${short}[nameSize]
    Should Be True    abs(float($short['textSize'][:-2]) - 8.5 * 4 / 3) < 0.01    msg=Text size ${short}[textSize]
    Finish Chrome Print
    [Teardown]    Close Mobile Workspace

Mac Safari opens the CV PDF with the new layout on one or two pages
    [Documentation]    TC23-009. The PDF path of Safari on a Mac ("Avaa PDF"). Expected result: the PDF of the
    ...    short CV has one page, the app's gap scale for it (cvGapScale, which the PDF uses too) is over 1, and
    ...    the page reads name, title, "email · phone", "Profiili" and the summary before the columns; no
    ...    "Yhteystiedot", "Sähköposti" or "Puhelin" label is printed. The PDF of the long CV has the same
    ...    header and profile, gap scale 1 and two pages, the second one ending with the hobbies.
    [Tags]    cv-print
    Open Print Device Workspace    mac-safari
    Print Cv From Materials    ${SHORT_CV_NAME}
    ${pages}=    Open Pdf On Mac Safari    ${PERSON_CV_PDF}
    Cv Pdf Should Have The New Layout    ${pages}    ${SHORT_CV}    1
    ${scale}=    App Cv Gap Scale    ${SHORT_CV}
    Should Be True    1 < ${scale} <= 1.8    msg=The short CV got the gap scale ${scale}
    Clear Print Capture
    Print Cv From Materials    ${LONG_CV_NAME}
    ${pages}=    Open Pdf On Mac Safari    ${PERSON_CV_PDF}
    Cv Pdf Should Have The New Layout    ${pages}    ${LONG_CV}    2
    Pdf Text Should Contain In Order    ${pages}[1]    Harrastukset    ${LONG_CV}[hobbies]
    ${scale}=    App Cv Gap Scale    ${LONG_CV}
    Should Be Equal As Numbers    ${scale}    1
    [Teardown]    Close Mobile Workspace

iPhone home screen app shares the CV PDF with the new layout on one or two pages
    [Documentation]    TC23-010. The PDF path of the iOS home screen app ("Tulosta / jaa PDF"). Expected result:
    ...    as in TC23-009, the shared PDF of the short CV has one page and that of the long CV two pages, both
    ...    with name, title, "email · phone" and the "Profiili" section in that order and without a contact box;
    ...    the gap scale is over 1 for the short CV and 1 for the long one.
    [Tags]    cv-print
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Cv From Materials    ${SHORT_CV_NAME}
    ${pages}=    Share Pdf On iPhone    ${PERSON_CV_PDF}    CV – ${PERSON}
    Cv Pdf Should Have The New Layout    ${pages}    ${SHORT_CV}    1
    ${scale}=    App Cv Gap Scale    ${SHORT_CV}
    Should Be True    1 < ${scale} <= 1.8    msg=The short CV got the gap scale ${scale}
    Clear Print Capture
    Print Cv From Materials    ${LONG_CV_NAME}
    ${pages}=    Share Pdf On iPhone    ${PERSON_CV_PDF}    CV – ${PERSON}
    Cv Pdf Should Have The New Layout    ${pages}    ${LONG_CV}    2
    Pdf Text Should Contain In Order    ${pages}[1]    Harrastukset    ${LONG_CV}[hobbies]
    ${scale}=    App Cv Gap Scale    ${LONG_CV}
    Should Be Equal As Numbers    ${scale}    1
    [Teardown]    Close Mobile Workspace

Chrome prints the cover letter with the date in the header and no recipient box
    [Documentation]    TC23-011. The HAKUKIRJE print sheet in Chrome from "Tulosta hakukirje" in the details
    ...    and from the template card in CV & pohjat; "Tulosta yhteenveto / PDF" (until 17 November 2026
    ...    "Tulosta hakemus / PDF", which printed the same letter) now prints the HAKEMUS summary without any
    ...    part of the letter. Expected result: neither letter print has the recipient box (.letter-address-row, .letter-recipient, the labels Vastaanottaja and
    ...    Päiväys) or the place of the application (Esimerkkilä, shown only in that box), and the header's
    ...    contact list ends with today's date (li.letter-date time, e.g. "17. marraskuuta 2026") after the
    ...    email and the phone. The template print, which had no date before, now has it too.
    [Tags]    letter-print
    Open Print Device Workspace    chrome
    ${contacts}=    Create List    ${PRINT_CV}[email]    ${PRINT_CV}[phone]
    Print Letter From Details    ${COMPANY}    ${TEMPLATE_NAME}
    Wait For Chrome Print    print-application
    Letter Print Sheet Should Have The Date In The Header    ${contacts}    Esimerkkilä
    Get Text    css=.print-document .letter-content h2    ==    Testaaja
    Finish Chrome Print
    Click    ${SUMMARY_BUTTON}
    Wait For Chrome Print    print-applicationSummary
    Get Text    ${SUMMARY_SHEET} >> css=.letter-titlebar    ==    HAKEMUS
    Get Element Count    css=.print-document .letter-sender    ==    0
    Get Element Count    css=.print-document .letter-content    ==    0
    Finish Chrome Print
    Click    css=.detail-card >> button:text-is("Sulje")
    Print Template From Materials    ${LETTER_TEMPLATE}
    Wait For Chrome Print    print-application
    ${template_contacts}=    Create List    ${PERSON_EMAIL}    ${PERSON_PHONE}
    Letter Print Sheet Should Have The Date In The Header    ${template_contacts}
    Get Text    css=.print-document .letter-sender h1    ==    ${PERSON}
    Finish Chrome Print
    [Teardown]    Close Mobile Workspace

Mac Safari opens the cover letter PDF with the date in the header and no recipient box
    [Documentation]    TC23-012. Expected result: the PDF of "Tulosta hakukirje" in the details
    ...    (Hakemus_ROBOT_Tulostin_Oy.pdf; until 17 November 2026 printed with "Tulosta hakemus / PDF") reads
    ...    HAKUKIRJE, the name,
    ...    the email, the phone and today's date, then HAETTAVA TEHTÄVÄ and the role; it has no Vastaanottaja
    ...    or Päiväys label, the date is printed once, the place (Esimerkkilä) is not printed and the company
    ...    is named only once (in the letter). The PDF of the template printed from CV & pohjat has the
    ...    template's name, email, phone and the date in the header, before the letter.
    [Tags]    letter-print
    Open Print Device Workspace    mac-safari
    Print Letter From Details    ${COMPANY}    ${TEMPLATE_NAME}
    ${pages}=    Open Pdf On Mac Safari    ${APPLICATION_PDF}
    ${before}=    Create List    ${PRINT_CV}[email]    ${PRINT_CV}[phone]
    ${after}=    Create List    HAETTAVA TEHTÄVÄ    Testaaja    Hei,
    Letter Pdf Should Have The Date In The Header    ${pages}    ${FULL_NAME}    ${before}    ${after}
    ${all}=    Evaluate    ' '.join($pages)
    Pdf Text Should Not Contain    ${all}    Esimerkkilä
    ${count}=    Pdf Text Count    ${all}    ${COMPANY}
    Should Be Equal As Integers    ${count}    1    msg=The company is printed ${count} times
    Click    css=.detail-card >> button:text-is("Sulje")
    Clear Print Capture
    Print Template From Materials    ${LETTER_TEMPLATE}
    ${pages}=    Open Pdf On Mac Safari    ${TEMPLATE_PDF}
    ${before}=    Create List    ${PERSON_EMAIL}    ${PERSON_PHONE}
    ${after}=    Create List    Hei,    Ystävällisin terveisin,    ${PERSON}
    Letter Pdf Should Have The Date In The Header    ${pages}    ${PERSON}    ${before}    ${after}
    [Teardown]    Close Mobile Workspace

iPhone home screen app shares the cover letter PDF with the date in the header and no recipient box
    [Documentation]    TC23-013. Expected result: as in TC23-012 for the shared PDFs of "Tulosta hakukirje"
    ...    in the details (Hakemus_ROBOT_Tulostin_Oy.pdf) and of the template printed from CV & pohjat
    ...    (Hakemus_Matti_Meikäläinen.pdf, title "Hakemus"): the date is in the header after the contact lines,
    ...    and there is no recipient box.
    [Tags]    letter-print
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Letter From Details    ${COMPANY}    ${TEMPLATE_NAME}
    ${pages}=    Share Pdf On iPhone    ${APPLICATION_PDF}    Hakemus – ${COMPANY}
    ${before}=    Create List    ${PRINT_CV}[email]    ${PRINT_CV}[phone]
    ${after}=    Create List    HAETTAVA TEHTÄVÄ    Testaaja    Hei,
    Letter Pdf Should Have The Date In The Header    ${pages}    ${FULL_NAME}    ${before}    ${after}
    ${all}=    Evaluate    ' '.join($pages)
    Pdf Text Should Not Contain    ${all}    Esimerkkilä
    Click    css=.detail-card >> button:text-is("Sulje")
    Clear Print Capture
    Print Template From Materials    ${LETTER_TEMPLATE}
    ${pages}=    Share Pdf On iPhone    ${TEMPLATE_PDF}    Hakemus
    ${before}=    Create List    ${PERSON_EMAIL}    ${PERSON_PHONE}
    ${after}=    Create List    Hei,    Ystävällisin terveisin,    ${PERSON}
    Letter Pdf Should Have The Date In The Header    ${pages}    ${PERSON}    ${before}    ${after}
    [Teardown]    Close Mobile Workspace

Application details print button is named Tulosta yhteenveto / PDF
    [Documentation]    TC23-014. Expected result: the print buttons of the application details are, in this order,
    ...    "Tulosta yhteenveto / PDF", "Tulosta muistiinpanot / PDF" and "Avaa AI-chat tällä hakemuksella";
    ...    the old name "Tulosta hakemus / PDF" is nowhere in the details, and the cover letter keeps its own
    ...    button "Tulosta hakukirje: <template>".
    [Tags]    application-summary
    Open Application Details    ${COMPANY}
    ${labels}=    Evaluate JavaScript    ${None}
    ...    () => Array.from(document.querySelectorAll('.detail-print-actions button')).map((b) => b.textContent.trim())
    Should Be Equal    ${labels}    ${{ ['Tulosta yhteenveto / PDF', 'Tulosta muistiinpanot / PDF', 'Avaa AI-chat tällä hakemuksella'] }}
    Get Text    css=.detail-card    not contains    Tulosta hakemus
    Get Element Count    css=.detail-document:text-is("Tulosta hakukirje: ${TEMPLATE_NAME}")    ==    1
    Click    css=.detail-card >> button:text-is("Sulje")

Chrome prints the summary of a full application with every section and the events newest first
    [Documentation]    TC23-015. The application has every fact, an app CV, a template, three events and notes.
    ...    Expected result: "Tulosta yhteenveto / PDF" renders the print sheet print-applicationSummary (and calls
    ...    window.print() once) with the title bar HAKEMUS, the role as the heading, "ROBOT Esimerkki Oy ·
    ...    Helsinki", "Tulostettu <today>" and the sections Perustiedot (Yritys, Tehtävä, Sijainti, Ilmoituksen
    ...    linkki, Vaihe, Lähetyspäivä, Vastauspäivä, Seuraava tehtävä, Muistutuspäivä in this order, dates as
    ...    pp.kk.vvvv), Liitteet (the names of the CV and the template), Tapahtumahistoria (Päivä, Tapahtuma,
    ...    Lisätieto; 10.11., 05.11., 02.11.) and Muistiinpanot (the notes with their line breaks). The posting
    ...    link points to the full address and shows it without https://. No part of the cover letter is
    ...    printed, and laid out for print every section heading has break-after: avoid.
    [Tags]    application-summary
    ${expected}=    Full Summary
    Open Print Device Workspace    chrome
    Print Summary From Details    ${FULL_COMPANY}
    Wait For Chrome Print    print-applicationSummary
    Summary Print Sheet Should Be    ${expected}
    Summary Headings Should Not Break Alone
    Get Element Count    ${PDF_DIALOG}    ==    0
    Finish Chrome Print
    [Teardown]    Close Mobile Workspace

Mac Safari opens the summary PDF of a full application
    [Documentation]    TC23-016. Expected result: on a Mac (Safari) "Tulosta yhteenveto / PDF" opens the PDF
    ...    Hakemus_ROBOT_Esimerkki_Oy_Frontend-kehittäjä.pdf, whose text has the same content as the Chrome print
    ...    in TC23-015 in the same order (the events under PÄIVÄ, TAPAHTUMA, LISÄTIETO, newest first, the link
    ...    without https://), no HAKUKIRJE title bar and no "Vanha hakemusteksti", and no page ends with a
    ...    section heading. The app window never prints.
    [Tags]    application-summary
    ${expected}=    Full Summary
    Open Print Device Workspace    mac-safari
    Print Summary From Details    ${FULL_COMPANY}
    ${pages}=    Open Pdf On Mac Safari    ${FULL_PDF}
    Summary Pdf Should Be    ${pages}    ${expected}
    [Teardown]    Close Mobile Workspace

iPhone home screen app shares the summary PDF of a full application
    [Documentation]    TC23-017. Expected result: in the iPhone home screen app "Tulosta yhteenveto / PDF" and
    ...    "Tulosta / jaa PDF" share one PDF Hakemus_ROBOT_Esimerkki_Oy_Frontend-kehittäjä.pdf with the title
    ...    "Hakemus – ROBOT Esimerkki Oy" and the same text as in TC23-016.
    [Tags]    application-summary
    ${expected}=    Full Summary
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Summary From Details    ${FULL_COMPANY}
    ${pages}=    Share Pdf On iPhone    ${FULL_PDF}    Hakemus – ${FULL_COMPANY}
    Summary Pdf Should Be    ${pages}    ${expected}
    [Teardown]    Close Mobile Workspace

Summary of an application with only a company and a role has no empty sections
    [Documentation]    TC23-018. The application has only a company and a role (and the default stage
    ...    Kiinnostava). Expected result: the Chrome print sheet and the Mac Safari PDF
    ...    (Hakemus_ROBOT_Vähäinen_Oy_Harjoittelija.pdf) have the heading Harjoittelija, the subtitle with the
    ...    company only (no " · "), and only the section Perustiedot with Yritys, Tehtävä and Vaihe; there is
    ...    no Liitteet, Tapahtumahistoria, Muistiinpanot or Vanha hakemusteksti heading and no empty fact row.
    [Tags]    application-summary
    ${expected}=    Minimal Summary
    Open Print Device Workspace    chrome
    Print Summary From Details    ${MINIMAL_COMPANY}
    Wait For Chrome Print    print-applicationSummary
    Summary Print Sheet Should Be    ${expected}
    Get Element Count    ${SUMMARY_SHEET} >> css=.summary-events    ==    0
    Finish Chrome Print
    Close Mobile Workspace
    Open Print Device Workspace    mac-safari
    Print Summary From Details    ${MINIMAL_COMPANY}
    ${pages}=    Open Pdf On Mac Safari    Hakemus_ROBOT_Vähäinen_Oy_Harjoittelija.pdf    ${MIN_SMALL_PDF_BYTES}
    Summary Pdf Should Be    ${pages}    ${expected}
    Pdf Text Should Not Contain    ${pages}[0]    ·
    [Teardown]    Close Mobile Workspace

Summary lists a deleted CV and a deleted cover letter file as in the details
    [Documentation]    TC23-019. The application points to an app CV and two cover letter files, and the app's
    ...    lists of CVs and files no longer have the CV and one of the files (GET /api/cvs and /api/files are
    ...    mocked, as after a delete in another tab). Expected result: the details show "CV on poistettu" and
    ...    "Tiedosto on poistettu" and the download button of the remaining file; the summary's Liitteet has
    ...    "Hakukirjetiedosto robot-yhteenveto-kirje.txt" and the rows "Poistettu CV on poistettu" and
    ...    "Poistettu Tiedosto on poistettu" (class summary-missing), in the same words as the details.
    [Tags]    application-summary
    ${cvs}=    Api Request    GET    /api/cvs    user=A
    ${files}=    Api Request    GET    /api/files    user=A
    ${expr}=    Catenate
    ...    {'title': 'Testaaja', 'subtitle': $DELETED_COMPANY, 'headings': ['Perustiedot', 'Liitteet'],
    ...    'facts': [['Yritys', $DELETED_COMPANY], ['Tehtävä', 'Testaaja'], ['Vaihe', 'Kiinnostava']],
    ...    'attachments': [['Hakukirjetiedosto', $KEPT_LETTER], ['Poistettu', 'CV on poistettu'], ['Poistettu', 'Tiedosto on poistettu']],
    ...    'events': None, 'notes': None, 'applicationText': None, 'link': None}
    ${expected}=    Evaluate    ${expr}
    Open Print Device Workspace    chrome
    Mock Lists Without    ${cvs.json}    ${files.json}    ${DELETED_CV_ID}    ${DELETED_LETTER_ID}
    Open Application Details    ${DELETED_COMPANY}
    ${missing}=    Evaluate JavaScript    ${None}
    ...    () => Array.from(document.querySelectorAll('.detail-card .detail-missing')).map((e) => e.textContent.trim())
    Should Be Equal    ${missing}    ${{ ['CV on poistettu', 'Tiedosto on poistettu'] }}
    Get Element Count    css=.detail-document:text-is("Lataa hakukirje: ${KEPT_LETTER}")    ==    1
    Click    ${SUMMARY_BUTTON}
    Wait For Chrome Print    print-applicationSummary
    Summary Print Sheet Should Be    ${expected}
    Get Element Count    ${SUMMARY_SHEET} >> css=tr.summary-missing    ==    2
    Finish Chrome Print
    [Teardown]    Run Keywords    Clear Mocked Responses    AND    Close Mobile Workspace

Summary prints an old application text that does not fit in the notes as its own section
    [Documentation]    TC23-020. The application has short notes and an old application text (applicationText) of
    ...    about 9 000 characters, which together do not fit in the 8 000 character notes, so the app keeps the
    ...    text as it is. Expected result: the details show it under "Vanha hakemusteksti"; the Chrome print
    ...    sheet has the sections Perustiedot, Muistiinpanot (only the notes) and Vanha hakemusteksti (the whole
    ...    text), and the Mac Safari PDF Hakemus_ROBOT_Vanha_Teksti_Oy_Myyjä.pdf has the same sections in that
    ...    order with the beginning and the end of the text, over several pages, and no page ends with a
    ...    section heading.
    [Tags]    application-summary    old-application-text
    ${expected}=    Old Text Summary
    Open Print Device Workspace    chrome
    Open Application Details    ${OLD_TEXT_COMPANY}
    Get Text    css=.detail-card section.detail-copy:has(h3:text-is("Vanha hakemusteksti")) p    contains    Kappale 80.
    Click    ${SUMMARY_BUTTON}
    Wait For Chrome Print    print-applicationSummary
    Summary Print Sheet Should Be    ${expected}
    Finish Chrome Print
    Close Mobile Workspace
    Open Print Device Workspace    mac-safari
    Print Summary From Details    ${OLD_TEXT_COMPANY}
    ${pages}=    Open Pdf On Mac Safari    ${OLD_TEXT_PDF}
    ${count}=    Get Length    ${pages}
    Should Be True    ${count} >= 2    msg=The summary with the long old text has only ${count} page
    Summary Pdf Should Be    ${pages}    ${expected}
    [Teardown]    Close Mobile Workspace

Tulosta hakukirje still prints the HAKUKIRJE cover letter and not the summary
    [Documentation]    TC23-021. Expected result: "Tulosta hakukirje: <template>" in the details still renders the
    ...    cover letter sheet print-application with the title bar HAKUKIRJE and the letter of the template
    ...    (the placeholders filled in), and no summary sheet; its PDF is checked in TC23-012 and TC23-013.
    [Tags]    application-summary    letter-print
    Open Print Device Workspace    chrome
    Print Letter From Details    ${COMPANY}    ${TEMPLATE_NAME}
    Wait For Chrome Print    print-application
    Get Text    css=.print-document.print-application .letter-titlebar    ==    HAKUKIRJE
    Get Text    css=.print-document.print-application    contains    Haen tehtävää Testaaja yrityksessä ${COMPANY}.
    Get Element Count    ${SUMMARY_SHEET}    ==    0
    Finish Chrome Print
    [Teardown]    Close Mobile Workspace
