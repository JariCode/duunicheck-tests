*** Settings ***
Documentation     Keywords of the print tests (suite 23). The app chooses how a document is printed from the
...               device (frontend/src/utils/printTarget.js): the iOS home screen app hands a PDF made on the
...               device to the share sheet, Safari and the Dock app on a Mac open that PDF in a new tab, and
...               every other browser calls window.print(). Emulate Print Device (libraries/network_mocks.js)
...               makes the app see the device and records the print, open and share calls.
Resource          common.robot
Library           ../libraries/PdfText.py


*** Variables ***
${PDF_DIALOG}             css=section.confirm-dialog[aria-labelledby="print-pdf-dialog-title"]
${PDF_DIALOG_TITLE}       css=#print-pdf-dialog-title
${PDF_DIALOG_TEXT}        css=#print-pdf-dialog-description
${SHARE_PDF_BUTTON}       ${PDF_DIALOG} >> button:text-is("Tulosta / jaa PDF")
${OPEN_PDF_BUTTON}        ${PDF_DIALOG} >> button:text-is("Avaa PDF")
${PDF_BUSY_TITLE}         Luodaan PDF:ää…
${PDF_READY_TITLE}        PDF on valmis
# PrintPdfDialog.jsx: the help shown when the iOS app cannot share the PDF.
${SAFARI_HELP}            Avaa duunicheck.jaricode.fi Safarissa, niin voit tulostaa tai tallentaa PDF:n sieltä.
# A real PDF of the app embeds the DM Sans fonts, so it is far bigger than this.
${MIN_PDF_BYTES}          ${10240}
# Height of an A4 page; the CV print sheet is one page tall (PrintSheet.css .print-document.print-cv).
${A4_HEIGHT_MM}           ${297}
# Reads a Blob or File as base64 in the page (the argument is a blob URL or null for the shared file).
${READ_PDF_JS}            SEPARATOR=
...    async (url) => { const blob = url ? await (await fetch(url)).blob() : window.__lastSharedFile;
...    if (!blob) return ''; const bytes = new Uint8Array(await blob.arrayBuffer()); let s = '';
...    for (let i = 0; i < bytes.length; i += 32768) s += String.fromCharCode(...bytes.subarray(i, i + 32768));
...    return btoa(s) }


*** Keywords ***
Open Print Device Workspace
    [Documentation]    Opens player A's workspace in a new session in which the app sees the given device:
    ...    iphone (the iOS home screen app), mac-safari (Safari or the Dock app on a Mac) or chrome (the
    ...    browser as it is). In every case window.print, window.open, navigator.share and navigator.canShare
    ...    are recorders (see Print Capture). With mobile=${True} the session emulates a phone (touch, no
    ...    classic scrollbar). The sign-in is copied from player A's session like in Open Mobile Workspace,
    ...    and the session is closed with Close Mobile Workspace.
    [Arguments]    ${device}    ${width}=1280    ${height}=900    ${mobile}=${False}
    ${state}=    Save Storage State
    ${context}=    New Context    viewport={'width': ${width}, 'height': ${height}}    locale=fi-FI
    ...    isMobile=${mobile}    hasTouch=${mobile}    acceptDownloads=${True}    storageState=${state}
    Remove File    ${state}
    Set Test Variable    ${MOBILE_CONTEXT}    ${context}
    New Page
    Emulate Print Device    ${device}
    Go To    ${FRONTEND_URL}
    Wait For Workspace
    ${capture}=    Print Capture
    Should Be Equal    ${capture}[device]    ${device}    msg=The print device emulation did not run before the app

Print Capture
    [Documentation]    Returns what the recorders saw: prints (window.print calls of the app window), opened
    ...    ({url, target} of each window.open call), stubPrints (print calls of the stand-in tab),
    ...    canShareCalls and shares (name, type, size, title and count of the shared files).
    ${capture}=    Evaluate JavaScript    ${None}    () => window.__printCapture
    RETURN    ${capture}

Set Print Capture
    [Documentation]    Sets how a recorder answers: canShareResult (true/false), shareResult (resolve, abort,
    ...    error) or openResult (window, null).
    [Arguments]    ${field}    ${value}
    Evaluate JavaScript    ${None}    (args) => { window.__printCapture[args.field] = args.value }
    ...    arg=${{ {'field': $field, 'value': $value} }}

