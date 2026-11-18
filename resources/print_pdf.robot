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
# The summary of an application with only a company and a role (TC23-018) has one short section, so pdfmake
# embeds only a few dozen glyphs; with the fonts it is still far over this (about 10 kB on 17 November 2026).
${MIN_SMALL_PDF_BYTES}    ${8192}
# Height of an A4 page; the CV print sheet is one page tall (PrintSheet.css .print-document.print-cv).
${A4_HEIGHT_MM}           ${297}
# ApplicationDetails.jsx: the application summary print (utils/applicationSummary.js).
${SUMMARY_BUTTON}         css=.detail-print-actions >> button:text-is("Tulosta yhteenveto / PDF")
${SUMMARY_SHEET}          css=.print-document.print-applicationSummary
# The section headings of the summary in their order; empty sections are left out.
@{SUMMARY_HEADINGS}       Perustiedot    Liitteet    Tapahtumahistoria    Muistiinpanot    Vanha hakemusteksti
# Reads the summary print sheet (textContent, so CSS text-transform and the screen layout do not matter).
${SUMMARY_SHEET_JS}       SEPARATOR=
...    () => { const sheet = document.querySelector('.print-document.print-applicationSummary'); if (!sheet) return null;
...    const t = (e) => (e ? e.textContent : null); const sections = Array.from(sheet.querySelectorAll('section.summary-section'));
...    const rows = (heading) => { const s = sections.find((x) => t(x.querySelector('h2')) === heading);
...    return s ? Array.from(s.querySelectorAll('tbody tr')).map((r) => Array.from(r.children).map(t)) : null };
...    const para = (heading) => { const s = sections.find((x) => t(x.querySelector('h2')) === heading); return s ? t(s.querySelector('p')) : null };
...    const link = sheet.querySelector('.summary-facts a');
...    return { titlebar: t(sheet.querySelector('.letter-titlebar')), title: t(sheet.querySelector('.summary-header h1')),
...    subtitle: t(sheet.querySelector('.summary-header p')), printed: t(sheet.querySelector('.summary-header small')),
...    headings: sections.map((s) => t(s.querySelector('h2'))), facts: rows('Perustiedot'), attachments: rows('Liitteet'),
...    eventHead: Array.from(sheet.querySelectorAll('.summary-events thead th')).map(t), events: rows('Tapahtumahistoria'),
...    notes: para('Muistiinpanot'), applicationText: para('Vanha hakemusteksti'),
...    link: link ? { href: link.getAttribute('href'), text: link.textContent } : null,
...    letter: sheet.querySelectorAll('.letter-content, .letter-sender, .letter-body').length } }
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
    [Documentation]    Returns what the recorders saw: prints (window.print calls of the app window),
    ...    printTitles (document.title at each of those calls), opened
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
    ...    () => { const c = window.__printCapture; c.prints = 0; c.printTitles = []; c.stubPrints = 0; c.opened = []; c.canShareCalls = []; c.shares = [] }

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

Open Application Details
    [Documentation]    Opens the details of the application from the list.
    [Arguments]    ${company}
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("${company}") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-card    visible

Print Summary From Details
    [Documentation]    Opens the details of the application and presses "Tulosta yhteenveto / PDF" (the
    ...    application summary, kind applicationSummary; until 17 November 2026 "Tulosta hakemus / PDF",
    ...    which printed the cover letter).
    [Arguments]    ${company}
    Open Application Details    ${company}
    Click    ${SUMMARY_BUTTON}

Print Letter From Details
    [Documentation]    Opens the details of the application and presses "Tulosta hakukirje: <template>".
    [Arguments]    ${company}    ${template_name}
    Open Application Details    ${company}
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
    ...    and more than min_bytes bytes (MIN_PDF_BYTES by default).
    [Arguments]    ${url}    ${min_bytes}=${MIN_PDF_BYTES}
    ${blob}=    Evaluate JavaScript    ${None}
    ...    async (url) => { const blob = await (await fetch(url)).blob(); const head = new TextDecoder().decode(await blob.slice(0, 5).arrayBuffer()); return { type: blob.type, size: blob.size, head } }
    ...    arg=${url}
    Should Be Equal    ${blob}[type]    application/pdf
    Should Be Equal    ${blob}[head]    %PDF-
    Should Be True    ${blob}[size] > ${min_bytes}    msg=The opened PDF has only ${blob}[size] bytes

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

Helsinki Short Date
    [Documentation]    Today in Finnish time as pp.kk.vvvv, the "Tulostettu" date of the summary. Built here,
    ...    independently of the app.
    ${date}=    Evaluate    datetime.datetime.now(zoneinfo.ZoneInfo('Europe/Helsinki')).strftime('%d.%m.%Y')
    ...    modules=datetime,zoneinfo
    RETURN    ${date}

Summary Sheet
    [Documentation]    The application summary print sheet as data (see SUMMARY_SHEET_JS), or None.
    ${sheet}=    Evaluate JavaScript    ${None}    ${SUMMARY_SHEET_JS}
    RETURN    ${sheet}

