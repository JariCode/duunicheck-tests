*** Settings ***
Documentation     Public part of the UI (no login): landing page, login dialog, legal modals,
...               small-screen layout, PWA files and privacy checks of the loaded resources.
Resource          ../resources/common.robot
Suite Setup       Open Test Browser
Suite Teardown    Close Browser    ALL
Test Setup        Open New Session
Test Teardown     Close Session
Force Tags        ui    browser    public


*** Test Cases ***
Landing page loads with the expected title and call to action
    [Documentation]    TC01-001. Expected result: Landing page loads with the title "DuuniCheck – työnhaun seuranta"
    ...    (with an en dash) and the call to action.
    Open Landing Page
    ${title}=    Get Title
    Should Be Equal    ${title}    DuuniCheck – työnhaun seuranta
    Get Element Count    text=Avaa DuuniCheck    >=    1

Landing page has no console errors
    [Documentation]    TC01-002. Expected result: Landing page has no console errors.
    Open Landing Page
    ${log}=    Get Console Log    full=${False}
    ${errors}=    Evaluate    [m for m in $log if m['type'] == 'error']
    Should Be Empty    ${errors}    msg=Console errors: ${errors}

Login dialog opens, shows both tabs and closes with the close button
    [Documentation]    TC01-003. Expected result: Login dialog opens, shows both tabs and closes with the close button.
    Open Login Dialog
    Get Element Count    text=Kirjaudu    >=    1
    Get Element Count    text=Luo tili    >=    1
    Click    css=[aria-label="Sulje kirjautuminen"]
    Wait For Elements State    css=[aria-label="DuuniCheckin kirjautuminen ja tilin luonti"]    detached

Login dialog closes with the Escape key
    [Documentation]    TC01-004. Expected result: Login dialog closes with the Escape key (keyboard users
    ...    must be able to leave a modal dialog). An invitation link keeps the dialog open on Escape.
    [Tags]    accessibility
    Open Login Dialog
    Keyboard Key    press    Escape
    Wait For Elements State    css=[aria-label="DuuniCheckin kirjautuminen ja tilin luonti"]    detached

Sign-in with an unknown email is refused without revealing internals
    [Documentation]    TC01-005. Expected result: Sign-in with an unknown email is refused without revealing internals.
    Open Login Dialog
    Fill Text    css=input[name="identifier"]    robot-unknown-${{ int(__import__('time').time()) }}@example.com
    Click    css=.cl-formButtonPrimary
    Sleep    2s
    ${text}=    Get Text    css=body
    Should Not Contain    ${text}    sk_test
    Should Not Contain    ${text}    stack
    Get Element Count    text=Yleiskatsaus    ==    0

Sign-up requires accepting the terms
    [Documentation]    TC01-017. Expected result: the sign-up form refuses to continue until the terms
    ...    and the privacy policy are accepted, and tells the user why.
    [Tags]    browser
    Open Login Dialog
    Click    text=Luo tili
    Fill Text    xpath=//label[contains(., "Sähköpostiosoite")]//input    robot-consent-${{ int(__import__('time').time()) }}+clerk_test@example.com
    Fill Text    xpath=//label[contains(., "Salasana")]//input    Robot-${{ int(__import__('time').time()) }}-aA1!
    Click    css=.custom-signup-submit
    Get Text    css=.custom-signup-message    contains    Hyväksy käyttöehdot ja tietosuojaseloste

Login dialog closes when the backdrop is clicked
    [Documentation]    TC01-018. Expected result: a click outside the dialog closes it.
    [Tags]    browser
    Open Login Dialog
    Click With Options    css=.auth-dialog-backdrop    position_x=5    position_y=5
    Wait For Elements State    css=[aria-label="DuuniCheckin kirjautuminen ja tilin luonti"]    detached

Legal documents open as dialogs and close with Escape
    [Documentation]    TC01-007. Expected result: Legal documents open as dialogs and close with Escape.
    Open Landing Page
    FOR    ${link}    IN    Käyttöehdot    Tietosuojaseloste
        Click    css=footer >> text=${link}
        Wait For Elements State    css=#legal-modal-title    visible
        Get Element Count    ${DIALOG}    >=    1
        Keyboard Key    press    Escape
        Wait For Elements State    css=#legal-modal-title    detached
    END

