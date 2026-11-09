*** Settings ***
Documentation     Public part of the UI (no login): landing page, login dialog, legal modals,
...               small-screen layout, PWA files and privacy checks of the loaded resources.
Resource          ../resources/common.robot
Suite Setup       Open Test Browser
Suite Teardown    Close Browser    ALL
Test Setup        Open New Session
Test Teardown     Close Session
Force Tags        ui    browser    public


*** Keywords ***
Close Invitation Session
    [Documentation]    Teardown of the invitation tests: closes the session, revokes the unused invitations
    ...    and deletes the invited users that signed up.
    Run Keyword And Ignore Error    Close Session
    Clean Up Invitations

Start Ticket Sign-up Without Password
    [Documentation]    On the open invitation page, starts the sign-up with Clerk's own browser client using only
    ...    the ticket of the address (no password), like a form that forgot to send it. Returns the missing
    ...    fields Clerk reports.
    ${missing}=    Evaluate JavaScript    ${None}
    ...    async () => { const ticket = new URLSearchParams(location.search).get('__clerk_ticket'); const signUp = await window.Clerk.client.signUp.create({ strategy: 'ticket', ticket, legalAccepted: true }); return { status: signUp.status, missing: signUp.missingFields } }
    Should Be Equal    ${missing}[status]    missing_requirements    msg=Clerk did not leave the sign-up open: ${missing}
    RETURN    ${missing}[missing]

Clerk Form Error
    [Documentation]    Waits for the error text Clerk shows under a field of its sign-in form and returns it.
    Wait For Elements State    css=.cl-formFieldErrorText, .cl-alert >> nth=0    visible    timeout=15s
    ${error}=    Get Text    css=.cl-formFieldErrorText, .cl-alert >> nth=0
    RETURN    ${error.strip()}

Invitation Link Should Fail In Finnish
    [Documentation]    Opens a revoked or used invitation link. When the app's invitation form opens, it is
    ...    submitted with a valid password and the terms and must show a Finnish error; otherwise the page that
    ...    Clerk shows must not show an English error. Either way no new Clerk user may appear for the address.
    [Arguments]    ${invitation}    ${existing_users}=0
    Go To    ${invitation}[url]
    ${form}=    Run Keyword And Return Status
    ...    Wait For Elements State    css=.custom-signup-submit:text-is("Hyväksy kutsu")    enabled    timeout=30s
    IF    ${form}
        ${password}=    Throw-away Password
        Fill Text    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input    ${password}
        Check Checkbox    css=.custom-signup-consent input
        Click    css=.custom-signup-submit
        Wait For Elements State    css=.custom-signup-message    visible    timeout=20s
        ${message}=    Get Text    css=.custom-signup-message
        Text Should Be Finnish    ${message}    The error of the invitation form
        Get Element Count    ${WORKSPACE}    ==    0
    ELSE
        ${page}=    Get Text    css=body
        Text Should Be Finnish    ${page}    The page of the invitation link
    END
    ${users}=    Clerk User Ids With Email    ${invitation}[email]
    Length Should Be    ${users}    ${existing_users}    msg=The invitation link created an account

Details View Should Not Be Empty
    [Documentation]    The "Täydennä tilin tiedot" form must have at least one field or a clear error message.
    ${fields}=    Get Element Count    css=.custom-signup form input
    ${alerts}=    Get Element Count    css=.custom-signup [role="alert"], .custom-signup-message
    Should Be True    ${fields} + ${alerts} > 0    msg=The "Täydennä tilin tiedot" view is empty


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

Login dialog opens with Clerk's sign-in and closes with the close button
    [Documentation]    TC01-003. Expected result: the button opens the dialog "DuuniCheckin kirjautuminen" with
    ...    Clerk's own sign-in form (e-mail field), the address is the sign-in address, and the close button
    ...    closes the dialog and returns to the landing page address.
    Open Login Dialog
    Wait For Elements State    ${LOGIN_DIALOG} >> css=.cl-signIn-root input[name="identifier"]    visible    timeout=15s
    ${path}=    Evaluate JavaScript    ${None}    () => window.location.pathname
    Should End With    ${path}    /sign-in
    Click    css=[aria-label="Sulje kirjautuminen"]
    Wait For Elements State    ${LOGIN_DIALOG}    detached
    ${path}=    Evaluate JavaScript    ${None}    () => window.location.pathname
    Should Not Contain    ${path}    sign-in

