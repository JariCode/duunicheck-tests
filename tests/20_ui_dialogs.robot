*** Settings ***
Documentation     Keyboard and layering behaviour of every dialog (frontend/src/utils/useDialog.js): the dialog
...               closes with Escape (an inner layer first), keeps Tab and Shift+Tab inside, returns the focus to the
...               button that opened it, and opens above the top bar. Checked for the application details, the add and
...               edit application forms, the CV and template editors, the delete confirmations, the legal documents,
...               the sign-in dialog and the mobile side menu. The topmost element at a point is read with
...               document.elementFromPoint, so a dialog hidden under the top bar is found even when it is in the DOM.
Resource          ../resources/common.robot
Suite Setup       Prepare Dialog Suite
Suite Teardown    Finish Dialog Suite
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    dialogs    accessibility


*** Variables ***
${COMPANY}          ROBOT Ikkuna Oy
${DETAILS}          css=section.detail-card[role="dialog"]
${APP_FORM}         css=form.extended-form[role="dialog"]
${CV_EDITOR}        css=form.cv-editor[role="dialog"]
${TEMPLATE_EDITOR}  css=form.template-editor[role="dialog"]
${CONFIRM}          css=section.confirm-dialog[role="alertdialog"]
${MENU}             css=aside.sidebar.menu-open
${MENU_TOGGLE}      css=button.mobile-nav-toggle
@{THEMES}           default    dark    light


*** Keywords ***
Prepare Dialog Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    &{event}=    Create Dictionary    id=1    type=Lähetetty    date=2026-11-02    note=Ikkunatestin merkintä
    Create Application As    A    company=${COMPANY}    role=Ikkunatestaaja    status=Lähetetty    events=${{ [$event] }}
    Create Cv As    A    name=ROBOT Ikkuna CV
    Create Template As    A    name=ROBOT Ikkuna pohja
    Upload Text File As    A    cv    ${PREFIX}-ikkuna.txt
    Reload
    Wait For Workspace

Finish Dialog Suite
    Run Keyword And Ignore Error    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'default'} }}
    Run Keyword And Ignore Error    Delete All Data    A
    Run Keyword And Ignore Error    Close Browser    ALL

Mark Opener
    [Documentation]    Marks the button that opens a dialog, so the focus can be compared with it after closing.
    [Arguments]    ${opener}
    Evaluate JavaScript    css=[data-robot-opener]    (els) => els.forEach((e) => e.removeAttribute('data-robot-opener'))    all_elements=${True}
    Evaluate JavaScript    ${opener}    (el) => el.setAttribute('data-robot-opener', '1')

Open Dialog With
    [Documentation]    Marks and clicks the opener and waits for the dialog.
    [Arguments]    ${opener}    ${dialog}
    Mark Opener    ${opener}
    Click    ${opener}
    Wait For Elements State    ${dialog}    visible

Focus Should Be Inside
    [Arguments]    ${dialog}    ${step}=after opening
    ${inside}=    Evaluate JavaScript    ${dialog}    (d) => d.contains(document.activeElement)
    ${where}=    Evaluate JavaScript    ${None}    () => { const e = document.activeElement; return e ? e.tagName + '.' + e.className + ' ' + (e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 40) : 'none' }
    Should Be True    ${inside}    msg=The focus left the dialog ${step}: ${where}

Tab Should Stay Inside
    [Documentation]    Presses Tab and then Shift+Tab more times than the dialog has focusable elements; the focus must
    ...    stay inside the dialog after every press.
    [Arguments]    ${dialog}
    ${count}=    Evaluate JavaScript    ${dialog}
    ...    (d) => Array.from(d.querySelectorAll('a[href], button:not([disabled]), input:not([disabled]):not([type="hidden"]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])')).filter((e) => e.getClientRects().length > 0).length
    Should Be True    ${count} > 0    msg=The dialog has no focusable element
    ${presses}=    Evaluate    min(${count} + 2, 40)
    FOR    ${key}    IN    Tab    Shift+Tab
        FOR    ${index}    IN RANGE    ${presses}
            Keyboard Key    press    ${key}
            Focus Should Be Inside    ${dialog}    after ${index + 1} x ${key}
        END
    END