Legal documents have real content
    [Documentation]    TC01-008. Expected result: Legal documents have real content.
    Open Landing Page
    Click    css=footer >> text=Tietosuojaseloste
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    Should Not Be Empty    ${text}
    Should Be True    len($text) > 300

Legal documents close with the close button and open from their own address
    [Documentation]    TC01-019. Expected result: The × button closes a legal document. The addresses
    ...    /kayttoehdot and /tietosuojaseloste open the document over the landing page, and closing
    ...    it returns the address to the landing page.
    Open Landing Page
    Click    css=footer >> text=Käyttöehdot
    Wait For Elements State    css=#legal-modal-title    visible
    Click    css=button.legal-modal-close
    Wait For Elements State    css=#legal-modal-title    detached
    FOR    ${page}    IN    kayttoehdot    tietosuojaseloste
        Go To    ${FRONTEND_URL}${page}
        Wait For Elements State    css=#legal-modal-title    visible
        Get Text    ${DIALOG}    contains    ${{ {'kayttoehdot': 'Käyttöehdot', 'tietosuojaseloste': 'Tietosuojaseloste'}[$page] }}
        Click    css=button.legal-modal-close
        Wait For Elements State    css=#legal-modal-title    detached
        ${path}=    Evaluate JavaScript    ${None}    () => window.location.pathname
        Should Not End With    ${path}    ${page}
        Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible
    END

Sign-up consent links open the legal documents without losing the form
    [Documentation]    TC01-020. Expected result: The terms and privacy links of the sign-up consent
    ...    open the documents as dialogs. Closing them returns to the form with the typed e-mail
    ...    kept, and following a link does not tick the consent box.
    Open Login Dialog
    Click    text=Luo tili
    Fill Text    xpath=//label[contains(., "Sähköpostiosoite")]//input    robot-links+clerk_test@example.com
    FOR    ${link}    IN    käyttöehdot    tietosuojaselosteen
        Click    css=.custom-signup-consent >> a:text-is("${link}")
        Wait For Elements State    css=#legal-modal-title    visible
        Click    css=button.legal-modal-close
        Wait For Elements State    css=#legal-modal-title    detached
    END
    Get Property    xpath=//label[contains(., "Sähköpostiosoite")]//input    value    ==    robot-links+clerk_test@example.com
    Get Checkbox State    css=.custom-signup-consent input    ==    unchecked

No horizontal scrolling on small screens
    [Documentation]    TC01-009. Expected result: No horizontal scrolling on small screens.
    ...    Each width is opened as an emulated phone (see Open Mobile Session).
    [Setup]    NONE
    FOR    ${width}    IN    @{MOBILE_WIDTHS}
        Open Mobile Session    ${width}
        Open Landing Page
        Page Should Not Scroll Horizontally
        Close Session
    END
    [Teardown]    Run Keyword And Ignore Error    Close Session

Login dialog fits on small screens
    [Documentation]    TC01-010. Expected result: Login dialog fits on small screens.
    ...    Each width is opened as an emulated phone (see Open Mobile Session).
    [Setup]    NONE
    FOR    ${width}    IN    320    360    390
        Open Mobile Session    ${width}
        Open Login Dialog
        Page Should Not Scroll Horizontally
        ${box}=    Get BoundingBox    css=[aria-label="DuuniCheckin kirjautuminen ja tilin luonti"]
        Should Be True    ${box}[width] <= ${width}
        Close Session
    END
    [Teardown]    Run Keyword And Ignore Error    Close Session

Web app manifest is valid and its icons exist with the declared sizes
    [Documentation]    TC01-011. Expected result: Web app manifest is valid and its icons exist with the declared sizes.
    ${response}=    Api Request    GET    ${FRONTEND_URL}manifest.webmanifest    absolute_url=${True}
    Status Should Be    ${response}    200
    ${manifest}=    Set Variable    ${response.json}
    Should Not Be Empty    ${manifest}[name]
    Should Not Be Empty    ${manifest}[icons]
    Should Be Equal    ${manifest}[display]    standalone
    FOR    ${icon}    IN    @{manifest}[icons]
        ${icon_response}=    Api Request    GET    ${FRONTEND_URL}${icon}[src]    absolute_url=${True}
        Status Should Be    ${icon_response}    200
        Should Contain    ${icon_response.header('Content-Type')}    image/
    END