Login dialog has no sign-up choice of its own and no Clerk sign-up link
    [Documentation]    TC01-028. The Clerk development instance is in Invite-only access mode, in which
    ...    Clerk hides the sign-up link of its sign-in form. Expected result: the login dialog has no "Kirjaudu /
    ...    Luo tili" switch of the app (no tab list, no "Luo tili" text, no sign-up form) and Clerk's sign-in shows
    ...    no "Rekisteröidy" / sign-up link, also after the e-mail step has rendered.
    Open Login Dialog
    Wait For Elements State    ${LOGIN_DIALOG} >> css=input[name="identifier"]    visible    timeout=15s
    Wait For Load State    networkidle
    Get Element Count    ${LOGIN_DIALOG} >> css=[role="tablist"], .auth-mode-switch, [role="tab"]    ==    0
    Get Element Count    ${LOGIN_DIALOG} >> text=Luo tili    ==    0
    Get Element Count    ${LOGIN_DIALOG} >> css=.custom-signup    ==    0
    Get Element Count    ${LOGIN_DIALOG} >> css=.cl-footerAction, .cl-footerActionLink    ==    0
    Get Element Count    ${LOGIN_DIALOG} >> css=a[href*="sign-up"]    ==    0
    ${text}=    Get Text    ${LOGIN_DIALOG}
    Should Not Contain    ${text}    Rekisteröidy    ignore_case=${True}
    Should Not Contain    ${text}    Sign up    ignore_case=${True}

Landing page says exactly that the sign-in opens securely in Clerk
    [Documentation]    TC01-029. Expected result: the text under the "Avaa DuuniCheck" button is exactly
    ...    "Kirjautuminen avautuu turvallisesti Clerkissä." and the page no longer mentions creating an account.
    Open Landing Page
    Get Text    css=.auth-cta + small    ==    ${LANDING_AUTH_NOTE}
    ${landing}=    Get Text    css=body
    Should Not Contain    ${landing}    uuden tilin luonti
    Should Not Contain    ${landing}    Luo tili

Invitation link opens the app's sign-up form and the dialog cannot be closed
    [Documentation]    TC01-030. An invitation is created with the Clerk Backend API (redirect_url /duunicheck/sign-up)
    ...    and its link is opened like the invited person would. Expected result: Clerk forwards the link to the app
    ...    (not to a Clerk hosted page) and the dialog "Kutsu DuuniCheckiin" opens with the app's invitation form:
    ...    heading "Luo kutsutili", a password field, the terms box and "Hyväksy kutsu", but no e-mail field, no
    ...    Google button and no sign-in form. The close button is disabled, and neither Escape nor a click on the
    ...    backdrop closes the dialog or drops the ticket from the address. No account is created by opening it.
    [Tags]    invitation
    ${invitation}=    Invite Throw-away User    open
    Open Invitation Link    ${invitation}
    ${frontend_origin}=    Evaluate    '/'.join($FRONTEND_URL.split('/')[:3])
    ${url}=    Get Url
    Should Start With    ${url}    ${frontend_origin}${INVITE_REDIRECT_PATH}?    msg=The invitation did not lead to the app's sign-up address: ${url}
    Get Text    ${INVITE_DIALOG} >> css=.custom-signup h2    ==    Luo kutsutili
    Get Text    ${INVITE_DIALOG} >> css=.auth-kicker    ==    KUTSU DUUNICHECKIIN
    Get Element Count    ${INVITE_DIALOG} >> css=.custom-signup form input[type="password"]    ==    1
    Get Element Count    ${INVITE_DIALOG} >> css=.custom-signup-consent input[type="checkbox"]    ==    1
    Get Element Count    ${INVITE_DIALOG} >> css=input[type="email"], .custom-signup-google    ==    0
    Get Element Count    ${INVITE_DIALOG} >> css=input[name="identifier"]    ==    0
    Get Element States    css=[aria-label="Sulje kirjautuminen"]    contains    disabled
    Keyboard Key    press    Escape
    Click With Options    css=.auth-dialog-backdrop    position_x=5    position_y=5
    Sleep    1s
    Wait For Elements State    ${INVITE_DIALOG}    visible
    Get Url    contains    __clerk_ticket=
    ${users}=    Clerk User Ids With Email    ${invitation}[email]
    Should Be Empty    ${users}
    ${status}=    Clerk Invitation Status    ${invitation}[id]
    Should Be Equal    ${status}    pending
    [Teardown]    Close Invitation Session