Clear Print Capture
    [Documentation]    Forgets the recorded calls (the answers set with Set Print Capture are kept).
    Evaluate JavaScript    ${None}
    ...    () => { const c = window.__printCapture; c.prints = 0; c.stubPrints = 0; c.opened = []; c.canShareCalls = []; c.shares = [] }

Prepare Print Data
    [Documentation]    Stores user A's CV, letter template and an application that uses both, and reloads
    ...    the workspace. The CV is filled like a real one (photo, every section, links), so the PDF has the
    ...    size of a real document: pdfmake embeds only the glyphs used, and a CV with a few words gives a
    ...    PDF under 10 kB. Every name, text and address is made up.
    [Arguments]    ${cv_name}    ${full_name}    ${template_name}    ${company}
    ${photo}=    Png Data Uri    64    80
    ${cv}=    Create Cv As    A    name=${cv_name}    fullName=${full_name}    title=Testiammattilainen
    ...    photo=${photo}    email=vaino.testinen@example.com    phone=+358 00 000 0000
    ...    summary=Ohjelmistotestaaja, joka kirjoittaa automaattisia testejä ja etsii virheet ennen käyttäjiä. Työskentelen mielelläni kehittäjien kanssa ja selitän löydökset selkeästi.
    ...    skills=Robot Framework\nPlaywright\nPython\nJavaScript\nREST-rajapinnat\nGit
    ...    languages=Suomi, äidinkieli\nEnglanti, sujuva\nRuotsi, tyydyttävä
    ...    experience=Testaaja, Esimerkki Oy, 2022–2026\nTestiautomaation rakentaminen ja ylläpito.\nJulkaisujen regressiotestaus.\n\nHarjoittelija, Malliyritys Oy, 2021\nManuaalinen testaus ja virheraporttien kirjoittaminen.
    ...    education=Tradenomi, tietojenkäsittely\nYlioppilas
    ...    certificates=ISTQB Foundation Level\nTestiautomaation perusteet
    ...    courses=Saavutettavuuden perusteet\nTietoturvan perusteet
    ...    hobbies=Suunnistus, shakki ja valokuvaus.
    ...    github=https://github.com/example    portfolio=https://example.com/portfolio
    ${template}=    Create Template As    A    name=${template_name}
    ...    body=Hei,\n\nHaen tehtävää {{tehtävä}} yrityksessä {{yritys}}. Olen työskennellyt testaajana neljä vuotta ja rakentanut testiautomaatiota verkkosovelluksille.\n\n# Miksi juuri minä\nKirjoitan testejä, jotka löytävät virheet ajoissa, ja raportoin ne niin, että kehittäjät voivat korjata ne nopeasti.\n\nKerron mielelläni lisää haastattelussa.\n\nYstävällisin terveisin,\n${full_name}
    Create Application As    A    company=${company}    role=Testaaja    place=Esimerkkilä    cvId=${cv}[id]
    ...    templateId=${template}[id]
    Set Suite Variable    ${PRINT_CV}    ${cv}
    Reload
    Wait For Workspace

Print Cv From Materials
    [Documentation]    Presses "Tulosta / tallenna PDF" of the CV card in CV & pohjat.
    [Arguments]    ${cv_name}
    Go To Section    CV & pohjat
    Click    css=.material-card:has-text("${cv_name}") >> button:text-is("Tulosta / tallenna PDF")

Print Application From Details
    [Documentation]    Opens the details of the application and presses "Tulosta hakemus / PDF".
    [Arguments]    ${company}
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("${company}") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-card    visible
    Click    css=.detail-print-actions >> button:text-is("Tulosta hakemus / PDF")

Print Letter From Details
    [Documentation]    Opens the details of the application and presses "Tulosta hakukirje: <template>".
    [Arguments]    ${company}    ${template_name}
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("${company}") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-card    visible
    Click    css=.detail-document:has-text("Tulosta hakukirje: ${template_name}")

Print Template From Materials
    [Documentation]    Presses "Tulosta / tallenna PDF" of the template card in CV & pohjat.
    [Arguments]    ${template_name}
    Go To Section    CV & pohjat
    Click    css=.template-card:has-text("${template_name}") >> button:text-is("Tulosta / tallenna PDF")

