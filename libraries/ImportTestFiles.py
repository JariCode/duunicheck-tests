"""Builds the test files of the file import tests (POST /api/assistant/import-applications).

Every file is generated in code from invented data, so no real job search data is ever stored in
the repository. The builders return bytes; write_import_file() also stores a copy in the gitignored
tmp/import-files/ folder, which the browser tests use for uploads and which helps when a test fails.

Spreadsheets are written as plain OOXML parts with zipfile, so no extra Python package is needed and
every detail (date cells, formulas, hyperlinks, hidden parts) is under the test's control.
"""
import datetime
import io
import json
import zipfile
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
IMPORT_DIR = ROOT / 'tmp' / 'import-files'

MAIN_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
REL_NS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PKG_REL_NS = 'http://schemas.openxmlformats.org/package/2006/relationships'
HYPERLINK_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink'

# Column headers of the invented job search spreadsheet (row 2 of the main sheet).
EXCEL_HEADERS = ['Nro', 'Yritys', 'Tehtävänimike', 'Paikkakunta', 'Lähetetty', 'Tila', 'Vastattu?',
                 'Vastauspäivä', 'Haastattelupäivä', 'Muistiinpanot', 'Linkki ilmoitukseen']
# The column mapping a person would choose for EXCEL_HEADERS (used with the remap route).
EXCEL_MAPPING = {'0:0': 'ignore', '0:1': 'company', '0:2': 'role', '0:3': 'place', '0:4': 'added',
                 '0:5': 'status', '0:6': 'responded', '0:7': 'respondedAt', '0:8': 'interviewDate',
                 '0:9': 'notes', '0:10': 'link'}
EXTERNAL_LEAK = 'ROBOT-EXTERNAL-LEAK'
FORMULA_LEAK = 'ROBOT-FORMULA-LEAK'
SUMMARY_LEAK = 'ROBOT-SUMMARY-LEAK'


def _date(text):
    return ('date', datetime.date.fromisoformat(text))


def _link(text, url):
    return ('link', text, url)


def _formula(formula, cached):
    return ('formula', formula, cached)


def _column_letter(index):
    letters = ''
    index += 1
    while index:
        index, remainder = divmod(index - 1, 26)
        letters = chr(65 + remainder) + letters
    return letters


class _SharedStrings:
    def __init__(self):
        self.values = []
        self.index = {}

    def add(self, text):
        if text not in self.index:
            self.index[text] = len(self.values)
            self.values.append(text)
        return self.index[text]

    def xml(self):
        items = ''.join(f'<si><t xml:space="preserve">{escape(value)}</t></si>' for value in self.values)
        return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                f'<sst xmlns="{MAIN_NS}" count="{len(self.values)}" uniqueCount="{len(self.values)}">{items}</sst>')


def _sheet_xml(rows, strings):
    """Returns (sheet xml, hyperlink list) for rows of cell values."""
    row_xml = []
    links = []
    for row_number, cells in enumerate(rows, start=1):
        parts = []
        for column, value in enumerate(cells):
            ref = f'{_column_letter(column)}{row_number}'
            if value is None or value == '':
                continue
            if isinstance(value, bool):
                parts.append(f'<c r="{ref}" t="b"><v>{int(value)}</v></c>')
            elif isinstance(value, (int, float)):
                parts.append(f'<c r="{ref}"><v>{value}</v></c>')
            elif isinstance(value, str):
                parts.append(f'<c r="{ref}" t="s"><v>{strings.add(value)}</v></c>')
            elif value[0] == 'date':
                serial = (value[1] - datetime.date(1899, 12, 30)).days
                parts.append(f'<c r="{ref}" s="1"><v>{serial}</v></c>')
            elif value[0] == 'link':
                parts.append(f'<c r="{ref}" t="s"><v>{strings.add(value[1])}</v></c>')
                links.append((ref, value[2]))
            elif value[0] == 'formula':
                cached = value[2]
                if isinstance(cached, str):
                    parts.append(f'<c r="{ref}" t="str"><f>{escape(value[1])}</f><v>{escape(cached)}</v></c>')
                else:
                    parts.append(f'<c r="{ref}"><f>{escape(value[1])}</f><v>{cached}</v></c>')
            else:
                raise ValueError(f'Unknown cell {value!r}')
        row_xml.append(f'<row r="{row_number}">{"".join(parts)}</row>')
    hyperlinks = ''
    if links:
        hyperlinks = '<hyperlinks>' + ''.join(
            f'<hyperlink ref="{ref}" r:id="rIdLink{index}"/>' for index, (ref, _) in enumerate(links, start=1)) + '</hyperlinks>'
    xml = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
           f'<worksheet xmlns="{MAIN_NS}" xmlns:r="{REL_NS}"><sheetData>{"".join(row_xml)}</sheetData>{hyperlinks}</worksheet>')
    return xml, links