Invited user signs up with a password and the workspace opens
    [Documentation]    TC01-031. Expected result: the invitation form asks for a password (the e-mail comes from
    ...    the invitation). With a valid password and the terms accepted (and the name or e-mail code, if Clerk asks
    ...    for them), the account is created in Clerk with the invited e-mail, the invitation becomes accepted and
    ...    the new user's workspace opens signed in. The Clerk user is deleted in the teardown.
    [Tags]    invitation
    ${invitation}=    Invite Throw-away User    signup
    Open Invitation Link    ${invitation}
    ${before}=    Clerk User Ids With Email    ${invitation}[email]
    Should Be Empty    ${before}
    ${password}=    Throw-away Password
    Complete Invitation Sign-up    ${password}
    ${after}=    Clerk User Ids With Email    ${invitation}[email]
    Length Should Be    ${after}    1    msg=The invited user was not created in Clerk
    ${user_id}=    Get Current User Id
    Should Be Equal    ${user_id}    ${after}[0]
    ${email}=    Evaluate JavaScript    ${None}    () => window.Clerk.user.primaryEmailAddress.emailAddress
    Should Be Equal    ${email}    ${invitation}[email]
    ${status}=    Clerk Invitation Status    ${invitation}[id]
    Should Be Equal    ${status}    accepted
    [Teardown]    Close Invitation Session

Details view asks for the password when Clerk still needs it
    [Documentation]    TC01-032. An invitation sign-up is started in the browser without a password (Clerk's own
    ...    client, signUp.create with the ticket only), so Clerk reports the missing password. The app's continue
    ...    address (sign-up/continue) is then opened. Expected result: the "Täydennä tilin tiedot" view is never
    ...    empty: it shows the password field (and every other field Clerk asks for), and filling them creates the
    ...    account and opens the workspace.
    [Tags]    invitation
    ${invitation}=    Invite Throw-away User    details
    Open Invitation Link    ${invitation}
    ${missing}=    Start Ticket Sign-up Without Password
    Should Contain    ${missing}    password    msg=Clerk did not ask for a password: ${missing}
    Go To    ${FRONTEND_URL}sign-up/continue
    Wait For Elements State    text=Täydennä tilin tiedot    visible    timeout=20s
    Details View Should Not Be Empty
    Get Element Count    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input[@type="password"]    ==    1
    ${password}=    Throw-away Password
    Fill Missing Sign-up Details    ${password}
    Wait For Workspace
    ${after}=    Clerk User Ids With Email    ${invitation}[email]
    Length Should Be    ${after}    1
    [Teardown]    Close Invitation Session

Details view explains a field the form cannot ask for instead of staying empty
    [Documentation]    TC01-033. As TC01-032, but every answer of Clerk's Frontend API is changed in the browser so
    ...    that the sign-up also asks for a phone number, a field the app's form cannot ask for. Expected result:
    ...    the "Täydennä tilin tiedot" view is not empty: it still shows the password field and a clear error
    ...    message that names the field ("puhelinnumero") and says the account cannot be created; "Jatka" is
    ...    disabled and no account is created.
    [Tags]    invitation
    ${invitation}=    Invite Throw-away User    unsupported
    Open Invitation Link    ${invitation}
    ${missing}=    Start Ticket Sign-up Without Password
    Should Contain    ${missing}    password
    Add Missing Sign Up Field    clerk.accounts.dev/v1/client    phone_number
    Go To    ${FRONTEND_URL}sign-up/continue
    Wait For Elements State    text=Täydennä tilin tiedot    visible    timeout=20s
    Details View Should Not Be Empty
    Get Text    css=.custom-signup [role="alert"]    contains    Clerk pyytää tietoa, jota tämä lomake ei osaa kysyä: puhelinnumero
    Get Text    css=.custom-signup [role="alert"]    contains    Tiliä ei voi luoda
    Get Element Count    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input    ==    1
    Get Element States    css=.custom-signup-submit    contains    disabled
    ${users}=    Clerk User Ids With Email    ${invitation}[email]
    Should Be Empty    ${users}
    [Teardown]    Run Keywords    Run Keyword And Ignore Error    Clear Mocked Responses    AND    Close Invitation Session