Focus Should Be On Opener
    ${back}=    Evaluate JavaScript    ${None}    () => document.activeElement?.getAttribute('data-robot-opener') === '1'
    ${where}=    Evaluate JavaScript    ${None}    () => { const e = document.activeElement; return e ? e.tagName + ' ' + (e.textContent || '').trim().slice(0, 40) : 'none' }
    Should Be True    ${back}    msg=The focus did not return to the button that opened the dialog (now on ${where})

Escape Should Close And Return Focus
    [Arguments]    ${dialog}
    Keyboard Key    press    Escape
    Wait For Elements State    ${dialog}    detached    timeout=5s
    Focus Should Be On Opener

Dialog Keyboard Check
    [Documentation]    Opens the dialog, checks that the focus moved inside, that Tab and Shift+Tab stay inside, that
    ...    Escape closes it and that the focus returns to the opener.
    [Arguments]    ${opener}    ${dialog}
    Open Dialog With    ${opener}    ${dialog}
    Focus Should Be Inside    ${dialog}
    Tab Should Stay Inside    ${dialog}
    Escape Should Close And Return Focus    ${dialog}

Element Should Be On Top
    [Documentation]    The element is the topmost element at its own centre (document.elementFromPoint).
    [Arguments]    ${locator}    ${label}
    ${result}=    Evaluate JavaScript    ${locator}
    ...    (el) => { el.scrollIntoView({ block: 'nearest' }); const r = el.getBoundingClientRect(); const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return { ok: hit === el || el.contains(hit), hit: hit ? hit.tagName + '.' + String(hit.className).slice(0, 60) : 'none' } }
    Should Be True    ${result}[ok]    msg=${label} is covered by ${result}[hit]

Dialog Top Should Be On Top
    [Documentation]    The top edge of the dialog panel and its close button are above every other layer, the top
    ...    bar included: elementFromPoint at the middle of the top edge (2 px inside) returns the panel or a child.
    [Arguments]    ${dialog}    ${close}    ${label}
    ${result}=    Evaluate JavaScript    ${dialog}
    ...    (d) => { const r = d.getBoundingClientRect(); const y = Math.max(r.top + 2, 2); const hit = document.elementFromPoint(r.left + r.width / 2, y); return { ok: d.contains(hit), hit: hit ? hit.tagName + '.' + String(hit.className).slice(0, 60) : 'none', top: r.top } }
    Should Be True    ${result}[ok]    msg=The top edge of ${label} is covered by ${result}[hit] (top ${result}[top] px)
    Element Should Be On Top    ${close}    The close button of ${label}

Set Theme And Width
    [Arguments]    ${theme}    ${width}
    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': $theme} }}
    Set Viewport Size    ${width}    800
    Go To    ${FRONTEND_URL}
    Wait For Workspace
    Get Attribute    css=html    data-duunicheck-theme    ==    ${theme}

Open Section And Dialog
    [Arguments]    ${section}    ${opener}    ${dialog}
    Go To Section    ${section}
    Click    ${opener}
    Wait For Elements State    ${dialog}    visible

Close With Escape
    [Arguments]    ${dialog}
    Keyboard Key    press    Escape
    Wait For Elements State    ${dialog}    detached    timeout=5s


*** Test Cases ***
Application details dialog keeps the keyboard inside and returns the focus
    [Documentation]    TC20-001. Expected result: "Tiedot" opens the application details as a modal dialog with the
    ...    focus inside, Tab and Shift+Tab stay in the dialog, Escape closes it and the focus returns to "Tiedot".
    Go To Section    Hakemukset
    Dialog Keyboard Check    css=.job-row:has-text("${COMPANY}") >> button:text-is("Tiedot")    ${DETAILS}

Add application form keeps the keyboard inside and returns the focus
    [Documentation]    TC20-002. Expected result: "＋ Lisää hakemus" opens the form as a modal dialog with the focus
    ...    inside, Tab and Shift+Tab stay in it, Escape closes it without saving and the focus returns to the button.
    ${before}=    Application Count Of    A
    Go To Section    Hakemukset
    Dialog Keyboard Check    css=button:has-text("＋ Lisää hakemus") >> nth=0    ${APP_FORM}
    ${after}=    Application Count Of    A
    Should Be Equal As Integers    ${after}    ${before}

