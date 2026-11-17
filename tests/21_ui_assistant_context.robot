*** Settings ***
Documentation     The context column of the AI chat (CV, Hakukirje and notes rows), the way AI answers are
...               shown, saving an AI cover letter as a new template (the template and application requests reach
...               the real backend), the choice between a local answer and the AI, and the timeout and connection
...               error messages. The answer of POST /api/assistant/suggest is replaced with test data (Mock Json Response,
...               libraries/network_mocks.js), so no OpenAI call is made; the mock also records the request body,
...               which shows which context the browser asked the backend to send. All data is invented.
Resource          ../resources/common.robot
Suite Setup       Prepare Context Suite
Suite Teardown    Run Keywords    Run Keyword And Ignore Error    Delete All Data    A    AND    Close Browser    ALL
Test Setup        Return To Clean Workspace
Force Tags        ui    browser    assistant


*** Variables ***
${OPTIONS}          css=.permission-list:not(.posting-draft-section)
${CV_ROW}           css=.permission-list:not(.posting-draft-section) > label:nth-of-type(2)
${LETTER_ROW}       css=.permission-list:not(.posting-draft-section) > label:nth-of-type(3)
${NOTES_ROW}        css=.permission-list:not(.posting-draft-section) > label:nth-of-type(4)
${ALLOW}            css=.permission-list:not(.posting-draft-section) label.approval-choice input
${COMPOSER}         css=.chat-composer textarea
${SEND}             css=.assistant-chat > button.chat-send
${FULL}             ROBOT Konteksti Tiedostot Oy
${APP_MATERIAL}     ROBOT Konteksti Sovellus Oy
${EMPTY_APP}        ROBOT Konteksti Tyhjä Oy
${CHAT_ERROR}       css=.assistant-chat > p.assistant-error
${ANSWERS}          css=.chat-messages > article.assistant-message
${SAVE_LETTER}      button:text-is("Tallenna uudeksi hakukirjeeksi")
${LETTER_DIALOG}    css=section.confirm-dialog:has(#confirm-dialog-title:text-is("Tallennetaanko uusi hakukirje?"))
${LETTER_HINT}      Tarkista kirje ja tallenna se uudeksi hakukirjeeksi painikkeella.
${COPY_HINT}        Voit kopioida ehdotuksen ja hyväksyä muokkauksen itse hakemuksessa.
${LOCAL_HINT}       Vastaus haettiin hakemuksen tiedoista. Jos tarkoitit viestin työparille, lähetä se AI:lle.
${TIMEOUT_ERROR}    AI-vastaus kesti liian kauan. Yritä uudelleen tai pyydä lyhyempi vastaus, esimerkiksi ensin pelkkä arvio ja sitten hakukirje erikseen.
${OFFLINE_ERROR}    Palvelimeen ei saatu yhteyttä. Tarkista verkkoyhteys ja yritä uudelleen.
# Invented person of the cover letter tests. Area code 00 does not exist, so the number is never real.
${PERSON}           Matti Meikäläinen
${PERSON_EMAIL}     matti.meikalainen@example.com
${PERSON_PHONE}     +358 00 000 0000
${LETTER_APP}       ROBOT Kirjeyhtiö Oy
${FILE_APP}         ROBOT Kirjetiedosto Oy
# A cover letter as the AI writes it: [Nimesi] for the name, [Yhteystietosi] for the contact line and one
# place in brackets left for the user to fill in.
${AI_LETTER}        Hei,\n\nHaen testaajan tehtävää yrityksessänne. Olen rakentanut testiautomaatiota verkkosovelluksille. [Kuvaa tähän yksi onnistunut testausprojektisi]\n\nYstävällisin terveisin,\n[Nimesi]\n[Yhteystietosi]
# The same letter as a template body (letterTemplate.js): the contact line is removed, [Nimesi] is {{nimi}}.
${LETTER_BODY}      Hei,\n\nHaen testaajan tehtävää yrityksessänne. Olen rakentanut testiautomaatiota verkkosovelluksille. [Kuvaa tähän yksi onnistunut testausprojektisi]\n\nYstävällisin terveisin,\n{{nimi}}
${PLAIN_LETTER}     Hei,\n\nHaen kehittäjän tehtävää yrityksessänne.\n\nYstävällisin terveisin,\n[Nimesi]


*** Keywords ***
Prepare Context Suite
    Require API Configuration
    Prepare Players    A
    Delete All Data    A
    ${cv_file}=    Upload Text File As    A    cv    robot-cv-tiedosto.txt    Testaajan CV
    ${letter}=    Upload Text File As    A    application    robot-hakukirje.txt    Testaajan hakukirje
    ${letter2}=    Upload Text File As    A    application    robot-hakukirje-2.txt    Toinen hakukirje
    ${cv}=    Create Cv As    A    name=ROBOT Kontekstin CV
    ${template}=    Create Template As    A    name=ROBOT Kontekstin pohja
    Create Application As    A    company=${FULL}    cvFileId=${cv_file}[id]
    ...    applicationFileIds=${{ [$letter['id'], $letter2['id']] }}    notes=Kontekstin muistiinpano
    Create Application As    A    company=${APP_MATERIAL}    cvId=${cv}[id]    templateId=${template}[id]
    ...    applicationText=Hakemusteksti ilman yhteystietoja.    notes=Toinen muistiinpano
    Create Application As    A    company=${EMPTY_APP}
    Reload
    Wait For Workspace

Choose Application
    [Arguments]    ${company}
    Click    css=.application-picker-trigger
    Click    css=[role="option"]:has-text("${company}")
    Get Text    css=.application-picker-trigger    contains    ${company}
    Wait For Elements State    ${OPTIONS}    visible

Row Should Be
    [Documentation]    Checks the text, the enabled state and the locked look of one context row.
    [Arguments]    ${row}    ${text}    ${enabled}
    Get Text    ${row}    contains    ${text}
    ${input}=    Set Variable    ${row} >> css=input[type="checkbox"]
    Get Property    ${input}    disabled    ==    ${{ not $enabled }}
    ${locked}=    Get Element Count    ${row}.is-context-locked
    Should Be Equal As Integers    ${locked}    ${{ 0 if $enabled else 1 }}

Mock Suggestion
    [Arguments]    ${suggestion}    @{notices}
    ${body}=    Evaluate    json.dumps({'suggestion': $suggestion, 'notices': list($notices)})    modules=json
    Mock Json Response    **/api/assistant/suggest    200    ${body}

Mock Suggestion With Letter
    [Documentation]    The /suggest answer the backend gives for a structured reply: the whole reply as
    ...    "suggestion" and the cover letter on its own as "letter" (empty when the reply has no letter).
    [Arguments]    ${suggestion}    ${letter}
    ${body}=    Evaluate    json.dumps({'suggestion': $suggestion, 'letter': $letter, 'notices': []})    modules=json
    Mock Json Response    **/api/assistant/suggest    200    ${body}

Helsinki Date Label
    [Documentation]    Today in Finland as pp.kk.vvvv, as in the name of a saved AI cover letter.
    ${label}=    Evaluate    datetime.datetime.now(zoneinfo.ZoneInfo('Europe/Helsinki')).strftime('%d.%m.%Y')
    ...    modules=datetime,zoneinfo
    RETURN    ${label}

Answer With Text
    [Arguments]    ${text}
    RETURN    ${ANSWERS}:has-text("${text}")

Template Named
    [Documentation]    User A's template with the given name (fails unless there is exactly one).
    [Arguments]    ${name}
    ${list}=    Api Request    GET    /api/templates    user=A
    ${matches}=    Evaluate    [t for t in $list.json if t['name'] == $name]
    Length Should Be    ${matches}    1    msg=Templates named "${name}": ${{ len($matches) }}
    RETURN    ${matches}[0]

Application Named
    [Arguments]    ${company}
    ${list}=    Api Request    GET    /api/applications    user=A
    ${match}=    Evaluate    [a for a in $list.json if a['company'] == $company][0]
    RETURN    ${match}

Save Letter From
    [Documentation]    Presses "Tallenna uudeksi hakukirjeeksi" under the given answer and checks that the
    ...    confirmation names the new template.
    [Arguments]    ${answer}    ${name}
    Click    ${answer} >> ${SAVE_LETTER}
    Wait For Elements State    ${LETTER_DIALOG}    visible
    Get Text    ${LETTER_DIALOG} >> css=#confirm-dialog-description    ==
    ...    Kirje tallennetaan uudeksi hakemuspohjaksi nimellä "${name}". Omat pohjasi pysyvät ennallaan.
    Get Text    ${LETTER_DIALOG} >> css=.confirm-option span    ==    Käytä tätä hakukirjeenä tässä hakemuksessa

Posted Api Paths
    [Documentation]    The API paths (after /api/) of the recorded POST requests, oldest first.
    ${requests}=    Get Recorded Requests
    ${posts}=    Evaluate    [r['url'].split('/api/', 1)[1] for r in json.loads($requests) if r['method'] == 'POST']    modules=json
    RETURN    ${posts}

Local And Ai Requests Should Have Been Attempted
    ${posts}=    Posted Api Paths
    Length Should Be    ${posts}    2    msg=Recorded POST requests: ${posts}
    Should Match Regexp    ${posts}[0]    ^conversations/[a-f0-9]{24}/answer$
    Should Be Equal    ${posts}[1]    assistant/suggest

Send Suggestion Request
    [Arguments]    ${message}=Paranna hakukirjettäni.
    Check Checkbox    ${ALLOW}
    Fill Text    ${COMPOSER}    ${message}
    Wait For Elements State    ${SEND}    enabled    timeout=15s
    Click    ${SEND}


*** Test Cases ***
Context rows are disabled when the application has no such material
    [Documentation]    TC21-001. Expected result: for an application without a CV, cover letter material or notes the
    ...    rows read "CV · ei CV:tä tällä hakemuksella", "Hakukirje · ei hakukirjettä tällä hakemuksella" and
    ...    "Muistiinpanot · ei muistiinpanoja tällä hakemuksella" and are disabled and look locked. For an application
    ...    with attached files the rows are enabled and name the files: "Valittu CV · CV-tiedosto:
    ...    robot-cv-tiedosto.txt", "Hakukirje · 2 tiedostoa" and "Tämän hakemuksen muistiinpanot". For an application
    ...    with an app CV, a template, an application text and notes they read "Valittu CV · ROBOT Kontekstin CV",
    ...    "Hakukirje · pohja ja hakemusteksti" and "Tämän hakemuksen muistiinpanot". The rows change when another
    ...    application is chosen, and a row chosen
    ...    for one application is not ticked on an application that has no such material.
    Go To Section    AI-chat
    Choose Application    ${EMPTY_APP}
    Row Should Be    ${CV_ROW}    CV · ei CV:tä tällä hakemuksella    ${False}
    Row Should Be    ${LETTER_ROW}    Hakukirje · ei hakukirjettä tällä hakemuksella    ${False}
    Row Should Be    ${NOTES_ROW}    Muistiinpanot · ei muistiinpanoja tällä hakemuksella    ${False}
    Choose Application    ${FULL}
    Row Should Be    ${CV_ROW}    Valittu CV · CV-tiedosto: robot-cv-tiedosto.txt    ${True}
    Row Should Be    ${LETTER_ROW}    Hakukirje · 2 tiedostoa    ${True}
    Get Text    ${LETTER_ROW}    contains    Yhteystiedot poistetaan ennen lähetystä.
    Row Should Be    ${NOTES_ROW}    Tämän hakemuksen muistiinpanot    ${True}
    Check Checkbox    ${CV_ROW} >> css=input
    Check Checkbox    ${LETTER_ROW} >> css=input
    Check Checkbox    ${NOTES_ROW} >> css=input
    Choose Application    ${APP_MATERIAL}
    Row Should Be    ${CV_ROW}    Valittu CV · ROBOT Kontekstin CV    ${True}
    Row Should Be    ${LETTER_ROW}    Hakukirje · pohja ja hakemusteksti    ${True}
    Row Should Be    ${NOTES_ROW}    Tämän hakemuksen muistiinpanot    ${True}
    Choose Application    ${EMPTY_APP}
    FOR    ${row}    IN    ${CV_ROW}    ${LETTER_ROW}    ${NOTES_ROW}
        Get Checkbox State    ${row} >> css=input    ==    unchecked
        Get Property    ${row} >> css=input    disabled    ==    ${True}
    END

CV and cover letter are not chosen by default
    [Documentation]    TC21-002. The privacy policy promises that choosing the CV and the cover letter is off by
    ...    default. Expected result: right after an application with a CV, cover letter files and notes is chosen,
    ...    and again after a reload, no context row is ticked (posting, CV, Hakukirje, notes, permission), and a
    ...    request sent with only the permission ticked asks for no CV, template, application text or notes.
    [Teardown]    Clear Mocked Responses
    FOR    ${round}    IN RANGE    2
        IF    ${round} == 1
            Reload
            Wait For Workspace
        END
        Go To Section    AI-chat
        Choose Application    ${FULL}
        ${states}=    Evaluate JavaScript    ${OPTIONS}    (list) => Array.from(list.querySelectorAll('input[type="checkbox"]')).map(e => e.checked)
        Should Be Equal    ${states}    ${{ [False] * 5 }}    msg=Context options ticked by default: ${states}
    END
    Mock Suggestion    Ehdotus.
    Send Suggestion Request
    Wait For Elements State    css=.assistant-message:has-text("Ehdotus.")    visible
    ${bodies}=    Get Mocked Request Bodies
    ${context}=    Evaluate    json.loads(json.loads($bodies)[-1])['context']    modules=json
    Should Be Equal    ${context}[includeCv]    ${False}
    Should Be Equal    ${context}[includeTemplate]    ${False}
    Should Be Equal    ${context}[includeApplicationText]    ${False}
    Should Be Equal    ${context}[includeApplication]    ${False}

Chosen CV and cover letter are sent as one request with every cover letter part
    [Documentation]    TC21-003. Expected result: when the CV and Hakukirje rows are ticked, the request asks for the
    ...    CV (includeCv) and for the whole cover letter material with one choice (includeTemplate and
    ...    includeApplicationText), but not for the notes, which were not ticked.
    [Teardown]    Clear Mocked Responses
    Go To Section    AI-chat
    Choose Application    ${FULL}
    Check Checkbox    ${CV_ROW} >> css=input
    Check Checkbox    ${LETTER_ROW} >> css=input
    Mock Suggestion    Ehdotus kirjeeseen.
    Send Suggestion Request
    Wait For Elements State    css=.assistant-message:has-text("Ehdotus kirjeeseen.")    visible
    ${bodies}=    Get Mocked Request Bodies
    ${context}=    Evaluate    json.loads(json.loads($bodies)[-1])['context']    modules=json
    Should Be Equal    ${context}[includeCv]    ${True}
    Should Be Equal    ${context}[includeTemplate]    ${True}
    Should Be Equal    ${context}[includeApplicationText]    ${True}
    Should Be Equal    ${context}[includeApplication]    ${False}

AI answer markdown is formatted safely and notices are shown with the answer
    [Documentation]    TC21-004. The suggest answer is mocked. Expected result: a heading (###), bold, italic and a
    ...    bullet list are shown formatted (h4, strong, em, two li items) and no raw "**" or "###" is visible; an
    ...    http(s) link becomes a link that opens in a new tab with rel noopener; a javascript: link, a <script> and
    ...    an <img onerror> are shown as plain text and never run; the user's own message stays plain text; the
    ...    Finnish notices of the answer are shown under it.
    [Teardown]    Clear Mocked Responses
    ${markdown}=    Catenate    SEPARATOR=\n
    # A cell that starts with # is a comment in Robot, so the heading marks are escaped.
    ...    \### Ehdotettu otsikko
    ...    ${EMPTY}
    ...    Tämä on **tärkeä** kohta ja *kursiivi* sana.
    ...    ${EMPTY}
    ...    - Ensimmäinen kohta
    ...    - Toinen kohta
    ...    ${EMPTY}
    # One __ per line, so the markers are not read as __bold__.
    ...    <script>window.__xss=1</script>
    ...    <img src=x onerror="window.__xss=2">
    ...    [Klikkaa tästä](javascript:window.__xss=3) ja [ohje](https://example.com/ohje)
    Mock Suggestion    ${markdown}    Tiedoston robot-hakukirje.txt teksti lyhennettiin: AI:lle lähetettiin ensimmäiset 8 000 merkkiä.
    Go To Section    AI-chat
    Choose Application    ${FULL}
    Send Suggestion Request    Paranna **tätä** tekstiä.
    ${answer}=    Set Variable    css=.assistant-message:has(.markdown-text) >> nth=-1
    Wait For Elements State    ${answer}    visible
    Get Text    ${answer} >> css=.markdown-text h4    ==    Ehdotettu otsikko
    Get Text    ${answer} >> css=.markdown-text strong    ==    tärkeä
    Get Text    ${answer} >> css=.markdown-text em    ==    kursiivi
    Get Element Count    ${answer} >> css=.markdown-text ul > li    ==    2
    Get Text    ${answer} >> css=.markdown-text ul > li >> nth=0    ==    Ensimmäinen kohta
    ${text}=    Get Text    ${answer} >> css=.markdown-text
    Should Not Contain    ${text}    **
    Should Not Contain    ${text}    \###
    Should Contain    ${text}    <script>window.__xss=1</script>
    Should Contain    ${text}    Klikkaa tästä (javascript:window.__xss=3)
    Get Element Count    css=.chat-messages script    ==    0
    Get Element Count    css=.chat-messages img    ==    0
    Get Element Count    css=.chat-messages a[href^="javascript"]    ==    0
    Get Attribute    ${answer} >> css=.markdown-text a    href    ==    https://example.com/ohje
    Get Attribute    ${answer} >> css=.markdown-text a    target    ==    _blank
    Get Attribute    ${answer} >> css=.markdown-text a    rel    contains    noopener
    Get Text    css=.user-message >> nth=-1 >> css=p    ==    Paranna **tätä** tekstiä.
    ${notice}=    Get Text    ${answer} >> css=.assistant-notice
    ${notice}=    Evaluate    $notice.replace(chr(0xa0), ' ')
    Should Be Equal    ${notice}    Tiedoston robot-hakukirje.txt teksti lyhennettiin: AI:lle lähetettiin ensimmäiset 8 000 merkkiä.
    Click    ${answer} >> text=Klikkaa tästä
    Script Marker Should Be Unset

AI cover letter is saved as a new template and becomes the application's cover letter
    [Documentation]    TC21-005. The suggest answer is mocked with a reply and a separate letter. Expected result:
    ...    under the reply there is "Tallenna uudeksi hakukirjeeksi" and the hint "Tarkista kirje ja tallenna se
    ...    uudeksi hakukirjeeksi painikkeella." (not the copy hint). The button opens "Tallennetaanko uusi
    ...    hakukirje?" naming the template "<company> · <role> (AI pp.kk.vvvv)", with "Käytä tätä hakukirjeenä
    ...    tässä hakemuksessa" ticked and enabled and a warning about the one place left in brackets; nothing is
    ...    saved before "Tallenna". After it the reply says "Hakukirje tallennettu pohjaksi <name>. Se on nyt
    ...    tämän hakemuksen hakukirje."; the new template has the letter with [Yhteystietosi] removed and
    ...    [Nimesi] as {{nimi}} and the name and contact details of the application's old template; the
    ...    application now has the new template while its application text and the old template are unchanged.
    ...    Saving the same letter again creates "<name> 2", which becomes the application's cover letter. Both
    ...    templates are listed in CV & pohjat and the details offer "Tulosta hakukirje: <name> 2".
    [Tags]    ai-letter
    [Teardown]    Clear Mocked Responses
    ${old}=    Create Template As    A    name=ROBOT Kirjeen vanha pohja    fullName=${PERSON}
    ...    email=${PERSON_EMAIL}    phone=${PERSON_PHONE}    body=Vanha hakukirje.
    Create Application As    A    company=${LETTER_APP}    role=Testaaja    templateId=${old}[id]
    ...    applicationText=Oma hakemusteksti.
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Choose Application    ${LETTER_APP}
    Mock Suggestion With Letter    Tässä muokattu hakukirje:\n\n${AI_LETTER}    ${AI_LETTER}
    Send Suggestion Request    Kirjoita hakukirje tähän hakemukseen.
    ${answer}=    Answer With Text    Tässä muokattu hakukirje
    Wait For Elements State    ${answer} >> ${SAVE_LETTER}    visible
    Get Element Count    ${answer} >> small:text-is("${LETTER_HINT}")    ==    1
    Get Element Count    ${answer} >> small:text-is("${COPY_HINT}")    ==    0
    ${date}=    Helsinki Date Label
    ${name}=    Set Variable    ${LETTER_APP} · Testaaja (AI ${date})
    ${before}=    Api Request    GET    /api/templates    user=A
    Save Letter From    ${answer}    ${name}
    Get Checkbox State    ${LETTER_DIALOG} >> css=.confirm-option input    ==    checked
    Get Property    ${LETTER_DIALOG} >> css=.confirm-option input    disabled    ==    ${False}
    Get Element Count    ${LETTER_DIALOG} >> css=.confirm-option.is-disabled    ==    0
    Get Text    ${LETTER_DIALOG} >> css=.confirm-warning    ==
    ...    Kirjeessä on vielä täydennettäviä kohtia hakasulkeissa (1 kpl). Voit täydentää ne CV & pohjat -sivulla.
    ${waiting}=    Api Request    GET    /api/templates    user=A
    Length Should Be    ${waiting.json}    ${{ len($before.json) }}    msg=A template was saved before the confirmation
    Click    ${LETTER_DIALOG} >> css=button.confirm-primary:text-is("Tallenna")
    Wait For Elements State    ${LETTER_DIALOG}    detached
    Wait For Elements State
    ...    ${answer} >> small[role="status"]:text-is("Hakukirje tallennettu pohjaksi ${name}. Se on nyt tämän hakemuksen hakukirje.")
    ...    visible
    ${first}=    Template Named    ${name}
    Should Be Equal    ${first}[body]    ${LETTER_BODY}
    Should Be Equal    ${first}[fullName]    ${PERSON}
    Should Be Equal    ${first}[email]    ${PERSON_EMAIL}
    Should Be Equal    ${first}[phone]    ${PERSON_PHONE}
    ${kept}=    Template Named    ROBOT Kirjeen vanha pohja
    Should Be Equal    ${kept}[body]    Vanha hakukirje.
    ${app}=    Application Named    ${LETTER_APP}
    Should Be Equal    ${app}[templateId]    ${first}[id]
    Should Be Equal    ${app}[applicationText]    Oma hakemusteksti.
    Save Letter From    ${answer}    ${name} 2
    Click    ${LETTER_DIALOG} >> css=button.confirm-primary:text-is("Tallenna")
    Wait For Elements State    ${LETTER_DIALOG}    detached
    Wait For Elements State
    ...    ${answer} >> small[role="status"]:text-is("Hakukirje tallennettu pohjaksi ${name} 2. Se on nyt tämän hakemuksen hakukirje.")
    ...    visible
    ${second}=    Template Named    ${name} 2
    Should Be Equal    ${second}[body]    ${LETTER_BODY}
    ${first_again}=    Template Named    ${name}
    Should Be Equal    ${first_again}[body]    ${LETTER_BODY}
    ${app}=    Application Named    ${LETTER_APP}
    Should Be Equal    ${app}[templateId]    ${second}[id]
    Should Be Equal    ${app}[applicationText]    Oma hakemusteksti.
    ${kept}=    Template Named    ROBOT Kirjeen vanha pohja
    Should Be Equal    ${kept}[body]    Vanha hakukirje.
    Go To Section    CV & pohjat
    Get Element Count    css=.template-card:has-text("${name}")    ==    2
    Wait For Elements State    css=.template-card:has-text("${name} 2")    visible
    Go To Section    Hakemukset
    Click    css=.job-row:has-text("${LETTER_APP}") >> button:text-is("Tiedot")
    Wait For Elements State    css=.detail-document:has-text("Tulosta hakukirje: ${name} 2")    visible
    Click    css=.detail-card >> button:text-is("Sulje")

Save button is offered only for a reply with a letter while AI suggestions are allowed
    [Documentation]    TC21-006. Expected result: a mocked reply without a letter (letter "") has no "Tallenna
    ...    uudeksi hakukirjeeksi" button and shows the copy hint "Voit kopioida ehdotuksen ja hyväksyä muokkauksen
    ...    itse hakemuksessa.". A reply with a letter has the button; when "AI saa ehdottaa muutoksia" is unticked
    ...    the button disappears and the copy hint is shown instead, and it comes back when the option is ticked
    ...    again.
    [Tags]    ai-letter
    [Teardown]    Clear Mocked Responses
    Go To Section    AI-chat
    Choose Application    ${APP_MATERIAL}
    Mock Suggestion With Letter    Arvio: CV vastaa ilmoitusta hyvin.    ${EMPTY}
    Send Suggestion Request    Arvioi CV:ni tätä hakemusta varten.
    ${review}=    Answer With Text    Arvio: CV vastaa ilmoitusta hyvin.
    Wait For Elements State    ${review}    visible
    Get Element Count    ${review} >> ${SAVE_LETTER}    ==    0
    Get Element Count    ${review} >> small:text-is("${COPY_HINT}")    ==    1
    Clear Mocked Responses
    Mock Suggestion With Letter    Uusi kirje:\n\n${PLAIN_LETTER}    ${PLAIN_LETTER}
    Send Suggestion Request    Kirjoita hakukirje.
    ${letter}=    Answer With Text    Uusi kirje:
    Wait For Elements State    ${letter} >> ${SAVE_LETTER}    visible
    Uncheck Checkbox    ${ALLOW}
    Wait For Elements State    ${letter} >> ${SAVE_LETTER}    detached
    Get Element Count    ${letter} >> small:text-is("${COPY_HINT}")    ==    1
    Get Element Count    ${letter} >> small:text-is("${LETTER_HINT}")    ==    0
    Check Checkbox    ${ALLOW}
    Wait For Elements State    ${letter} >> ${SAVE_LETTER}    visible
    Get Element Count    ${review} >> ${SAVE_LETTER}    ==    0

An application with a cover letter file keeps it and gets the saved letter only as a new template
    [Documentation]    TC21-007. The application has an attached cover letter file. Expected result: in the
    ...    confirmation "Käytä tätä hakukirjeenä tässä hakemuksessa" is unticked, disabled and greyed out
    ...    (is-disabled, opacity 0.65) and the note says that the file stays attached and the new template is in
    ...    CV & pohjat; the letter has no place left in brackets, so there is no warning. "Tallenna" saves the
    ...    template ("Hakukirje tallennettu pohjaksi <name>." without "Se on nyt…") and the application keeps
    ...    its file and gets no template.
    [Tags]    ai-letter
    [Teardown]    Clear Mocked Responses
    ${file}=    Upload Text File As    A    application    robot-kirjetiedosto.txt    Liitetty hakukirje
    Create Application As    A    company=${FILE_APP}    role=Kehittäjä    applicationFileIds=${{ [$file['id']] }}
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Choose Application    ${FILE_APP}
    Mock Suggestion With Letter    Kirje kehittäjän tehtävään:\n\n${PLAIN_LETTER}    ${PLAIN_LETTER}
    Send Suggestion Request    Kirjoita hakukirje.
    ${answer}=    Answer With Text    Kirje kehittäjän tehtävään:
    Wait For Elements State    ${answer} >> ${SAVE_LETTER}    visible
    ${date}=    Helsinki Date Label
    ${name}=    Set Variable    ${FILE_APP} · Kehittäjä (AI ${date})
    Save Letter From    ${answer}    ${name}
    Get Checkbox State    ${LETTER_DIALOG} >> css=.confirm-option input    ==    unchecked
    Get Property    ${LETTER_DIALOG} >> css=.confirm-option input    disabled    ==    ${True}
    Get Element Count    ${LETTER_DIALOG} >> css=label.confirm-option.is-disabled    ==    1
    ${opacity}=    Evaluate JavaScript    ${LETTER_DIALOG} >> css=.confirm-option    (label) => getComputedStyle(label).opacity
    Should Be Equal As Numbers    ${opacity}    0.65    msg=The disabled choice is not greyed out (opacity ${opacity})
    Get Text    ${LETTER_DIALOG} >> css=.confirm-note    ==
    ...    Hakemukseen on liitetty hakukirjetiedosto, joten pohjaa ei voi valita sen rinnalle. Tiedosto pysyy liitettynä, ja uuden pohjan löydät CV & pohjat -sivulta.
    Get Element Count    ${LETTER_DIALOG} >> css=.confirm-warning    ==    0
    Click    ${LETTER_DIALOG} >> css=button.confirm-primary:text-is("Tallenna")
    Wait For Elements State    ${LETTER_DIALOG}    detached
    Wait For Elements State    ${answer} >> small[role="status"]:text-is("Hakukirje tallennettu pohjaksi ${name}.")    visible
    Get Element Count    ${answer} >> css=.assistant-letter-error    ==    0
    ${saved}=    Template Named    ${name}
    Should Be Equal    ${saved}[body]    Hei,\n\nHaen kehittäjän tehtävää yrityksessänne.\n\nYstävällisin terveisin,\n{{nimi}}
    ${app}=    Application Named    ${FILE_APP}
    Should Be Equal    ${app}[templateId]    ${EMPTY}
    Should Be Equal    ${app}[applicationFileIds]    ${{ [$file['id']] }}

A timed-out AI request shows the Finnish timeout message
    [Documentation]    TC21-008. The suggest answer is mocked as the backend's timeout answer (504 with its
    ...    message). Expected result: the chat shows "AI-vastaus kesti liian kauan. Yritä uudelleen tai pyydä
    ...    lyhyempi vastaus, esimerkiksi ensin pelkkä arvio ja sitten hakukirje erikseen.", the message stays in
    ...    the field for a new try and no message pair is added to the chat. The backend's own 504 mapping is
    ...    covered by its unit tests (TC22-001).
    [Tags]    ai-letter
    [Teardown]    Clear Mocked Responses
    ${body}=    Evaluate    json.dumps({'error': $TIMEOUT_ERROR})    modules=json
    Mock Json Response    **/api/assistant/suggest    504    ${body}
    Go To Section    AI-chat
    Choose Application    ${APP_MATERIAL}
    Send Suggestion Request    Kirjoita pitkä arvio ja hakukirje.
    Wait For Elements State    ${CHAT_ERROR}    visible
    Get Text    ${CHAT_ERROR}    ==    ${TIMEOUT_ERROR}
    Get Property    ${COMPOSER}    value    ==    Kirjoita pitkä arvio ja hakukirje.
    Get Element Count    css=.user-message:has-text("Kirjoita pitkä arvio ja hakukirje.")    ==    0

Short questions about the application are answered locally and can be sent to the AI
    [Documentation]    TC21-009. AI suggestions are allowed and the suggest answer is mocked. Expected result:
    ...    "Mikä on hakemuksen tila?" goes only to the local answer route, the answer shows "Tila: Lähetetty", the
    ...    note "Vastaus haettiin hakemuksen tiedoista. Jos tarkoitit viestin työparille, lähetä se AI:lle." and the
    ...    button "Lähetä AI:lle" (no copy hint). The button sends the same question to /api/assistant/suggest
    ...    for this application and the AI reply is shown; with AI suggestions off the button is not offered.
    ...    The editing request "muokkaa hakukirjettä: korosta motivaatiotani tehtävässä kehittymiselle ja
    ...    testausosaamistani" mentions the role (tehtävä) but asks for an edit, so it goes only to the AI.
    [Tags]    local-question
    [Teardown]    Run Keywords    Clear Mocked Responses    AND    Stop Recording Requests
    ${app}=    Create Application As    A    company=ROBOT Paikallinen Oy    status=Lähetetty
    Reload
    Wait For Workspace
    Go To Section    AI-chat
    Choose Application    ROBOT Paikallinen Oy
    Check Checkbox    ${ALLOW}
    Mock Suggestion    AI:n vastaus tilakysymykseen.
    Fill Text    ${COMPOSER}    Mikä on hakemuksen tila?
    Wait For Elements State    ${SEND}    enabled    timeout=15s
    Start Recording Requests    /api/
    Click    ${SEND}
    ${local}=    Answer With Text    Tila: Lähetetty
    Wait For Elements State    ${local}    visible
    Get Element Count    ${local} >> small:text-is("${LOCAL_HINT}")    ==    1
    Get Element Count    ${local} >> small:text-is("${COPY_HINT}")    ==    0
    Wait For Elements State    ${local} >> button:text-is("Lähetä AI:lle")    enabled
    ${posts}=    Posted Api Paths
    Should Be Equal    ${posts}    ${{ ['conversations/' + $app['id'] + '/answer'] }}
    Click    ${local} >> button:text-is("Lähetä AI:lle")
    Wait For Elements State    ${ANSWERS}:has-text("AI:n vastaus tilakysymykseen.")    visible
    ${posts}=    Posted Api Paths
    Should Be Equal    ${posts}    ${{ ['conversations/' + $app['id'] + '/answer', 'assistant/suggest'] }}
    ${bodies}=    Get Mocked Request Bodies
    ${sent}=    Evaluate    json.loads(json.loads($bodies)[-1])    modules=json
    Should Be Equal    ${sent}[message]    Mikä on hakemuksen tila?
    Should Be Equal    ${sent}[context][applicationId]    ${app}[id]
    Get Element Count    css=.user-message:has-text("Mikä on hakemuksen tila?")    ==    2
    Uncheck Checkbox    ${ALLOW}
    Wait For Elements State    ${local} >> button:text-is("Lähetä AI:lle")    detached
    Check Checkbox    ${ALLOW}
    Clear Mocked Responses
    Mock Suggestion    AI:n ehdotus hakukirjeeseen.
    ${edit}=    Set Variable    muokkaa hakukirjettä: korosta motivaatiotani tehtävässä kehittymiselle ja testausosaamistani
    Fill Text    ${COMPOSER}    ${edit}
    Wait For Elements State    ${SEND}    enabled    timeout=15s
    Start Recording Requests    /api/
    Click    ${SEND}
    Wait For Elements State    ${ANSWERS}:has-text("AI:n ehdotus hakukirjeeseen.")    visible
    ${posts}=    Posted Api Paths
    Should Be Equal    ${posts}    ${{ ['assistant/suggest'] }}
    ${bodies}=    Get Mocked Request Bodies
    ${sent}=    Evaluate    json.loads(json.loads($bodies)[-1])    modules=json
    Should Be Equal    ${sent}[message]    ${edit}

A request that never reaches the server shows a Finnish connection error
    [Documentation]    TC21-010. The API requests are made to fail at the network level (Abort Requests, as when
    ...    the connection is down), so fetch rejects with the browser's "Failed to fetch". Expected result: both a
    ...    local question (POST /api/conversations/:id/answer) and an AI request (POST /api/assistant/suggest)
    ...    were attempted and the chat shows "Palvelimeen ei saatu yhteyttä. Tarkista verkkoyhteys ja yritä
    ...    uudelleen." instead of "Failed to fetch".
    [Tags]    connection-error
    [Teardown]    Run Keywords    Clear Mocked Responses    AND    Stop Recording Requests
    Go To Section    AI-chat
    Choose Application    ${APP_MATERIAL}
    Fill Text    ${COMPOSER}    Mikä on hakemuksen tila?
    Wait For Elements State    ${SEND}    enabled    timeout=15s
    Abort Requests    **/api/conversations/**
    Abort Requests    **/api/assistant/suggest
    Start Recording Requests    /api/
    Click    ${SEND}
    Wait For Elements State    ${CHAT_ERROR}    visible
    Get Text    ${CHAT_ERROR}    ==    ${OFFLINE_ERROR}
    Send Suggestion Request    Paranna hakukirjettäni.
    Wait Until Keyword Succeeds    10s    250ms    Local And Ai Requests Should Have Been Attempted
    Get Text    ${CHAT_ERROR}    ==    ${OFFLINE_ERROR}
    Get Element Count    css=.user-message:has-text("Paranna hakukirjettäni.")    ==    0
    Get Text    css=.assistant-chat    not contains    Failed to fetch
