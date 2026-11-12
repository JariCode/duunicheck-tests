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


*** Keywords ***
Prepare Print Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    Prepare Print Data    ${CV_NAME}    ${FULL_NAME}    ${TEMPLATE_NAME}    ${COMPANY}

Share Pdf On iPhone
    [Documentation]    In the iPhone session: the PDF dialog gets ready, "Tulosta / jaa PDF" hands exactly
    ...    one PDF with the right name and title to the share sheet, the dialog closes and the app window
    ...    never prints.
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

Open Pdf On Mac Safari
    [Documentation]    In the Mac Safari session: the PDF dialog gets ready, "Avaa PDF" opens the PDF's blob
    ...    URL in a new tab (_blank), the dialog closes and the app window never prints.
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