Edit application form keeps the keyboard inside and returns the focus
    [Documentation]    TC20-003. Expected result: "Muokkaa" opens the edit form ("Muokkaa hakemusta") as a modal dialog,
    ...    Tab and Shift+Tab stay in it, Escape closes it and the focus returns to "Muokkaa".
    Go To Section    Hakemukset
    Open Dialog With    css=.job-row:has-text("${COMPANY}") >> button:text-is("Muokkaa")    ${APP_FORM}
    Get Text    ${APP_FORM} >> css=#application-form-title    ==    Muokkaa hakemusta
    Focus Should Be Inside    ${APP_FORM}
    Tab Should Stay Inside    ${APP_FORM}
    Escape Should Close And Return Focus    ${APP_FORM}

CV and template editors keep the keyboard inside and return the focus
    [Documentation]    TC20-004. Expected result: the CV editor ("Muokkaa / päivitä") and the template editor
    ...    ("Muokkaa pohjaa") open as modal dialogs, Tab and Shift+Tab stay inside, Escape closes them and the focus
    ...    returns to the button that opened them.
    Go To Section    CV & pohjat
    Dialog Keyboard Check    css=article:has-text("ROBOT Ikkuna CV") >> button:has-text("Muokkaa / päivitä")    ${CV_EDITOR}
    Dialog Keyboard Check    css=.template-card:has-text("ROBOT Ikkuna pohja") >> button:text-is("Muokkaa pohjaa")    ${TEMPLATE_EDITOR}

Escape in an inline field of the CV editor closes only the field and keeps the focus in the editor
    [Documentation]    TC20-011. Expected result: Escape in the inline "Uusi it-taidot kohta" field of the CV editor
    ...    removes only that field (nothing is added) and the editor stays open with the keyboard focus still inside
    ...    it; the next Escape closes the editor and the focus returns to "Muokkaa / päivitä".
    Go To Section    CV & pohjat
    Open Dialog With    css=article:has-text("ROBOT Ikkuna CV") >> button:has-text("Muokkaa / päivitä")    ${CV_EDITOR}
    Click    css=fieldset:has(legend:has-text("IT-taidot")) >> text=＋ Lisää kohta
    Fill Text    css=input[aria-label="Uusi it-taidot kohta"]    Kesken
    Keyboard Key    press    Escape
    Get Element Count    css=input[aria-label="Uusi it-taidot kohta"]    ==    0
    Wait For Elements State    ${CV_EDITOR}    visible
    Get Element Count    ${CV_EDITOR} >> css=.cv-list-chip:has-text("Kesken"), span:text-is("Kesken")    ==    0
    Focus Should Be Inside    ${CV_EDITOR}    after cancelling the inline field
    Escape Should Close And Return Focus    ${CV_EDITOR}

Delete confirmations start on Peruuta, keep the keyboard inside and delete nothing on Escape
    [Documentation]    TC20-005. Expected result: the delete confirmation of an application (Hakemukset, "Poista") and of
    ...    a file (CV & pohjat, "Poista") opens with the focus on "Peruuta", so Enter cannot confirm by accident;
    ...    Tab and Shift+Tab stay inside; Escape closes it, the focus returns to "Poista" and nothing is deleted.
    ${apps}=    Application Count Of    A
    ${files}=    Api Request    GET    /api/files    user=A
    FOR    ${section}    ${opener}    IN
    ...    Hakemukset    css=.job-row:has-text("${COMPANY}") >> button.delete-action
    ...    CV & pohjat    css=.file-library .delete-material >> nth=0
        Go To Section    ${section}
        Open Dialog With    ${opener}    ${CONFIRM}
        ${on_cancel}=    Evaluate JavaScript    ${None}    () => document.activeElement?.classList.contains('confirm-cancel')
        Should Be True    ${on_cancel}    msg=The focus did not start on Peruuta in the confirmation of ${section}
        Tab Should Stay Inside    ${CONFIRM}
        Escape Should Close And Return Focus    ${CONFIRM}
    END
    ${after_apps}=    Application Count Of    A
    Should Be Equal As Integers    ${after_apps}    ${apps}
    ${after_files}=    Api Request    GET    /api/files    user=A
    Length Should Be    ${after_files.json}    ${{ len($files.json) }}

Application details close an open date picker first on Escape
    [Documentation]    TC20-006. Expected result: in the application details, when the date picker of the event form
    ...    has been opened by clicking the date field, the first Escape closes the date picker and the dialog stays
    ...    open; the next Escape closes the dialog and the focus returns to "Tiedot".
    Go To Section    Hakemukset
    Open Dialog With    css=.job-row:has-text("${COMPANY}") >> button:text-is("Tiedot")    ${DETAILS}
    Click    ${DETAILS} >> css=.event-form input[aria-label="Tapahtuman päivämäärä"]:not([type="hidden"])
    Wait For Elements State    css=.flatpickr-calendar.open    visible
    Keyboard Key    press    Escape
    Wait For Elements State    css=.flatpickr-calendar.open    detached    timeout=5s
    Wait For Elements State    ${DETAILS}    visible
    Escape Should Close And Return Focus    ${DETAILS}

