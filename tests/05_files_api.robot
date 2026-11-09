*** Settings ***
Documentation     File library API: upload validation, safe download, filename handling and size limits.
...               Valid uploads use test user A. Invalid-upload attempts use test user B, because
...               every attempt (even a rejected one) counts toward the 30 uploads per hour limit.
Resource          ../resources/common.robot
Suite Setup       Prepare API Suite
Suite Teardown    Finish API Suite
Force Tags        api    files


*** Test Cases ***
Text file can be uploaded, listed and downloaded unchanged
    [Documentation]    TC05-001. Expected result: Text file can be uploaded, listed and downloaded unchanged.
    ${content}=    Make Text    Rivi 1\nRivi 2 äö
    ${upload}=    Upload File    A    cv    ${PREFIX}-roundtrip.txt    ${content}    text/plain
    Status Should Be    ${upload}    201
    Should Be Equal    ${upload.json}[category]    cv
    Should Be Equal    ${upload.json}[name]    ${PREFIX}-roundtrip.txt
    Should Start With    ${upload.json}[mimeType]    text/plain
    Should Be Equal As Integers    ${upload.json}[size]    ${{ len($content) }}
    Dictionary Should Not Contain Key    ${upload.json}    data
    Dictionary Should Not Contain Key    ${upload.json}    userId
    ${list}=    Api Request    GET    /api/files    user=A
    ${ids}=    Ids Of    ${list}
    Should Contain    ${ids}    ${upload.json}[id]
    Should Not Contain    ${list.text}    "data"
    ${download}=    Api Request    GET    /api/files/${upload.json}[id]/download    user=A
    Status Should Be    ${download}    200
    Should Be Equal    ${download.content}    ${content}

PDF and DOCX files are accepted with the correct MIME types
    [Documentation]    TC05-002. Expected result: PDF and DOCX files are accepted with the correct MIME types.
    ${pdf}=    Make Pdf
    ${response}=    Upload File    A    application    ${PREFIX}-letter.pdf    ${pdf}    application/pdf
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[mimeType]    application/pdf
    Should Be Equal    ${response.json}[category]    application
    ${docx}=    Make Docx
    ${response}=    Upload File    A    cv    ${PREFIX}-cv.docx    ${docx}    application/octet-stream
    Status Should Be    ${response}    201
    Should Contain    ${response.json}[mimeType]    wordprocessingml

Download response carries safe headers
    [Documentation]    TC05-003. Expected result: Download response carries safe headers.
    ${file}=    Upload Text File As    A    cv    ${PREFIX}-headers.txt
    ${download}=    Api Request    GET    /api/files/${file}[id]/download    user=A
    Status Should Be    ${download}    200
    Should Be Equal    ${download.header('X-Content-Type-Options')}    nosniff
    Should Start With    ${download.header('Content-Disposition')}    attachment
    Should Contain    ${download.header('Cache-Control')}    no-store
    Should Contain    ${download.header('Cache-Control')}    private
    Should Be Equal As Integers    ${download.header('Content-Length')}    ${file}[size]

Only PDF, DOCX and TXT files are accepted
    [Documentation]    TC05-004. Expected result: Only PDF, DOCX and TXT files are accepted.
    ${bytes}=    Make Text    harmless
    FOR    ${name}    ${type}    IN
    ...    ${PREFIX}.exe    application/x-msdownload
    ...    ${PREFIX}.html    text/html
    ...    ${PREFIX}.svg    image/svg+xml
    ...    ${PREFIX}.js    text/javascript
    ...    ${PREFIX}.pdf.exe    application/pdf
    ...    ${PREFIX}.php    text/plain
    ...    ${PREFIX}-noextension    text/plain
        ${response}=    Upload File    B    cv    ${name}    ${bytes}    ${type}
        Status Should Be    ${response}    400
        Error Response Should Be Safe    ${response}
    END

File content must match the extension
    [Documentation]    TC05-005. Expected result: File content must match the extension.
    ${text}=    Make Text    this is not a pdf
    ${fake_pdf}=    Upload File    B    cv    ${PREFIX}-fake.pdf    ${text}    application/pdf
    Status Should Be    ${fake_pdf}    400
    ${fake_docx}=    Upload File    B    cv    ${PREFIX}-fake.docx    ${text}    application/octet-stream
    Status Should Be    ${fake_docx}    400
    ${html_as_txt_with_null}=    Make Bytes    5    ${{ b'\x00' }}
    ${null_txt}=    Upload File    B    cv    ${PREFIX}-null.txt    ${html_as_txt_with_null}    text/plain
    Status Should Be    ${null_txt}    400
    # Byte values are listed as numbers: Robot would turn "\xff" escapes into characters
    # before Python sees them, and a bytes literal cannot contain non-ASCII characters.
    ${latin1}=    Evaluate    bytes([0xff, 0xfe, 0xfa, 0xfb])
    ${bad_utf8}=    Upload File    B    cv    ${PREFIX}-latin1.txt    ${latin1}    text/plain
    Status Should Be    ${bad_utf8}    400