Page declares viewport, theme colour, icons and social preview metadata
    [Documentation]    TC01-012. Expected result: Page declares viewport, theme colour, icons and social preview metadata.
    Open Landing Page
    Get Element Count    css=meta[name="viewport"]    ==    1
    Get Element Count    css=meta[name="theme-color"]    >=    1
    Get Element Count    css=link[rel="manifest"]    ==    1
    Get Element Count    css=meta[property="og:title"]    >=    1
    Get Element Count    css=meta[property="og:image"]    >=    1
    Get Element Count    css=meta[name="twitter:card"]    >=    1

Page does not load resources from third-party font or tracking hosts
    [Documentation]    TC01-013. Expected result: The page loads no fonts or scripts from third-party font or
    ...    tracking hosts. Fonts are self-hosted, so visitor IP addresses are not sent to Google (GDPR).
    [Tags]    privacy
    ${urls}=    Evaluate JavaScript    ${None}    () => performance.getEntriesByType('resource').map(r => r.name)
    ${bad}=    Evaluate    [u for u in $urls if any(h in u for h in ('fonts.googleapis.com','fonts.gstatic.com','google-analytics','googletagmanager','facebook.net','hotjar'))]
    Should Be Empty    ${bad}    msg=Third-party requests: ${bad}

Built JavaScript contains no secret keys
    [Documentation]    TC01-014. Expected result: Built JavaScript contains no secret keys.
    Open Landing Page
    ${scripts}=    Evaluate JavaScript    ${None}    () => Array.from(document.scripts).map(s => s.src).filter(Boolean)
    FOR    ${src}    IN    @{scripts}
        ${response}=    Api Request    GET    ${src}    absolute_url=${True}
        Should Not Contain    ${response.text}    sk_test_
        Should Not Contain    ${response.text}    sk_live_
        Should Not Contain    ${response.text}    whsec_
        Should Not Contain    ${response.text}    mongodb+srv
        Should Not Contain    ${response.text}    sk-proj-
    END

Unknown pages do not show a blank screen or an error trace
    [Documentation]    TC01-015. Expected result: Unknown pages do not show a blank screen or an error trace.
    Go To    ${FRONTEND_URL}this-page-does-not-exist-robot
    ${text}=    Get Text    css=body
    Should Not Contain    ${text}    Cannot GET
    Should Not Contain    ${text}    at Object.

Published .htaccess forbids framing by another site
    [Documentation]    TC01-016. Checks the content of the published frontend/public/.htaccess (Robot is never
    ...    run against the production site). Expected result: framing is forbidden with X-Frame-Options DENY
    ...    or a CSP with frame-ancestors 'none'.
    [Tags]    htaccess
    ${headers}=    Htaccess Headers
    ${csp}=    Evaluate    $headers.get('Content-Security-Policy', '') + $headers.get('Content-Security-Policy-Report-Only', '')
    ${frame_options}=    Evaluate    $headers.get('X-Frame-Options', '').strip().upper()
    Should Be True    $frame_options == 'DENY' or "frame-ancestors 'none'" in $csp
    ...    msg=The published .htaccess does not forbid framing (X-Frame-Options "${frame_options}")

Privacy policy says postings are not fetched from links and fonts are self-hosted
    [Documentation]    TC01-021. Expected result: The privacy policy does not mention Google Fonts, says that
    ...    the service does not fetch job postings from links (the user pastes the text) and that a link in the
    ...    pasted text is not opened, and says that the fonts are loaded from DuuniCheck's own server.
    [Tags]    privacy
    Open Landing Page
    Click    css=footer >> text=Tietosuojaseloste
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    Should Not Contain    ${text}    Google Fonts    ignore_case=${True}
    Should Not Contain    ${text}    fonts.googleapis    ignore_case=${True}
    Should Not Contain    ${text}    hakee linkistä
    Should Contain    ${text}    Palvelu ei hae työpaikkailmoituksia linkeistä, vaan liität ilmoituksen tekstin itse.
    Should Contain    ${text}    Jos tekstissä on linkki, se lähetetään tekstin mukana, mutta palvelu ei avaa sitä.
    Should Contain    ${text}    Ilmoituksen tekstiä ei tallenneta, eikä sitä lisätä keskusteluhistoriaan.
    Should Contain    ${text}    Käyttöliittymän fontit ladataan DuuniCheckin omalta palvelimelta