Pdf Dialog Should Become Ready
    [Documentation]    The PDF dialog opens, first shows that the PDF is being made (unless it was already
    ...    made) and then "PDF on valmis" with the file name and the given button.
    [Arguments]    ${file_name}    ${button}
    Wait For Elements State    ${PDF_DIALOG}    visible    timeout=10s
    Get Text    ${PDF_DIALOG} >> .confirm-kicker    ==    TULOSTA / TALLENNA PDF
    ${first}=    Get Text    ${PDF_DIALOG_TITLE}
    Should Contain    ${{ [$PDF_BUSY_TITLE, $PDF_READY_TITLE] }}    ${first}
    ...    msg=The PDF dialog opened with the title "${first}"
    Get Text    ${PDF_DIALOG_TITLE}    ==    ${PDF_READY_TITLE}    message=The PDF was not made: {value}
    Get Attribute    ${PDF_DIALOG}    aria-busy    ==    false
    Get Text    ${PDF_DIALOG_TEXT}    contains    ${file_name}
    Wait For Elements State    ${button}    visible

Shared File Should Be
    [Documentation]    navigator.share got exactly one call with one PDF file of the given name.
    [Arguments]    ${file_name}
    Wait Until Keyword Succeeds    5s    200ms    Share Count Should Be    1
    ${capture}=    Print Capture
    ${shared}=    Set Variable    ${capture}[shares][0]
    Should Be Equal    ${shared}[name]    ${file_name}
    Should Be Equal    ${shared}[type]    application/pdf
    Should Be Equal As Integers    ${shared}[count]    1
    Should Be True    ${shared}[size] > ${MIN_PDF_BYTES}    msg=The shared PDF has only ${shared}[size] bytes
    RETURN    ${shared}

Share Count Should Be
    [Arguments]    ${count}
    ${capture}=    Print Capture
    Length Should Be    ${capture}[shares]    ${count}

App Window Should Not Print
    [Documentation]    window.print() of the app window was not called, also not shortly after.
    Sleep    1s
    ${capture}=    Print Capture
    Should Be Equal As Integers    ${capture}[prints]    0    msg=The app called window.print()

Blob Should Be A Pdf
    [Documentation]    The blob URL the app opened still gives the PDF: type application/pdf, the PDF header
    ...    and more than MIN_PDF_BYTES bytes.
    [Arguments]    ${url}
    ${blob}=    Evaluate JavaScript    ${None}
    ...    async (url) => { const blob = await (await fetch(url)).blob(); const head = new TextDecoder().decode(await blob.slice(0, 5).arrayBuffer()); return { type: blob.type, size: blob.size, head } }
    ...    arg=${url}
    Should Be Equal    ${blob}[type]    application/pdf
    Should Be Equal    ${blob}[head]    %PDF-
    Should Be True    ${blob}[size] > ${MIN_PDF_BYTES}    msg=The opened PDF has only ${blob}[size] bytes

Opened Pdf Pages
    [Documentation]    The text of every page of the PDF behind the blob URL the app opened (Mac Safari).
    [Arguments]    ${url}
    ${data}=    Evaluate JavaScript    ${None}    ${READ_PDF_JS}    arg=${url}
    Should Not Be Empty    ${data}    msg=The opened PDF could not be read
    ${pages}=    Pdf Page Texts    ${data}
    RETURN    ${pages}

Shared Pdf Pages
    [Documentation]    The text of every page of the PDF file last handed to navigator.share (iPhone).
    ${data}=    Evaluate JavaScript    ${None}    ${READ_PDF_JS}    arg=${None}
    Should Not Be Empty    ${data}    msg=No shared PDF file was recorded
    ${pages}=    Pdf Page Texts    ${data}
    RETURN    ${pages}

Finnish Long Date
    [Documentation]    Today as the app writes it in a letter (fi-FI, day numeric, month long), e.g.
    ...    "17. marraskuuta 2026". Built here from the month names, independently of the app.
    ${date}=    Evaluate
    ...    (lambda d: f"{d.day}. {['tammikuuta', 'helmikuuta', 'maaliskuuta', 'huhtikuuta', 'toukokuuta', 'kesäkuuta', 'heinäkuuta', 'elokuuta', 'syyskuuta', 'lokakuuta', 'marraskuuta', 'joulukuuta'][d.month - 1]} {d.year}")(datetime.date.today())
    ...    modules=datetime
    RETURN    ${date}