Application details cancel an event edit first on Escape
    [Documentation]    TC20-010. Expected result: in the application details Escape first cancels an event that is
    ...    being edited (the edit field closes, the dialog stays and the event is unchanged), and only the next
    ...    Escape closes the dialog and returns the focus to "Tiedot".
    Go To Section    Hakemukset
    Open Dialog With    css=.job-row:has-text("${COMPANY}") >> button:text-is("Tiedot")    ${DETAILS}
    Click    ${DETAILS} >> css=.history li:has-text("Ikkunatestin merkintä") >> button:text-is("Muokkaa")
    Wait For Elements State    ${DETAILS} >> css=.history li input[aria-label="Tapahtuman lisätieto"]    visible
    Keyboard Key    press    Escape
    Wait For Elements State    ${DETAILS} >> css=.history li input[aria-label="Tapahtuman lisätieto"]    detached    timeout=5s
    Wait For Elements State    ${DETAILS}    visible
    Get Text    ${DETAILS} >> css=.history    contains    Ikkunatestin merkintä
    Escape Should Close And Return Focus    ${DETAILS}

Mobile side menu keeps the keyboard inside and returns the focus to the menu button
    [Documentation]    TC20-007. Runs as an emulated phone 375 px wide. Expected result: the menu button opens the side
    ...    menu with the focus inside the menu, Tab and Shift+Tab stay in the menu, Escape closes it
    ...    (aria-expanded false) and the focus returns to the menu button.
    Open Mobile Workspace    375    800
    Mark Opener    ${MENU_TOGGLE}
    Click    ${MENU_TOGGLE}
    Wait For Elements State    ${MENU}    visible
    Focus Should Be Inside    ${MENU}
    Tab Should Stay Inside    ${MENU}
    Keyboard Key    press    Escape
    Wait For Elements State    ${MENU}    detached    timeout=5s
    Get Attribute    ${MENU_TOGGLE}    aria-expanded    ==    false
    Focus Should Be On Opener
    [Teardown]    Close Mobile Workspace