Terms of use mention the prefilled application made from a job posting
    [Documentation]    TC01-022. Expected result: The terms of use list prefilled applications made from job
    ...    postings among the features and say, in the AI assistant section, that the user checks the
    ...    prefilled data and the application is saved only after the user accepts it.
    Open Landing Page
    Click    css=footer >> text=Käyttöehdot
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    Should Contain    ${text}    luoda esitäytettyjä hakemuksia työpaikkailmoituksista
    Should Contain    ${text}    Avustaja voi tehdä liittämästäsi työpaikkailmoituksen tekstistä esitäytetyn hakemuksen.
    Should Contain    ${text}    Hakemus tallennetaan vasta, kun hyväksyt sen.

Fonts are loaded from the app's own origin
    [Documentation]    TC01-023. Expected result: Once the fonts of the landing page have loaded, at least one
    ...    font file has been downloaded and every font file comes from the frontend's own origin.
    [Tags]    privacy
    Open Landing Page
    ${fonts}=    Evaluate JavaScript    ${None}
    ...    async () => { await document.fonts.ready; return performance.getEntriesByType('resource').map(r => r.name).filter(u => /\\.(woff2?|ttf|otf)(\\?|$)/i.test(u)) }
    ${origin}=    Evaluate JavaScript    ${None}    () => window.location.origin
    Should Not Be Empty    ${fonts}    msg=No font files were loaded; the self-hosted fonts are missing
    ${foreign}=    Evaluate    [u for u in $fonts if not u.startswith($origin + '/')]
    Should Be Empty    ${foreign}    msg=Fonts loaded from another origin: ${foreign}

Page has a canonical link and the descriptive title in its metadata
    [Documentation]    TC01-024. Expected result: frontend/index.html of the application has the title "DuuniCheck –
    ...    työnhaun seuranta", the same og:title and a canonical link built from VITE_SITE_URL like og:url. The
    ...    finished build frontend/dist/index.html (read as it is, never built or changed by the test) has exactly
    ...    one canonical link, its address is an absolute https address ending in "/" and equal to og:url, no
    ...    placeholder is left and the title is the new one.
    [Tags]    build
    Require Config    APP_DIR
    ${source}=    Get File    ${APP_DIR}${/}frontend${/}index.html    encoding=UTF-8
    Should Contain    ${source}    <title>DuuniCheck – työnhaun seuranta</title>
    Should Contain    ${source}    <meta property="og:title" content="DuuniCheck – työnhaun seuranta" />
    Should Contain    ${source}    <link rel="canonical" href="%VITE_SITE_URL%" />
    Should Contain    ${source}    <meta property="og:url" content="%VITE_SITE_URL%" />
    ${dist}=    Normalize Path    ${APP_DIR}${/}frontend${/}dist${/}index.html
    File Should Exist    ${dist}    msg=No finished build at ${dist}. Build the frontend (npm run build) before the test run.
    ${built}=    Get File    ${dist}    encoding=UTF-8
    ${canonicals}=    Get Regexp Matches    ${built}    <link rel="canonical" href="([^"]*)" />    1
    Length Should Be    ${canonicals}    1    msg=The build must have exactly one canonical link
    ${og_urls}=    Get Regexp Matches    ${built}    <meta property="og:url" content="([^"]*)" />    1
    Length Should Be    ${og_urls}    1
    Should Match Regexp    ${canonicals}[0]    ^https://[^\\s"%<>]+/$    msg=Canonical link of the build is not an absolute https address: ${canonicals}[0]
    Should Be Equal    ${canonicals}[0]    ${og_urls}[0]
    Should Not Contain    ${built}    %VITE_SITE_URL%
    Should Contain    ${built}    <title>DuuniCheck – työnhaun seuranta</title>
    Should Contain    ${built}    <meta property="og:title" content="DuuniCheck – työnhaun seuranta" />

