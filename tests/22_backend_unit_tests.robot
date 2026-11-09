*** Settings ***
Documentation     Runs the backend's own unit tests (node --test in the backend folder of APP_DIR) as one Robot
...               test. They cover the removal of names, e-mail addresses, phone numbers, postal addresses and web
...               addresses from the texts sent to the AI (backend/utils/redactContactDetails.test.js). No server,
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