STYLES_XML = (
    f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="{MAIN_NS}">'
    '<fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>'
    '</styleSheet>')


def build_xlsx(sheets, extra_entries=None):
    """sheets: list of (name, rows). extra_entries: {zip path: bytes} added as they are."""
    strings = _SharedStrings()
    buffer = io.BytesIO()
    sheet_overrides = ''.join(
        f'<Override PartName="/xl/worksheets/sheet{index}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        for index in range(1, len(sheets) + 1))
    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        f'{sheet_overrides}'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
        '</Types>')
    workbook_sheets = ''.join(
        f'<sheet name="{escape(name)}" sheetId="{index}" r:id="rId{index}"/>' for index, (name, _) in enumerate(sheets, start=1))
    workbook = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                f'<workbook xmlns="{MAIN_NS}" xmlns:r="{REL_NS}"><sheets>{workbook_sheets}</sheets></workbook>')
    count = len(sheets)
    workbook_rels = (
        f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="{PKG_REL_NS}">'
        + ''.join(f'<Relationship Id="rId{index}" Type="{REL_NS}/worksheet" Target="worksheets/sheet{index}.xml"/>'
                  for index in range(1, count + 1))
        + f'<Relationship Id="rId{count + 1}" Type="{REL_NS}/styles" Target="styles.xml"/>'
        + f'<Relationship Id="rId{count + 2}" Type="{REL_NS}/sharedStrings" Target="sharedStrings.xml"/>'
        + '</Relationships>')
    root_rels = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="{PKG_REL_NS}">'
                 f'<Relationship Id="rId1" Type="{REL_NS}/officeDocument" Target="xl/workbook.xml"/></Relationships>')
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('[Content_Types].xml', content_types)
        archive.writestr('_rels/.rels', root_rels)
        archive.writestr('xl/workbook.xml', workbook)
        archive.writestr('xl/_rels/workbook.xml.rels', workbook_rels)
        archive.writestr('xl/styles.xml', STYLES_XML)
        for index, (_, rows) in enumerate(sheets, start=1):
            xml, links = _sheet_xml(rows, strings)
            archive.writestr(f'xl/worksheets/sheet{index}.xml', xml)
            if links:
                rels = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="{PKG_REL_NS}">'
                        + ''.join(f'<Relationship Id="rIdLink{number}" Type="{HYPERLINK_REL}" Target="{escape(url, {chr(34): "&quot;"})}" TargetMode="External"/>'
                                  for number, (_, url) in enumerate(links, start=1))
                        + '</Relationships>')
                archive.writestr(f'xl/worksheets/_rels/sheet{index}.xml.rels', rels)
        archive.writestr('xl/sharedStrings.xml', strings.xml())
        for path, data in (extra_entries or {}).items():
            archive.writestr(path, data)
    return buffer.getvalue()