Terms of use describe the file import and deleting through the assistant
    [Documentation]    TC01-025. Expected result: the AI assistant section of the terms of use says which files can be
    ...    imported (Excel .xlsx, CSV, Word .docx, PDF, text), the 5 MB and 50 application limits, that macro and old
    ...    Excel files are not supported, that the file is not stored and only the chosen applications are saved
    ...    after approval, that "Kumoa tuonti" works until the page is reloaded, that the AI only turns a delete
    ...    request into search criteria and deletes nothing, and that a deletion cannot be undone.
    [Tags]    privacy
    Open Landing Page
    Click    css=footer >> text=Käyttöehdot
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    Should Contain    ${text}    Avustaja voi myös tuoda hakemuksia liittämästäsi Excel- (.xlsx), CSV-, Word- (.docx), PDF- tai tekstitiedostosta.
    Should Contain    ${text}    Tiedosto saa olla enintään 5 Mt, ja yhdellä kerralla voi tuoda enintään 50 hakemusta.
    Should Contain    ${text}    Makroja sisältäviä tai vanhan muodon Excel-tiedostoja ei tueta. Tiedostoa ei tallenneta.
    Should Contain    ${text}    Vain valitsemasi hakemukset tallennetaan, ja vasta kun hyväksyt ne.
    Should Contain    ${text}    Tiedostosta tuodut hakemukset voi poistaa Kumoa tuonti -painikkeella, kunnes sivu ladataan uudelleen.
    Should Contain    ${text}    Tekoäly muuntaa pyynnön hakuehdoiksi, eikä se näe hakemuksia eikä poista mitään.
    Should Contain    ${text}    Poistoa ei voi perua: poistetut hakemukset ja niiden keskustelut poistuvat pysyvästi.
    Should Contain    ${text}    9. marraskuuta 2026

Privacy policy describes what the file import and the delete search send to OpenAI
    [Documentation]    TC01-026. Expected result: the privacy policy says that imported data comes from the attached
    ...    file, that the file is read only for the request and never stored, that from a spreadsheet only the
    ...    column headers and at most five example rows go to OpenAI, that from Word, PDF and text files at most
    ...    16 000 characters go to OpenAI, that nothing is saved before approval, and that a delete request sends
    ...    only the message and today's date and deletes nothing before confirmation.
    [Tags]    privacy
    Open Landing Page
    Click    css=footer >> text=Tietosuojaseloste
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    ${text}=    Evaluate    $text.replace(chr(0xa0), ' ')
    Should Contain    ${text}    Jos tuot hakemuksia tiedostosta, tiedot saadaan liittämästäsi tiedostosta.
    Should Contain    ${text}    Kun tuot hakemuksia tiedostosta, tiedosto luetaan palvelimella vain pyynnön ajan, eikä sitä tallenneta minnekään.
    Should Contain    ${text}    Excel- ja CSV-taulukosta OpenAI:lle lähetetään vain sarakeotsikot ja enintään viisi esimerkkiriviä
    Should Contain    ${text}    Word-, PDF- ja tekstitiedostosta OpenAI:lle lähetetään tiedoston teksti (enintään 16 000 merkkiä)
    Should Contain    ${text}    eikä mitään tallenneta ennen kuin valitset ja hyväksyt tallennettavat hakemukset. Tuontia ei lisätä keskusteluhistoriaan.
    Should Contain    ${text}    Kun pyydät avustajaa etsimään poistettavia hakemuksia, OpenAI:lle lähetetään vain kirjoittamasi viesti ja tämän päivän päivämäärä, ei yhtään hakemuksen tietoa.
    Should Contain    ${text}    Mitään ei poisteta ennen kuin valitset poistettavat ja vahvistat poiston. Poistopyyntöä ei lisätä keskusteluhistoriaan.

Legal texts and the landing page name no job site
    [Documentation]    TC01-027. Expected result: the landing page, the sign-in dialog, the terms of use and the
    ...    privacy policy contain no web address other than the service's own (and the data protection
    ...    authority's), so no job site is named by its address (Text Should Name No Job Site).
    [Tags]    privacy
    Open Landing Page
    ${landing}=    Get Text    css=body
    Text Should Name No Job Site    ${landing}    The landing page
    FOR    ${link}    IN    Käyttöehdot    Tietosuojaseloste
        Click    css=footer >> text=${link}
        Wait For Elements State    css=#legal-modal-title    visible
        ${text}=    Get Text    ${DIALOG}
        Text Should Name No Job Site    ${text}    ${link}
        Keyboard Key    press    Escape
        Wait For Elements State    css=#legal-modal-title    detached
    END
