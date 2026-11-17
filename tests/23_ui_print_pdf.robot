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
# printPdf.js pdfFileName: CV_<full name>, Hakemus_<company>, spaces as underscores.
${CV_PDF}           CV_Väinö_Testinen.pdf
${APPLICATION_PDF}    Hakemus_ROBOT_Tulostin_Oy.pdf
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
    Prepare Print Data    ${CV_NAME}    ${FULL_NAME}    ${TEMPLATE_NAME}    ${COMPANY}

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
    [Arguments]    ${file_name}
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
    Blob Should Be A Pdf    ${opened}[url]
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
iPhone home screen app shares the CV and the application as PDF files
    [Documentation]    TC23-001. The app runs as an iPhone home screen app (iPhone user agent,
    ...    navigator.standalone = true, phone session 390 px). Expected result: "Tulosta / tallenna PDF" of the
    ...    CV card and "Tulosta hakemus / PDF" in the application details open the PDF dialog, which goes from
    ...    "Luodaan PDF:ää…" to "PDF on valmis" and shows "Tulosta / jaa PDF". The button hands one file to
    ...    navigator.share: CV_Väinö_Testinen.pdf and Hakemus_ROBOT_Tulostin_Oy.pdf, type application/pdf,
    ...    over 10 kB, after navigator.canShare has accepted the same file. The dialog then closes, no print
    ...    sheet is rendered and window.print() is never called.
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Cv From Materials    ${CV_NAME}
    Share Pdf On iPhone    ${CV_PDF}    CV – ${FULL_NAME}
    Clear Print Capture
    Print Application From Details    ${COMPANY}
    Share Pdf On iPhone    ${APPLICATION_PDF}    Hakemus – ${COMPANY}
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

Mac Safari opens the CV and the application PDF in a new tab
    [Documentation]    TC23-004. The app runs as Safari on a Mac (Mac Safari user agent, no
    ...    navigator.userAgentData, maxTouchPoints 0). Expected result: printing the CV and the application
    ...    opens the PDF dialog with "Avaa PDF" (not the share button). "Avaa PDF" calls window.open with the
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
    Print Application From Details    ${COMPANY}
    Open Pdf On Mac Safari    ${APPLICATION_PDF}
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
    ...    the CV and the application renders the print sheet and calls window.print() exactly once each; the
    ...    PDF dialog never opens, nothing is shared and no new tab is opened.
    Open Print Device Workspace    chrome
    Print Cv From Materials    ${CV_NAME}
    Print In Chrome    print-cv    ${FULL_NAME}
    Clear Print Capture
    Print Application From Details    ${COMPANY}
    Print In Chrome    print-application    ${COMPANY}
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
    [Documentation]    TC23-011. The HAKUKIRJE print sheet in Chrome from "Tulosta hakukirje" and "Tulosta
    ...    hakemus / PDF" in the details and from the template card in CV & pohjat. Expected result: none of
    ...    them has the recipient box (.letter-address-row, .letter-recipient, the labels Vastaanottaja and
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
    Click    css=.detail-print-actions >> button:text-is("Tulosta hakemus / PDF")
    Wait For Chrome Print    print-application
    Letter Print Sheet Should Have The Date In The Header    ${contacts}    Esimerkkilä
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
    [Documentation]    TC23-012. Expected result: the PDF of "Tulosta hakemus / PDF" reads HAKUKIRJE, the name,
    ...    the email, the phone and today's date, then HAETTAVA TEHTÄVÄ and the role; it has no Vastaanottaja
    ...    or Päiväys label, the date is printed once, the place (Esimerkkilä) is not printed and the company
    ...    is named only once (in the letter). The PDF of the template printed from CV & pohjat has the
    ...    template's name, email, phone and the date in the header, before the letter.
    [Tags]    letter-print
    Open Print Device Workspace    mac-safari
    Print Application From Details    ${COMPANY}
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
    [Documentation]    TC23-013. Expected result: as in TC23-012 for the shared PDFs of "Tulosta hakemus / PDF"
    ...    (Hakemus_ROBOT_Tulostin_Oy.pdf) and of the template printed from CV & pohjat
    ...    (Hakemus_Matti_Meikäläinen.pdf, title "Hakemus"): the date is in the header after the contact lines,
    ...    and there is no recipient box.
    [Tags]    letter-print
    Open Print Device Workspace    iphone    390    844    mobile=${True}
    Print Application From Details    ${COMPANY}
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
