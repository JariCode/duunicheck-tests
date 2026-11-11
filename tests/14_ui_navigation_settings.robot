*** Settings ***
Documentation     Navigation, theme persistence, user menu and sign-out in the UI.
Resource          ../resources/common.robot
Suite Setup       Prepare UI Suite
Suite Teardown    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    navigation


*** Keywords ***
Prepare UI Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A

Open Workspace Of User A
    [Documentation]    Opens the workspace of user A in user A's session. Signs in again when the session has
    ...    already signed out (after TC14-006), otherwise only resets the viewport and opens the overview.
    Switch To Player    A
    Set Viewport Size    1280    900
    Go To    ${FRONTEND_URL}
    Wait For Elements State    css=.workspace .topbar, .auth-cta >> nth=0    visible    timeout=45s
    ${signed_out}=    Get Element Count    css=.auth-cta
    IF    ${signed_out}    Sign In
    Wait For Workspace


*** Test Cases ***
Every sidebar section opens without errors
    [Documentation]    TC14-001. Expected result: Every sidebar section opens without errors.
    FOR    ${section}    IN    Yleiskatsaus    Hakemukset    Eteneminen    Kalenteri    CV & pohjat    AI-chat
        Go To Section    ${section}
        Get Element Count    css=.api-error    ==    0
    END

Theme can be changed and is saved to the account
    [Documentation]    TC14-002. Expected result: Theme can be changed and is saved to the account.
    FOR    ${theme}    IN    dark    light    default
        Select Options By    css=[aria-label="Väriteema"]    value    ${theme}
        Sleep    1s
        Get Attribute    css=html    data-duunicheck-theme    ==    ${theme}
        ${api}=    Api Request    GET    /api/settings    user=A
        Should Be Equal    ${api.json}[theme]    ${theme}
    END

Chosen theme is restored after reload
    [Documentation]    TC14-003. Expected result: Chosen theme is restored after reload.
    Select Options By    css=[aria-label="Väriteema"]    value    dark
    Sleep    1s
    Reload
    Wait For Workspace
    Get Attribute    css=html    data-duunicheck-theme    ==    dark
    [Teardown]    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'default'} }}

User menu contains account, legal links and sign out
    [Documentation]    TC14-004. Expected result: User menu contains account, legal links and sign out.
    Click    css=.cl-userButtonTrigger
    Wait For Elements State    text=Käyttöehdot    visible
    Wait For Elements State    text=Tietosuojaseloste    visible
    Keyboard Key    press    Escape

Protected data is not stored in browser storage
    [Documentation]    TC14-005. Expected result: Protected data is not stored in browser storage.
    ${storage}=    Evaluate JavaScript    ${None}    () => JSON.stringify([Object.entries(localStorage), Object.entries(sessionStorage)])
    Should Not Contain    ${storage}    sk_test
    Should Not Contain    ${storage}    sk_live
    Should Not Contain    ${storage}    whsec_
    Should Not Contain    ${storage}    ${USER_A_PASSWORD}

Clerk checkbox in the password change form is a small checkbox in every theme
    [Documentation]    TC14-008. Expected result: in the themes default, dark and light, Hallitse tiliä → Turvallisuus →
    ...    password change shows the "Kirjaudu ulos kaikista muista laitteista" checkbox as a checkbox of at most
    ...    20 × 20 px (the text field styles no longer hit it). The password is not changed: the dialog is closed
    ...    with Escape.
    FOR    ${theme}    IN    default    dark    light
        Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': $theme} }}
        Go To    ${FRONTEND_URL}
        Wait For Workspace
        Get Attribute    css=html    data-duunicheck-theme    ==    ${theme}
        Click    css=.cl-userButtonTrigger
        Click    css=.cl-userButtonPopoverActionButton:has-text("Hallitse tiliä")
        Wait For Elements State    css=.cl-modalContent    visible
        Click    css=.cl-modalContent >> text=Turvallisuus
        Click    css=.cl-modalContent .cl-profileSection__password button >> nth=0
        ${checkbox}=    Set Variable    css=.cl-modalContent input[type="checkbox"]
        Wait For Elements State    ${checkbox}    visible    timeout=15s
        Get Text    css=.cl-modalContent    contains    Kirjaudu ulos kaikista muista laitteista
        ${box}=    Get BoundingBox    ${checkbox}
        Should Be True    0 < ${box}[width] <= 20 and 0 < ${box}[height] <= 20
        ...    msg=The checkbox is ${box}[width] × ${box}[height] px in theme ${theme}
        Keyboard Key    press    Escape
        Wait For Elements State    css=.cl-modalContent    detached    timeout=10s
    END
    [Teardown]    Api Request    PUT    /api/settings    user=A    json_body=${{ {'theme': 'default'} }}

Signing out returns the user to the landing page
    [Documentation]    TC14-006. Expected result: Signing out returns the user to the landing page.
    Click    css=.cl-userButtonTrigger
    Click    text=Kirjaudu ulos
    Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible    timeout=30s
    Get Element Count    text=Yleiskatsaus    ==    0

Workspace cannot be reached without signing in
    [Documentation]    TC14-007. Expected result: Workspace cannot be reached without signing in, not
    ...    even with a deep link to a section. Runs after TC14-006 has signed the user out. The
    ...    landing page shows a decorative "Hakemukset" card, so the workspace is checked by its
    ...    structure (top bar, main navigation) instead of by text.
    [Setup]    NONE
    FOR    ${url}    IN    ${FRONTEND_URL}    ${FRONTEND_URL}?view=jobs    ${FRONTEND_URL}?view=materials
        Go To    ${url}
        Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible
        Get Element Count    css=.workspace    ==    0
        Get Element Count    ${WORKSPACE}    ==    0
        Get Element Count    ${NAV}    ==    0
        Get Element Count    text=Yleiskatsaus    ==    0
    END

Signing out loads the page fully
    [Documentation]    TC14-009. Runs last, because it signs user A out; when TC14-006 has already signed the user
    ...    out, the setup signs in again. A marker (window.__robotNoReload = true) is set in the workspace and the user
    ...    signs out from the user menu. Expected result: the landing page opens and the marker is gone, so signing
    ...    out outside the sign-in and sign-up dialogs is a full page load (routerPush/routerReplace keep the
    ...    page only inside those dialogs).
    [Tags]    subdomain-release
    [Setup]    Open Workspace Of User A
    Evaluate JavaScript    ${None}    () => { window.__robotNoReload = true }
    Click    css=.cl-userButtonTrigger
    Click    text=Kirjaudu ulos
    Wait For Elements State    text=Avaa DuuniCheck >> nth=0    visible    timeout=30s
    ${marker}=    Evaluate JavaScript    ${None}    () => window.__robotNoReload === undefined
    Should Be True    ${marker}    msg=The page was not loaded again when signing out (the marker is still set)