def _excel_rows():
    """Invented job search sheet: title on row 1, headers on row 2, data from row 3."""
    return [
        ['Työnhakuseuranta 2026 (keksitty testiaineisto)'],
        EXCEL_HEADERS,
        [1, 'ROBOT Import Alfa Oy', 'Testaaja', 'Helsinki', _date('2026-03-02'), 'Lähetetty', 'Ei', '', '',
         'Lähetetty sähköpostilla', _link('Ilmoitus', 'https://example.com/robot-import/alfa')],
        [2, 'ROBOT Import Beeta Oy', 'Kehittäjä', 'Tampere', '5.3.2026', 'Hylätty', 'Kyllä', _date('2026-03-20'), '',
         '', 'https://example.com/robot-import/beeta'],
        [3, 'ROBOT Import Gamma Oy', 'Analyytikko', 'Espoo', _date('2026-03-10'), 'Haastattelu sovittu', 'Kyllä',
         '12.3.2026', _date('2026-03-18'), 'Toinen kierros', ''],
        [4, 'ROBOT Import Delta Oy', 'Suunnittelija', 'Oulu', '15.3.2026', 'Hyväksytty', 'Kyllä', _date('2026-04-01'),
         '25.3.2026', '', _link('Ilmoitus', 'https://example.com/robot-import/delta')],
        [5, 'ROBOT Import Epsilon Oy', 'Konsultti', 'Turku', '1.4.2026', 'Lähetetty', 'Kyllä', '', '', '', ''],
        [6, 'ROBOT Import Zeta Oy', 'Arkkitehti', 'Vaasa', '3.4.2026', 'Q7-koodi', 'Ei', '', '', '', ''],
        [7, 'ROBOT Import Eeta Oy', 'Integraattori', 'Lahti', _date('2026-04-05'), 'Lähetetty', '', '', '',
         _formula("'[ulkoinen.xlsx]Taul1'!A1", EXTERNAL_LEAK), _link('Avaa ilmoitus', 'javascript:alert(1)')],
        [8, 'ROBOT Import Theeta Oy', 'Ylläpitäjä', 'Pori', '7.4.2026', 'Lähetetty', '', '', '',
         _formula('CONCATENATE("ROBOT-","FORMULA-LEAK")', FORMULA_LEAK), _link('Lähetä sähköposti', 'mailto:robot@example.com')],
        [9, 'ROBOT Import Beeta Oy', 'Kehittäjä', 'Tampere', '8.4.2026', 'Lähetetty', '', '', '', '', ''],
        [],
        ['Yhteensä', _formula('COUNTA(B3:B11)', 9)],
    ]


def _summary_rows():
    return [
        [_formula('COUNTA(Hakemukset!B3:B11)', 9), _formula('COUNTIF(Hakemukset!F3:F11,"Hylätty")', 1)],
        [_formula('COUNTIF(Hakemukset!F3:F11,"Lähetetty")', 5), _formula('CONCATENATE("ROBOT-","SUMMARY-LEAK")', SUMMARY_LEAK)],
    ]


def _csv_bytes(rows, delimiter, encoding):
    def quote(value):
        value = str(value)
        if any(char in value for char in (delimiter, '"', '\n', '\r')):
            return '"' + value.replace('"', '""') + '"'
        return value
    text = '\r\n'.join(delimiter.join(quote(value) for value in row) for row in rows) + '\r\n'
    return text.encode(encoding)


def _docx(paragraphs):
    """paragraphs: list of strings or (text, hidden) pairs. Hidden runs use <w:vanish/>."""
    body = []
    for item in paragraphs:
        text, hidden = (item, False) if isinstance(item, str) else item
        props = '<w:rPr><w:vanish/></w:rPr>' if hidden else ''
        body.append(f'<w:p><w:r>{props}<w:t xml:space="preserve">{escape(text)}</w:t></w:r></w:p>')
    document = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                f'<w:body>{"".join(body)}</w:body></w:document>')
    content_types = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
                     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                     '<Default Extension="xml" ContentType="application/xml"/>'
                     '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
                     '</Types>')
    rels = (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="{PKG_REL_NS}">'
            f'<Relationship Id="rId1" Type="{REL_NS}/officeDocument" Target="word/document.xml"/></Relationships>')
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
        archive.writestr('[Content_Types].xml', content_types)
        archive.writestr('_rels/.rels', rels)
        archive.writestr('word/document.xml', document)
    return buffer.getvalue()


def _pdf_text(value):
    return value.encode('cp1252').replace(b'\\', b'\\\\').replace(b'(', b'\\(').replace(b')', b'\\)')