Empty file and missing file are rejected
    [Documentation]    TC05-006. Expected result: Empty file and missing file are rejected.
    ${empty}=    Upload File    B    cv    ${PREFIX}-empty.txt    ${EMPTY}    text/plain
    Status Should Be    ${empty}    400
    ${no_file}=    Api Request    POST    /api/files    user=B    form=${{ {'category': 'cv'} }}
    Status Should Be    ${no_file}    400

Category must be cv or application
    [Documentation]    TC05-007. Expected result: Category must be cv or application.
    ${bytes}=    Make Text    ok
    FOR    ${category}    IN    ${None}    ${EMPTY}    admin    CV    {"$ne":null}    cv,application
        ${response}=    Upload File    B    ${category}    ${PREFIX}-cat.txt    ${bytes}    text/plain
        Status Should Be    ${response}    400
    END

Path traversal in the filename is neutralised
    [Documentation]    TC05-008. Expected result: Path traversal in the filename is neutralised.
    ${bytes}=    Make Text    ok
    FOR    ${name}    IN    ../../etc/passwd.txt    ..\\..\\windows\\win.txt    /absolute/path.txt    a/b\\c.txt
        ${response}=    Upload File    A    cv    ${name}    ${bytes}    text/plain
        Status Should Be    ${response}    201
        Should Not Contain    ${response.json}[name]    /
        Should Not Contain    ${response.json}[name]    \\
        ${download}=    Api Request    GET    /api/files/${response.json}[id]/download    user=A
        Should Not Contain    ${download.header('Content-Disposition')}    ..${/}
        Status Should Be    ${download}    200
    END

Header injection through the filename is impossible
    [Documentation]    TC05-009. Expected result: Header injection through the filename is impossible.
    ${bytes}=    Make Text    ok
    ${name}=    Set Variable    evil"\r\nX-Injected: yes.txt
    ${response}=    Upload File    A    cv    ${name}    ${bytes}    text/plain
    Status Should Be One Of    ${response}    201    400
    IF    ${response.status} == 201
        # CR and LF are what would split the header, so they must be gone from the stored name.
        # A quote is a legal file name character and React shows it as text; it is only dangerous
        # inside the quoted filename="..." of the download header, which is checked below.
        Should Not Contain Any    ${response.json}[name]    \r    \n
        ${download}=    Api Request    GET    /api/files/${response.json}[id]/download    user=A
        Status Should Be    ${download}    200
        Should Be Empty    ${download.header('X-Injected')}
        ${disposition}=    Set Variable    ${download.header('Content-Disposition')}
        Should Not Contain Any    ${disposition}    \r    \n
        Should Match Regexp    ${disposition}    ^attachment; filename="[^"\\\\]*"; filename\\*=UTF-8''[^";\\s]+$
        ...    msg=Quote or backslash breaks out of the quoted file name: ${disposition}
    END

HTML in the filename is stored as plain text
    [Documentation]    TC05-010. Expected result: HTML in the filename is stored as plain text.
    ${bytes}=    Make Text    ok
    ${name}=    Set Variable    <img src=x onerror=alert(1)>.txt
    ${response}=    Upload File    A    cv    ${name}    ${bytes}    text/plain
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[name]    ${name}
    ${list}=    Api Request    GET    /api/files    user=A
    Should Contain    ${list.header('Content-Type')}    application/json
    Should Be Equal    ${list.header('X-Content-Type-Options')}    nosniff

Unicode filenames keep their characters
    [Documentation]    TC05-011. Expected result: Unicode file names (for example CV_Mäkinen.pdf) come back
    ...                exactly as sent, and the download header carries the UTF-8 name (filename*).
    ...                A garbled name means the multipart parser uses the wrong character set
    ...                (multer defParamCharset).
    ${bytes}=    Make Text    ok
    ${response}=    Upload File    A    cv    CV Mäkinen Åke ✓.txt    ${bytes}    text/plain
    Status Should Be    ${response}    201
    Should Be Equal    ${response.json}[name]    CV Mäkinen Åke ✓.txt
    ${download}=    Api Request    GET    /api/files/${response.json}[id]/download    user=A
    Should Contain    ${download.header('Content-Disposition')}    filename*=UTF-8''

