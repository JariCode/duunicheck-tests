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