def _pdf(lines, javascript=None, uri=None):
    """One-page PDF with Helvetica text lines. javascript adds an OpenAction and a document-level
    script, uri a link annotation; neither may ever be run or opened by the server."""
    content = b'BT /F1 11 Tf 50 780 Td 14 TL ' + b''.join(b'(' + _pdf_text(line) + b') Tj T* ' for line in lines) + b'ET'
    objects = {}
    catalog = b'<< /Type /Catalog /Pages 2 0 R'
    if javascript:
        catalog += b' /OpenAction 5 0 R /Names << /JavaScript << /Names [(robot) 5 0 R] >> >>'
    catalog += b' >>'
    objects[1] = catalog
    objects[2] = b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>'
    page = b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 6 0 R'
    if javascript:
        page += b' /AA << /O 5 0 R >>'
    if uri:
        page += b' /Annots [7 0 R]'
    objects[3] = page + b' >>'
    objects[4] = b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>'
    if javascript:
        objects[5] = b'<< /Type /Action /S /JavaScript /JS (' + _pdf_text(javascript) + b') >>'
    else:
        objects[5] = b'<< >>'
    objects[6] = b'<< /Length ' + str(len(content)).encode() + b' >>\nstream\n' + content + b'\nendstream'
    if uri:
        objects[7] = (b'<< /Type /Annot /Subtype /Link /Rect [50 700 300 720] /Border [0 0 0] /A << /S /URI /URI ('
                      + _pdf_text(uri) + b') >> >>')
    out = io.BytesIO()
    out.write(b'%PDF-1.7\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for number in sorted(objects):
        offsets[number] = out.tell()
        out.write(f'{number} 0 obj\n'.encode() + objects[number] + b'\nendobj\n')
    xref = out.tell()
    size = max(objects) + 1
    out.write(f'xref\n0 {size}\n0000000000 65535 f \n'.encode())
    for number in range(1, size):
        out.write(f'{offsets[number]:010d} 00000 n \n'.encode() if number in offsets else b'0000000000 65535 f \n')
    out.write(f'trailer\n<< /Size {size} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    return out.getvalue()


class ImportTestFiles:
    ROBOT_LIBRARY_SCOPE = 'GLOBAL'

    # ------------------------------------------------------------------
    # Spreadsheets
    # ------------------------------------------------------------------
    def make_job_search_xlsx(self):
        """Invented job search workbook: sheet "Hakemukset" (title row, header row, 9 application rows,
        running numbers in column A, Excel dates and d.m.yyyy text dates, the statuses Lähetetty, Hylätty,
        Haastattelu sovittu and Hyväksytty plus one unknown status, formulas, an external reference, a
        javascript: and a mailto: hyperlink, an empty row and a totals row) and sheet "Yhteenveto" with
        formulas only."""
        return build_xlsx([('Hakemukset', _excel_rows()), ('Yhteenveto', _summary_rows())])

    def job_search_mapping(self):
        """The column mapping of make_job_search_xlsx as a person would choose it."""
        return dict(EXCEL_MAPPING)

    def make_macro_xlsx(self):
        """Valid workbook that carries a VBA project (as an .xlsm saved with the .xlsx extension)."""
        return build_xlsx([('Hakemukset', _excel_rows())], {'xl/vbaProject.bin': b'\xd0\xcf\x11\xe0robot-vba'})

    def make_zip_bomb_xlsx(self, unpacked_mb=45):
        """Small .xlsx (well under 1 MB) whose one extra part unpacks to unpacked_mb megabytes."""
        return build_xlsx([('Hakemukset', _excel_rows())],
                          {'xl/media/robot-bomb.bin': b'\0' * (int(unpacked_mb) * 1024 * 1024)})

    def make_zip_without_workbook(self):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr('[Content_Types].xml', '<Types/>')
            archive.writestr('robot.txt', 'not a workbook')
        return buffer.getvalue()

    def make_ole_file(self):
        """Compound File header: what encrypted Office files and old .xls/.doc files look like."""
        return b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1' + b'\0' * 4088

    def make_exe(self):
        return b'MZ\x90\x00\x03\x00\x00\x00\x04\x00\x00\x00\xff\xff' + b'\0' * 512 + b'This program cannot be run in DOS mode.'

    def make_csv(self, delimiter=';', encoding='utf-8', rows=None):
        """Three invented applications with Finnish letters, a quoted field with the delimiter and a
        d.m.yyyy date. delimiter ';' or ','; encoding e.g. utf-8 or cp1252."""
        return _csv_bytes(rows or self.csv_rows(delimiter), delimiter, encoding)

    def csv_rows(self, delimiter=';'):
        place = 'Helsinki; Espoo' if delimiter == ';' else 'Helsinki, Espoo'
        return [
            ['Yritys', 'Tehtävä', 'Paikkakunta', 'Lähetetty', 'Tila', 'Muistiinpanot'],
            ['ROBOT Äijälä Oy', 'Myyjä', 'Jyväskylä', '2.3.2026', 'Lähetetty', 'Hakemus "pikana"'],
            ['ROBOT Öljy Ab', 'Työnjohtaja', place, '4.3.2026', 'Hylätty', ''],
            ['ROBOT Åland Oy', 'Kääntäjä', 'Maarianhamina', '6.3.2026', 'Haastattelu sovittu', 'Ääni €'],
        ]

    def make_large_csv(self, rows=60):
        """CSV with the given number of invented application rows (for the 50 row limit)."""
        data = [['Yritys', 'Tehtävä', 'Paikkakunta', 'Lähetetty', 'Tila']]
        for index in range(1, int(rows) + 1):
            data.append([f'ROBOT Rivi {index:03d} Oy', 'Testaaja', 'Tampere', '1.3.2026', 'Lähetetty'])
        return _csv_bytes(data, ';', 'utf-8')

    def remap_table(self, row_count=9, prefix='ROBOT Remap'):
        """A table in the shape the import route returns, with invented rows, for the remap route."""
        rows = [{'n': index + 3, 'c': [str(index + 1), f'{prefix} {index + 1:03d} Oy', 'Testaaja', 'Tampere', '1.3.2026', 'Lähetetty']}
                for index in range(int(row_count))]
        return {
            'sheets': [{'name': 'Hakemukset', 'columns': [{'label': label} for label in ['Nro', 'Yritys', 'Tehtävä', 'Paikkakunta', 'Lähetetty', 'Tila']], 'rows': rows}],
            'mapping': {'0:0': 'ignore', '0:1': 'company', '0:2': 'role', '0:3': 'place', '0:4': 'added', '0:5': 'status'},
            'statusMap': {},
        }

    # ------------------------------------------------------------------
    # Free text
    # ------------------------------------------------------------------
    def make_docx_text(self, *paragraphs):
        return _docx(list(paragraphs))

    def make_docx_with_hidden_instruction(self, visible, hidden):
        """DOCX whose visible paragraph is followed by a hidden (w:vanish) one."""
        return _docx([visible, (hidden, True)])

    def make_pdf_text(self, *lines):
        return _pdf(list(lines))

    def make_pdf_with_javascript(self, port, *lines):
        """PDF with an OpenAction script, a page-open script and a link, all pointing at the local
        connection recorder (port). The server must never run the script or open the link."""
        script = (f'app.alert("robot"); app.launchURL("http://127.0.0.1:{port}/js", true); '
                  f'this.submitForm("http://127.0.0.1:{port}/submit");')
        return _pdf(list(lines), javascript=script, uri=f'http://127.0.0.1:{port}/uri')

    def make_long_text(self, length=20000):
        """UTF-8 text longer than the 16 000 character read limit, one application at the start."""
        head = 'ROBOT Pitkä Oy, tehtävä Testaaja, Tampere, haettu 2.3.2026, tila: lähetetty.\n'
        filler = 'Tämä rivi on täytettä eikä kuvaa hakemusta. ' * 3 + '\n'
        text = head
        while len(text) < int(length):
            text += filler
        return text.encode('utf-8')

    def encode_text(self, text, encoding='utf-8'):
        return str(text).encode(encoding)

    # ------------------------------------------------------------------
    # Files on disk and helpers
    # ------------------------------------------------------------------
    def write_import_file(self, name, content):
        """Writes the bytes to tmp/import-files/<name> and returns the path."""
        IMPORT_DIR.mkdir(parents=True, exist_ok=True)
        path = IMPORT_DIR / name
        path.write_bytes(content if isinstance(content, bytes) else str(content).encode('utf-8'))
        return str(path)

    def zip_entry_sizes(self, content):
        """Returns (packed size of the file, total unpacked size of its entries)."""
        with zipfile.ZipFile(io.BytesIO(content)) as archive:
            return len(content), sum(info.file_size for info in archive.infolist())

    def without_event_ids(self, events):
        """Events without their generated ids, for comparison."""
        return [{'type': event['type'], 'date': event['date'], 'note': event.get('note', '')} for event in events]

    def as_json(self, value):
        return json.dumps(value, ensure_ascii=False)