Too short password in the invitation form gives an error and no account
    [Documentation]    TC01-034. Expected result: a 5-character password in the invitation form is refused: the
    ...    browser blocks the form (the password field is too short and has a validation message) and the form
    ...    stays open. When the browser check is bypassed (the minlength attribute is removed), Clerk refuses the
    ...    password and the form shows an error message in Finnish (no English words such as "password" or
    ...    "characters"). No account is created and the invitation stays pending.
    [Tags]    invitation    finnish-errors
    ${invitation}=    Invite Throw-away User    short
    Open Invitation Link    ${invitation}
    ${field}=    Set Variable    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input
    Fill Text    ${field}    Ab1!x
    Check Checkbox    css=.custom-signup-consent input
    Click    css=.custom-signup-submit
    ${too_short}=    Evaluate JavaScript    ${field}    (input) => input.validity.tooShort
    Should Be True    ${too_short}    msg=The browser accepted a 5-character password
    ${validation}=    Get Property    ${field}    validationMessage
    Should Not Be Empty    ${validation}
    Wait For Elements State    css=.custom-signup-submit:text-is("Hyväksy kutsu")    visible
    Evaluate JavaScript    ${field}    (input) => input.removeAttribute('minlength')
    Click    css=.custom-signup-submit
    Wait For Elements State    css=.custom-signup-message    visible    timeout=20s
    ${message}=    Get Text    css=.custom-signup-message
    Text Should Be Finnish    ${message}    The too-short password error
    Get Element Count    ${WORKSPACE}    ==    0
    Wait For Elements State    css=.custom-signup-submit:text-is("Hyväksy kutsu")    visible
    ${users}=    Clerk User Ids With Email    ${invitation}[email]
    Should Be Empty    ${users}    msg=An account was created with a 5-character password
    ${status}=    Clerk Invitation Status    ${invitation}[id]
    Should Be Equal    ${status}    pending
    [Teardown]    Close Invitation Session

Revoked invitation gives a Finnish error and no account
    [Documentation]    TC01-035. An invitation is created and revoked with the Clerk Backend API, then its link
    ...    is opened. Expected result: the link does not create an account. If the app's invitation form opens,
    ...    submitting it with a valid password and the terms shows an error in Finnish (no English words);
    ...    if Clerk stops the link before the app, the page shown has no English error text either. No Clerk
    ...    user is created with the address.
    [Tags]    invitation    finnish-errors
    ${invitation}=    Invite Throw-away User    revoked
    Revoke Created Invitations
    Invitation Link Should Fail In Finnish    ${invitation}
    [Teardown]    Close Invitation Session

Used invitation gives a Finnish error and no second account
    [Documentation]    TC01-036. An invited user signs up with the link (TC01-031 path); the same link is then
    ...    opened again in a new browser session. Expected result: the second use creates no new account and
    ...    shows an error in Finnish (no English words), as in TC01-035; the address still has exactly one
    ...    Clerk user.
    [Tags]    invitation    finnish-errors
    ${invitation}=    Invite Throw-away User    used
    Open Invitation Link    ${invitation}
    ${password}=    Throw-away Password
    Complete Invitation Sign-up    ${password}
    Close Session
    Open New Session
    Invitation Link Should Fail In Finnish    ${invitation}    existing_users=1
    [Teardown]    Close Invitation Session

Sign-in with a wrong password shows a Finnish error
    [Documentation]    TC01-037. Expected result: signing in as user A with a wrong password is refused with
    ...    Clerk's error under the password field in Finnish ("Sähköpostiosoite tai salasana on väärä" or
    ...    "Salasana on väärä"), with no English words such as "password" or "incorrect", and the workspace
    ...    does not open.
    [Tags]    finnish-errors
    Open Sign In
    Fill Text    input[name="identifier"]    ${USER_A_EMAIL}
    Click    .cl-formButtonPrimary
    Wait For Elements State    input[name="password"]    visible    timeout=15s
    Fill Text    input[name="password"]    Robot-Väärä-Salasana-1!
    Click    .cl-formButtonPrimary
    ${error}=    Clerk Form Error
    Should Match Regexp    ${error}    ^(Sähköpostiosoite tai salasana on väärä|Salasana on väärä)    msg=Unexpected wrong-password error: ${error}
    Text Should Be Finnish    ${error}    The wrong-password error
    Get Element Count    ${WORKSPACE}    ==    0

