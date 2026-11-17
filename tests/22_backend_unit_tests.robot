*** Settings ***
Documentation     Runs the application's own unit tests (node --test in the backend and frontend folders of
...               APP_DIR) as Robot tests. The backend tests cover, among other things, the removal of names, e-mail
...               addresses, phone numbers, postal addresses and web addresses from the texts sent to the AI, the
...               structured AI reply (reply and letter, plain text without a letter), the 504 timeout answer, the
...               conversation history and saving a cover letter as a template. The frontend tests cover the choice
...               between a local answer and the AI, the event types and the cover letter template. No server,
...               browser or OpenAI call is needed.
Resource          ../resources/common.robot
Library           Process
Force Tags        unit    backend


*** Test Cases ***
Backend unit tests pass
    [Documentation]    TC22-001. Expected result: "node --test" in the backend folder exits with code 0, at least one
    ...    unit test is run and none fails, is cancelled or is left as a todo. The output of node is written to the log.
    Require Config    APP_DIR
    ${backend}=    Normalize Path    ${APP_DIR}${/}backend
    Directory Should Exist    ${backend}    msg=No backend folder at ${backend}. Set APP_DIR in .env.
    ${result}=    Run Process    node    --test    cwd=${backend}    timeout=300s    stderr=STDOUT
    Log    ${result.stdout}
    ${summary}=    Evaluate    dict(re.findall(r'^\\S*\\s*(tests|pass|fail|cancelled|todo) (\\d+)\\s*$', $result.stdout, re.M))    modules=re
    Log    ${summary}
    Should Be Equal As Integers    ${result.rc}    0    msg=Backend unit tests failed (exit code ${result.rc}):\n${result.stdout}[-3000:]
    Should Be True    int($summary.get('tests', 0)) > 0    msg=node --test ran no unit tests:\n${result.stdout}[-2000:]
    Should Be Equal As Integers    ${summary.get('fail', -1)}    0    msg=Failed unit tests:\n${result.stdout}[-3000:]
    Should Be Equal As Integers    ${summary.get('cancelled', 0)}    0
    Should Be Equal As Integers    ${summary.get('todo', 0)}    0

Frontend unit tests pass
    [Documentation]    TC22-002. Expected result: "node --test src/utils" in the frontend folder (the command the
    ...    test files name) exits with code 0, at least one unit test is run and none fails, is cancelled or is
    ...    left as a todo. They cover applicationQuestion.js (local answer or AI), the event types and
    ...    letterTemplate.js (name and body of a cover letter template). The output of node is written to the log.
    [Tags]    frontend
    Require Config    APP_DIR
    ${frontend}=    Normalize Path    ${APP_DIR}${/}frontend
    Directory Should Exist    ${frontend}    msg=No frontend folder at ${frontend}. Check APP_DIR.
    ${result}=    Run Process    node    --test    src/utils    cwd=${frontend}    timeout=300s    stderr=STDOUT
    Log    ${result.stdout}
    ${summary}=    Evaluate    dict(re.findall(r'^\\S*\\s*(tests|pass|fail|cancelled|todo) (\\d+)\\s*$', $result.stdout, re.M))    modules=re
    Log    ${summary}
    Should Be Equal As Integers    ${result.rc}    0    msg=Frontend unit tests failed (exit code ${result.rc}):\n${result.stdout}[-3000:]
    Should Be True    int($summary.get('tests', 0)) > 0    msg=node --test ran no unit tests:\n${result.stdout}[-2000:]
    Should Be Equal As Integers    ${summary.get('fail', -1)}    0    msg=Failed unit tests:\n${result.stdout}[-3000:]
    Should Be Equal As Integers    ${summary.get('cancelled', 0)}    0
    Should Be Equal As Integers    ${summary.get('todo', 0)}    0