Cv Pdf Should Have The New Layout
    [Documentation]    The CV PDF has the given number of pages. The first page starts with the name, the
    ...    title, the contact line "email · phone" and then the full-width section "Profiili" with the
    ...    summary, before the columns (IT-taidot). There is no contact box: no "Yhteystiedot",
    ...    "Sähköposti" or "Puhelin" label anywhere, and the summary is printed only once.
    [Arguments]    ${pages}    ${cv}    ${page_count}
    Length Should Be    ${pages}    ${page_count}    msg=The CV PDF has ${{ len($pages) }} pages, expected ${page_count}
    Pdf Text Should Contain In Order    ${pages}[0]    ${cv}[fullName]    ${cv}[title]
    ...    ${cv}[email] · ${cv}[phone]    Profiili    ${cv}[summary]    IT-taidot
    ${all}=    Evaluate    ' '.join($pages)
    Pdf Text Should Not Contain    ${all}    Yhteystiedot    Sähköposti    Puhelin
    ${count}=    Pdf Text Count    ${all}    ${cv}[summary]
    Should Be Equal As Integers    ${count}    1    msg=The summary is printed ${count} times

Letter Pdf Should Have The Date In The Header
    [Documentation]    The cover letter PDF (HAKUKIRJE layout) has the title bar, the name, the contact lines
    ...    and today's date in the header, before the letter. There is no recipient box: no "Vastaanottaja"
    ...    or "Päiväys" label. ${before} are the texts expected between the name and the date, ${after}
    ...    the texts expected after the date.
    [Arguments]    ${pages}    ${name}    ${before}    ${after}
    ${date}=    Finnish Long Date
    Pdf Text Should Contain In Order    ${pages}[0]    HAKUKIRJE    ${name}    @{before}    ${date}    @{after}
    ${all}=    Evaluate    ' '.join($pages)
    Pdf Text Should Not Contain    ${all}    Vastaanottaja    Päiväys
    ${count}=    Pdf Text Count    ${all}    ${date}
    Should Be Equal As Integers    ${count}    1    msg=The date is printed ${count} times

Print Sheet Layout
    [Documentation]    Lays the page out for print (Emulate Media) and measures the CV print sheet: the gap
    ...    scale the app set (--cv-gap of the style attribute), where the columns end below the top of the
    ...    sheet (mm), the bottom margin of the profile section (mm, 4mm * gap in PrintSheet.css) and the
    ...    font sizes of the name and the body text. The screen layout is restored afterwards.
    Emulate Media    media=print
    ${layout}=    Evaluate JavaScript    ${None}
    ...    () => { const sheet = document.querySelector('.print-document.print-cv'); const mm = (px) => px * 25.4 / 96; const top = sheet.getBoundingClientRect().top; const profile = sheet.querySelector('.cv-print-profile'); return { gap: sheet.style.getPropertyValue('--cv-gap'), end: mm(sheet.querySelector('.cv-print-columns').getBoundingClientRect().bottom - top), profileMargin: profile ? mm(parseFloat(getComputedStyle(profile).marginBottom)) : null, nameSize: getComputedStyle(sheet.querySelector('h1')).fontSize, textSize: getComputedStyle(sheet).fontSize } }
    Emulate Media    media=screen
    RETURN    ${layout}

Cv Print Sheet Should Have The New Layout
    [Documentation]    The CV print sheet in the DOM: the header (.cv-print-hero) has the name, the title,
    ...    the contact line "email · phone" (.cv-print-contact) and the photo, but not the summary; the
    ...    section "Profiili" (.cv-print-profile) with the summary comes right after the header; there is no
    ...    contact box (no "Yhteystiedot" heading, no .cv-print-summary).
    [Arguments]    ${cv}
    ${sheet}=    Set Variable    css=.print-document.print-cv
    Get Text    ${sheet} >> css=.cv-print-hero h1    ==    ${cv}[fullName]
    Get Text    ${sheet} >> css=.cv-print-hero .cv-print-title    ==    ${cv}[title]
    Get Text    ${sheet} >> css=.cv-print-hero .cv-print-contact    ==    ${cv}[email] · ${cv}[phone]
    Get Element Count    ${sheet} >> css=.cv-print-hero img.cv-print-photo    ==    1
    Get Text    ${sheet} >> css=.cv-print-hero    not contains    ${cv}[summary]
    Get Element Count    ${sheet} >> css=.cv-print-hero + section.cv-print-profile    ==    1
    Get Text    ${sheet} >> css=.cv-print-profile h2    ==    Profiili
    Get Text    ${sheet} >> css=.cv-print-profile p    ==    ${cv}[summary]
    Get Element Count    ${sheet} >> css=.cv-print-summary    ==    0
    Get Element Count    ${sheet} >> css=h2:text-is("Yhteystiedot")    ==    0
    Get Element Count    ${sheet} >> css=section.cv-print-contact    ==    0