Sign-in with an unknown e-mail says exactly that no account was found
    [Documentation]    TC01-038. Expected result: an e-mail address without an account gives exactly
    ...    "Tiliä ei löytynyt näillä tiedoilla." under the field.
    [Tags]    finnish-errors
    Open Sign In
    Fill Text    input[name="identifier"]    robot-unknown-${{ int(__import__('time').time()) }}+clerk_test@example.com
    Click    .cl-formButtonPrimary
    ${error}=    Clerk Form Error
    Should Be Equal    ${error}    Tiliä ei löytynyt näillä tiedoilla.

Sign-in error texts contain no English words
    [Documentation]    TC01-039. Expected result: every sign-in error shown by Clerk is in Finnish: a malformed
    ...    e-mail address, an unknown e-mail, a wrong password and an empty password. None of them contains
    ...    English words such as "password", "incorrect", "invalid", "expired" or "account" (the sign-up form
    ...    errors are checked in TC01-034..036).
    [Tags]    finnish-errors
    Open Sign In
    FOR    ${identifier}    IN    robot-ei-osoite@    robot-unknown-${{ int(__import__('time').time()) }}+clerk_test@example.com
        Fill Text    input[name="identifier"]    ${identifier}
        Click    .cl-formButtonPrimary
        # A malformed address can already be stopped by the browser's own check; its message counts too.
        ${browser_message}=    Get Property    input[name="identifier"]    validationMessage
        IF    $browser_message
            Text Should Be Finnish    ${browser_message}    The browser's message for "${identifier}"
        ELSE
            ${error}=    Clerk Form Error
            Text Should Be Finnish    ${error}    The error for "${identifier}"
        END
    END
    Fill Text    input[name="identifier"]    ${USER_A_EMAIL}
    Click    .cl-formButtonPrimary
    Wait For Elements State    input[name="password"]    visible    timeout=15s
    FOR    ${password}    IN    x    Robot-Väärä-Salasana-2!
        Fill Text    input[name="password"]    ${password}
        Click    .cl-formButtonPrimary
        ${error}=    Clerk Form Error
        Text Should Be Finnish    ${error}    The password error
    END

Privacy policy describes the invitation-only service and what the AI context sends
    [Documentation]    TC01-040. Expected result: section 2 of the privacy policy says that the service is invitation
    ...    based. Section 5 says that the text of attached files is sent (at most 8 000 characters per file and 20 000
    ...    in total), which details are removed (e-mail addresses, phone numbers, postal addresses, web addresses,
    ...    the name and saved contact details), how the name is recognised, that the AI is told not to write the
    ...    name or contact details, and that choosing the CV and cover letter is off by default. The old sentence
    ...    "koko tiedostoa ei tämän toiminnon kautta lähetetä" is gone, and neither the policy nor the landing page
    ...    names a job site.
    [Tags]    privacy
    Open Landing Page
    Click    css=footer >> text=Tietosuojaseloste
    Wait For Elements State    css=#legal-modal-title    visible
    ${text}=    Get Text    ${DIALOG}
    ${text}=    Evaluate    ' '.join($text.replace(chr(0xa0), ' ').split())
    Should Contain    ${text}    2. Kuka voi käyttää palvelua
    Should Contain    ${text}    Palvelu on kutsupohjainen. Tilin voi luoda vain kehittäjän lähettämällä kutsulla.
    Should Contain    ${text}    5. Tekoälyavustaja
    Should Contain    ${text}    OpenAI:lle lähetetään myös tiedostojen teksti, enintään 8 000 merkkiä tiedostoa kohden ja enintään 20 000 merkkiä yhteensä.
    Should Contain    ${text}    Tiedostoa itseään tai sen kuvia ei lähetetä.
    Should Contain    ${text}    poistetaan sähköpostiosoitteet, puhelinnumerot, postiosoitteet, nettiosoitteet, nimesi ja CV:ihin ja hakemuspohjiin tallentamasi yhteystiedot.
    Should Contain    ${text}    Nimesi tunnistetaan profiilistasi, CV:istäsi ja hakemuspohjistasi, sähköpostiosoitteestasi sekä dokumentin alusta ja allekirjoituksesta
    Should Contain    ${text}    Tekoälyä ohjeistetaan olemaan kirjoittamatta nimeäsi tai yhteystietojasi vastaukseen.
    Should Contain    ${text}    CV:n ja hakukirjeen valinta on vapaaehtoinen ja oletuksena pois päältä.
    Should Not Contain    ${text}    koko tiedostoa ei tämän toiminnon kautta lähetetä
    Should Not Contain    ${text}    koko tiedostoa
    Text Should Name No Job Site    ${text}    The privacy policy
    Keyboard Key    press    Escape
    Wait For Elements State    css=#legal-modal-title    detached
    ${landing}=    Get Text    css=body
    Text Should Name No Job Site    ${landing}    The landing page