Summary Print Sheet Should Be
    [Documentation]    The summary print sheet (Chrome's print) has the title bar HAKEMUS, the role as the
    ...    heading, the given subtitle ("company · place", None when there is none), "Tulostettu <today>",
    ...    exactly the given section headings in that order and exactly the given rows: ${expected} has
    ...    headings, facts and attachments ([label, value] rows, None for a missing section), events ([date,
    ...    type, note], newest first), notes and applicationText (None when not printed) and link ({href,
    ...    text} or None). No part of the cover letter is in the sheet.
    [Arguments]    ${expected}
    ${sheet}=    Summary Sheet
    Should Not Be Equal    ${sheet}    ${None}    msg=No application summary print sheet is rendered
    ${date}=    Helsinki Short Date
    Should Be Equal    ${sheet}[titlebar]    HAKEMUS
    Should Be Equal    ${sheet}[title]    ${expected}[title]
    Should Be Equal    ${sheet}[subtitle]    ${expected}[subtitle]
    Should Be Equal    ${sheet}[printed]    Tulostettu ${date}
    Should Be Equal    ${sheet}[headings]    ${expected}[headings]
    FOR    ${key}    IN    facts    attachments    events    notes    applicationText    link
        Should Be Equal    ${sheet}[${key}]    ${expected}[${key}]    msg=Summary ${key}: ${sheet}[${key}]
    END
    IF    $expected['events']
        Should Be Equal    ${sheet}[eventHead]    ${{ ['Päivä', 'Tapahtuma', 'Lisätieto'] }}
    END
    Should Be Equal As Integers    ${sheet}[letter]    0    msg=The summary has parts of the cover letter
    Get Element Count    css=.print-document.print-application    ==    0

Summary Headings Should Not Break Alone
    [Documentation]    Laid out for print, every section heading of the summary sheet has break-after: avoid,
    ...    so the browser never leaves it alone at the bottom of a page.
    Emulate Media    media=print
    ${breaks}=    Evaluate JavaScript    ${None}
    ...    () => Array.from(document.querySelectorAll('.print-applicationSummary .summary-section h2')).map((h) => getComputedStyle(h).breakAfter)
    Emulate Media    media=screen
    Should Not Be Empty    ${breaks}
    FOR    ${value}    IN    @{breaks}
        Should Be Equal    ${value}    avoid
    END

Summary Pdf Should Be
    [Documentation]    The summary PDF reads, in this order: HAKEMUS, the role, the subtitle, "Tulostettu
    ...    <today>", then every expected section heading with its rows (the events after the column titles
    ...    PÄIVÄ, TAPAHTUMA, LISÄTIETO) and the notes. Of the old application text, which may run over
    ...    several pages, its first and last 60 characters are checked. Headings that are not expected, the
    ...    cover letter title bar HAKUKIRJE and the link scheme are not printed, and no page ends with a
    ...    section heading (the heading moves to the next page with its section).
    [Arguments]    ${pages}    ${expected}
    ${date}=    Helsinki Short Date
    ${parts}=    Evaluate
    ...    ['HAKEMUS', $expected['title']] + ([$expected['subtitle']] if $expected['subtitle'] else []) + ['Tulostettu ' + $date]
    FOR    ${heading}    IN    @{expected}[headings]
        Append To List    ${parts}    ${heading}
        IF    $heading == 'Perustiedot'
            ${rows}=    Evaluate    [cell for row in $expected['facts'] for cell in row]
        ELSE IF    $heading == 'Liitteet'
            ${rows}=    Evaluate    [cell for row in $expected['attachments'] for cell in row]
        ELSE IF    $heading == 'Tapahtumahistoria'
            ${rows}=    Evaluate    ['PÄIVÄ', 'TAPAHTUMA', 'LISÄTIETO'] + [cell for row in $expected['events'] for cell in row if cell]
        ELSE IF    $heading == 'Muistiinpanot'
            ${rows}=    Create List    ${expected}[notes]
        ELSE
            ${text}=    Set Variable    ${expected}[applicationText]
            ${rows}=    Create List    ${text}[:60]    ${text}[-60:]
        END
        Append To List    ${parts}    @{rows}
    END
    ${all}=    Evaluate    ' '.join($pages)
    Pdf Text Should Contain In Order    ${all}    @{parts}
    ${absent}=    Evaluate    [h for h in $SUMMARY_HEADINGS if h not in $expected['headings']]
    Pdf Text Should Not Contain    ${all}    https://    @{absent}
    # Case-sensitive: the attachment label "Hakukirjetiedosto" may be printed, the title bar must not.
    ${letter_bars}=    Pdf Text Count    ${all}    HAKUKIRJE
    Should Be Equal As Integers    ${letter_bars}    0    msg=The summary PDF has the cover letter title bar
    ${compact}=    Evaluate    [''.join(page.split()) for page in $pages[:-1]]
    FOR    ${index}    ${page}    IN ENUMERATE    @{compact}
        FOR    ${heading}    IN    @{expected}[headings]
            ${alone}=    Evaluate    $page.endswith(''.join($heading.split()))
            Should Not Be True    ${alone}    msg=Page ${index + 1} of the summary PDF ends with the heading ${heading}
        END
    END

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