Very long filenames are shortened to 180 characters
    [Documentation]    TC05-012. Expected result: Very long filenames are shortened to 180 characters.
    ${bytes}=    Make Text    ok
    ${name}=    Evaluate    'a' * 300 + '.txt'
    ${response}=    Upload File    A    cv    ${name}    ${bytes}    text/plain
    Status Should Be One Of    ${response}    201    400
    IF    ${response.status} == 201
        Should Be True    len($response.json['name']) <= 180
    END

File of exactly 10 MB is accepted and 10 MB plus one byte is rejected
    [Documentation]    TC05-013. Expected result: File of exactly 10 MB is accepted and 10 MB plus one byte is rejected.
    ${limit}=    Evaluate    10 * 1024 * 1024
    ${exact}=    Make Bytes    ${limit}
    ${ok}=    Upload File    A    cv    ${PREFIX}-10mb.txt    ${exact}    text/plain    retry_429=${False}
    Status Should Be    ${ok}    201
    ${too_big}=    Make Bytes    ${limit + 1}
    ${rejected}=    Upload File    B    cv    ${PREFIX}-over.txt    ${too_big}    text/plain
    Status Should Be    ${rejected}    413
    Error Response Should Be Safe    ${rejected}
    Should Contain    ${rejected.json}[error]    10 Mt
    ${delete}=    Api Request    DELETE    /api/files/${ok.json}[id]    user=A
    Status Should Be    ${delete}    204

File can be deleted and is then gone
    [Documentation]    TC05-014. Expected result: File can be deleted and is then gone.
    ${file}=    Upload Text File As    A    cv    ${PREFIX}-delete.txt
    ${delete}=    Api Request    DELETE    /api/files/${file}[id]    user=A
    Status Should Be    ${delete}    204
    ${download}=    Api Request    GET    /api/files/${file}[id]/download    user=A
    Status Should Be    ${download}    404
    ${again}=    Api Request    DELETE    /api/files/${file}[id]    user=A
    Status Should Be    ${again}    404

Malformed and missing file ids are handled safely
    [Documentation]    TC05-015. Expected result: Malformed and missing file ids are handled safely.
    FOR    ${bad}    IN    abc    123    %24ne    ..%2F..%2Fetc%2Fpasswd    ${MISSING_ID}0
        ${download}=    Api Request    GET    /api/files/${bad}/download    user=A
        Status Should Be    ${download}    400
        ${delete}=    Api Request    DELETE    /api/files/${bad}    user=A
        Status Should Be    ${delete}    400
    END
    ${missing}=    Api Request    GET    /api/files/${MISSING_ID}/download    user=A
    Status Should Be    ${missing}    404

Upload request with several files or extra fields does not crash the server
    [Documentation]    TC05-016. Expected result: Upload request with several files or extra fields does not crash the server.
    ${response}=    Api Request    POST    /api/files    user=B    form=${{ {'category': 'cv', 'extra': 'x', 'more': 'y'} }}
    ...    files=${{ [('file', ('a.txt', b'one', 'text/plain')), ('file', ('b.txt', b'two', 'text/plain'))] }}
    Should Be True    ${response.status} < 500    msg=Server error on a malformed multipart upload: ${response.text}
    ${health}=    Api Request    GET    /api/health
    Status Should Be    ${health}    200

Library limit of 50 MB per user is enforced
    [Documentation]    TC05-017. Uploads five 10 MB files and then one more, so it only runs when RUN_SLOW=true.
    [Tags]    slow
    Skip If    not ${RUN_SLOW}    Set RUN_SLOW=true in .env to run the quota test.
    Clean Up User A
    ${limit}=    Evaluate    10 * 1024 * 1024
    ${block}=    Make Bytes    ${limit}
    FOR    ${index}    IN RANGE    5
        ${response}=    Upload File    A    cv    ${PREFIX}-quota-${index}.txt    ${block}    text/plain    retry_429=${False}
        Status Should Be    ${response}    201
    END
    ${one_more}=    Make Text    one more
    ${over}=    Upload File    A    cv    ${PREFIX}-quota-over.txt    ${one_more}    text/plain    retry_429=${False}
    Status Should Be    ${over}    413
    [Teardown]    Clean Up User A