Login dialog closes with the Escape key
    [Documentation]    TC01-004. Expected result: Login dialog closes with the Escape key (keyboard users
    ...    must be able to leave a modal dialog). An invitation link keeps the dialog open on Escape (TC01-030).
    [Tags]    accessibility
    Open Login Dialog
    Keyboard Key    press    Escape
    Wait For Elements State    ${LOGIN_DIALOG}    detached

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
    [Documentation]    TC01-017. The sign-up form is opened from an invitation link (the development instance is
    ...    invite-only). Expected result: the form refuses to continue until the terms and the privacy policy are
    ...    accepted and tells the user why; no account is created and the invitation stays pending.
    [Tags]    browser    invitation
    ${invitation}=    Invite Throw-away User    consent
    Open Invitation Link    ${invitation}
    Get Checkbox State    css=.custom-signup-consent input    ==    unchecked
    ${password}=    Throw-away Password
    Fill Text    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input    ${password}
    Click    css=.custom-signup-submit
    Get Text    css=.custom-signup-message    contains    Hyväksy käyttöehdot ja tietosuojaseloste
    Wait For Elements State    css=.custom-signup-submit:text-is("Hyväksy kutsu")    visible
    Sleep    2s
    ${users}=    Clerk User Ids With Email    ${invitation}[email]
    Should Be Empty    ${users}    msg=An account was created without accepting the terms
    ${status}=    Clerk Invitation Status    ${invitation}[id]
    Should Be Equal    ${status}    pending
    [Teardown]    Close Invitation Session

Login dialog closes when the backdrop is clicked
    [Documentation]    TC01-018. Expected result: a click outside the dialog closes it.
    [Tags]    browser
    Open Login Dialog
    Click With Options    css=.auth-dialog-backdrop    position_x=5    position_y=5
    Wait For Elements State    ${LOGIN_DIALOG}    detached

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
    [Documentation]    TC01-020. The sign-up form is opened from an invitation link (the development instance
    ...    is invite-only). Expected result: The terms and privacy links of the sign-up consent open the
    ...    documents as dialogs. Closing them returns to the same invitation form (the invitation ticket is
    ...    kept in the address) with the typed password kept, following a link does not tick the consent
    ...    box, and a box ticked before opening a link stays ticked.
    [Tags]    invitation
    ${invitation}=    Invite Throw-away User    links
    Open Invitation Link    ${invitation}
    ${ticket_url}=    Get Url
    ${password_field}=    Set Variable    css=.custom-signup form >> xpath=.//label[contains(., "Salasana")]//input
    Fill Text    ${password_field}    Robot-Links-aA1!
    FOR    ${link}    IN    käyttöehdot    tietosuojaselosteen
        Click    css=.custom-signup-consent >> a:text-is("${link}")
        Wait For Elements State    css=#legal-modal-title    visible
        Click    css=button.legal-modal-close
        Wait For Elements State    css=#legal-modal-title    detached
        Wait For Elements State    ${INVITE_DIALOG} >> css=.custom-signup-submit:text-is("Hyväksy kutsu")    visible
        Get Url    ==    ${ticket_url}
        Get Checkbox State    css=.custom-signup-consent input    ==    unchecked
        Get Property    ${password_field}    value    ==    Robot-Links-aA1!
    END
    Check Checkbox    css=.custom-signup-consent input
    Click    css=.custom-signup-consent >> a:text-is("käyttöehdot")
    Wait For Elements State    css=#legal-modal-title    visible
    Click    css=button.legal-modal-close
    Wait For Elements State    css=#legal-modal-title    detached
    Get Checkbox State    css=.custom-signup-consent input    ==    checked
    Get Url    ==    ${ticket_url}
    [Teardown]    Close Invitation Session

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
        ${box}=    Get BoundingBox    ${LOGIN_DIALOG}
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