Letter Print Sheet Should Have The Date In The Header
    [Documentation]    The HAKUKIRJE print sheet in the DOM: no recipient box (.letter-address-row,
    ...    .letter-recipient, the labels Vastaanottaja and Päiväys), and the last item of the header's contact
    ...    list (.letter-sender li.letter-date) holds today's date as a time element after the given contact
    ...    lines. ${missing} are texts that only the recipient box had.
    [Arguments]    ${contacts}    @{missing}
    ${sheet}=    Set Variable    css=.print-document.print-application
    Get Element Count    ${sheet} >> css=.letter-address-row    ==    0
    Get Element Count    ${sheet} >> css=.letter-recipient    ==    0
    ${text}=    Get Text    ${sheet}
    ${lower}=    Convert To Lower Case    ${text}
    Should Not Contain    ${lower}    vastaanottaja
    Should Not Contain    ${lower}    päiväys
    FOR    ${value}    IN    @{missing}
        Should Not Contain    ${text}    ${value}
    END
    ${date}=    Finnish Long Date
    Get Text    ${sheet} >> css=.letter-sender li.letter-date time    ==    ${date}
    Get Element Count    ${sheet} >> css=.letter-sender ul > li:last-child.letter-date    ==    1
    ${items}=    Get Elements    ${sheet} >> css=.letter-sender ul > li
    ${texts}=    Create List
    FOR    ${item}    IN    @{items}
        ${value}=    Get Text    ${item}
        Append To List    ${texts}    ${value}
    END
    ${expected}=    Evaluate    list($contacts) + [$date]
    Should Be Equal    ${texts}    ${expected}

App Cv Gap Scale
    [Documentation]    The gap scale the app's printPdf.js (cvGapScale, used by both the print and the PDF)
    ...    gives the CV. The module is imported from the address the app itself loaded it from.
    [Arguments]    ${cv}
    ${scale}=    Evaluate JavaScript    ${None}
    ...    async (cv) => { const entry = performance.getEntriesByType('resource').map((e) => e.name).find((name) => name.includes('/utils/printPdf.js')); if (!entry) return 'printPdf.js was not loaded'; return (await import(entry)).cvGapScale(cv) }
    ...    arg=${cv}
    RETURN    ${scale}

Metric Font Sizes
    [Documentation]    Returns the computed font sizes of the label row (div), the number (b) and the note
    ...    (small) of every dashboard metric card, one [div, b, small] list per card.
    ${sizes}=    Evaluate JavaScript    ${None}
    ...    () => Array.from(document.querySelectorAll('.metrics .metric')).map((card) => ['div', 'b', 'small'].map((tag) => getComputedStyle(card.querySelector(':scope > ' + tag)).fontSize))
    RETURN    ${sizes}

Metric Font Sizes Should Be
    [Documentation]    All five metric cards have the given div, b and small font sizes.
    [Arguments]    ${div}    ${b}    ${small}    ${where}
    Get Element Count    css=.metrics .metric    ==    5
    ${sizes}=    Metric Font Sizes
    ${expected}=    Evaluate    [[$div, $b, $small]] * 5
    Should Be Equal    ${sizes}    ${expected}    msg=${where}: metric font sizes (div, b, small) per card: ${sizes}

Metric Transform
    [Arguments]    ${index}
    ${transform}=    Evaluate JavaScript    ${None}
    ...    (index) => getComputedStyle(document.querySelectorAll('.metrics .metric')[index]).transform
    ...    arg=${index}
    RETURN    ${transform}