Workspace dialogs open above the top bar in every theme at 1280 and 375 px
    [Documentation]    TC20-008. Expected result: in the themes default, dark and light and at the widths 1280 and 375
    ...    px, the application details, the add and edit forms, the CV and template editors, the delete confirmation
    ...    and the legal document opened from the user menu are above the top bar: the top edge of each dialog and its
    ...    close button are the topmost elements at their position (elementFromPoint). At 375 px the open side menu is
    ...    above the top bar as well.
    [Tags]    slow
    FOR    ${width}    IN    1280    375
        FOR    ${theme}    IN    @{THEMES}
            Set Theme And Width    ${theme}    ${width}
            Open Section And Dialog    Hakemukset    css=.job-row:has-text("${COMPANY}") >> button:text-is("Tiedot")    ${DETAILS}
            Dialog Top Should Be On Top    ${DETAILS}    ${DETAILS} >> css=.form-heading button[aria-label="Sulje"]    the details (${theme}, ${width} px)
            Close With Escape    ${DETAILS}
            Open Section And Dialog    Hakemukset    css=button:has-text("＋ Lisää hakemus") >> nth=0    ${APP_FORM}
            Dialog Top Should Be On Top    ${APP_FORM}    ${APP_FORM} >> css=.form-heading button[aria-label="Sulje"]    the add form (${theme}, ${width} px)
            Close With Escape    ${APP_FORM}
            Open Section And Dialog    Hakemukset    css=.job-row:has-text("${COMPANY}") >> button:text-is("Muokkaa")    ${APP_FORM}
            Dialog Top Should Be On Top    ${APP_FORM}    ${APP_FORM} >> css=.form-heading button[aria-label="Sulje"]    the edit form (${theme}, ${width} px)
            Close With Escape    ${APP_FORM}
            Open Section And Dialog    Hakemukset    css=.job-row:has-text("${COMPANY}") >> button.delete-action    ${CONFIRM}
            Dialog Top Should Be On Top    ${CONFIRM}    ${CONFIRM} >> css=.confirm-cancel    the delete confirmation (${theme}, ${width} px)
            Close With Escape    ${CONFIRM}
            Open Section And Dialog    CV & pohjat    css=article:has-text("ROBOT Ikkuna CV") >> button:has-text("Muokkaa / päivitä")    ${CV_EDITOR}
            Dialog Top Should Be On Top    ${CV_EDITOR}    ${CV_EDITOR} >> css=.form-heading button[aria-label="Sulje"]    the CV editor (${theme}, ${width} px)
            Close With Escape    ${CV_EDITOR}
            Open Section And Dialog    CV & pohjat    css=.template-card:has-text("ROBOT Ikkuna pohja") >> button:text-is("Muokkaa pohjaa")    ${TEMPLATE_EDITOR}
            Dialog Top Should Be On Top    ${TEMPLATE_EDITOR}    ${TEMPLATE_EDITOR} >> css=.form-heading button[aria-label="Sulje"]    the template editor (${theme}, ${width} px)
            Close With Escape    ${TEMPLATE_EDITOR}
            Click    css=.cl-userButtonTrigger
            Click    css=.cl-userButtonPopoverCard >> button:has-text("Tietosuojaseloste")
            Wait For Elements State    css=#legal-modal-title    visible
            Dialog Top Should Be On Top    css=[role="dialog"]:has(#legal-modal-title)    css=button.legal-modal-close    the legal document (${theme}, ${width} px)
            Close With Escape    css=#legal-modal-title
            IF    ${width} == 375
                Click    ${MENU_TOGGLE}
                Wait For Elements State    ${MENU}    visible
                Element Should Be On Top    ${MENU} >> css=.nav-link.current    The current menu link (${theme}, ${width} px)
                Element Should Be On Top    ${MENU_TOGGLE}    The menu button (${theme}, ${width} px)
                Close With Escape    ${MENU}
            END
        END
    END
    [Teardown]    Run Keywords    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'default'} }}
    ...    AND    Set Viewport Size    1280    900

Sign-in dialog and legal documents of the landing page keep the keyboard inside and stay on top
    [Documentation]    TC20-009. Runs signed out in its own browser session. Expected result: the sign-in dialog
    ...    ("Avaa DuuniCheck") and the legal documents (footer links) take the focus inside, keep Tab and Shift+Tab
    ...    inside, close with Escape and return the focus to the button or link that opened them. At 1280 and 375 px
    ...    their top edge and close button are the topmost elements (elementFromPoint).
    [Setup]    NONE
    New Context    viewport={'width': 1280, 'height': 900}    locale=fi-FI
    New Page    ${FRONTEND_URL}
    Open Landing Page
    Open Dialog With    css=button.auth-cta    ${LOGIN_DIALOG}
    Wait For Elements State    ${LOGIN_DIALOG} >> css=input[name="identifier"]    visible    timeout=15s
    Focus Should Be Inside    ${LOGIN_DIALOG}
    Tab Should Stay Inside    ${LOGIN_DIALOG}
    Escape Should Close And Return Focus    ${LOGIN_DIALOG}
    FOR    ${link}    IN    Käyttöehdot    Tietosuojaseloste
        Open Dialog With    css=footer >> text=${link}    css=#legal-modal-title
        Focus Should Be Inside    css=[role="dialog"]:has(#legal-modal-title)
        Tab Should Stay Inside    css=[role="dialog"]:has(#legal-modal-title)
        Escape Should Close And Return Focus    css=#legal-modal-title
    END
    FOR    ${width}    IN    1280    375
        Set Viewport Size    ${width}    800
        Click    css=button.auth-cta
        Wait For Elements State    ${LOGIN_DIALOG}    visible
        Dialog Top Should Be On Top    ${LOGIN_DIALOG}    css=[aria-label="Sulje kirjautuminen"]    the sign-in dialog (${width} px)
        Close With Escape    ${LOGIN_DIALOG}
        Click    css=footer >> text=Tietosuojaseloste
        Wait For Elements State    css=#legal-modal-title    visible
        Dialog Top Should Be On Top    css=[role="dialog"]:has(#legal-modal-title)    css=button.legal-modal-close    the legal document (${width} px)
        Close With Escape    css=#legal-modal-title
    END
    [Teardown]    Run Keywords    Close Context    AND    Switch To Player    A
