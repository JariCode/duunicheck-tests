"""Reads the text of the PDF files the app makes with pdfmake (suite 23), without a PDF library.

pdfmake (pdfkit) writes every object uncompressed and every page content stream with FlateDecode.
Its fonts are embedded subsets with the Identity-H encoding: the text operators (Tj, TJ) hold
two-byte glyph ids, and each font's ToUnicode CMap maps them back to characters (also ligatures
such as "fi"). That is all this reader understands, which is enough for the app's own PDFs.
The text of a page is returned with all whitespace collapsed into single spaces, in the order the
page draws it (pdfmake draws every word as its own text object).
"""
import base64
import re
import zlib

_OBJECT = re.compile(rb'(\d+)\s+0\s+obj(.*?)endobj', re.S)
_STREAM = re.compile(rb'stream\r?\n(.*?)\r?\nendstream', re.S)
_TOKEN = re.compile(r'/([\w.+-]+)\s+[\d.]+\s+Tf|\[((?:<[0-9a-fA-F]*>|[^\]])*)\]\s*TJ|<([0-9a-fA-F]*)>\s*Tj|(ET)')


def _objects(data):
    objects = {}
    for match in _OBJECT.finditer(data):
        body = match.group(2)
        stream = None
        found = _STREAM.search(body)
        if found:
            stream = found.group(1)
            if b'/FlateDecode' in body[:found.start()]:
                try:
                    stream = zlib.decompress(stream)
                except zlib.error:
                    pass
            body = body[:found.start()]
        objects[int(match.group(1))] = (body, stream)
    return objects


def _utf16(hex_text):
    return bytes.fromhex(hex_text.replace(' ', '')).decode('utf-16-be', 'replace')


def _cmap(stream):
    mapping = {}
    text = stream.decode('latin-1')
    for block in re.findall(r'beginbfchar(.*?)endbfchar', text, re.S):
        for source, target in re.findall(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F ]+)>', block):
            mapping[int(source, 16)] = _utf16(target)
    for block in re.findall(r'beginbfrange(.*?)endbfrange', text, re.S):
        for low, high, target in re.findall(
                r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*(\[[^\]]*\]|<[0-9a-fA-F ]+>)', block):
            low, high = int(low, 16), int(high, 16)
            if target.startswith('['):
                for offset, value in enumerate(re.findall(r'<([0-9a-fA-F ]+)>', target)):
                    mapping[low + offset] = _utf16(value)
            else:
                start = int(target[1:-1].replace(' ', ''), 16)
                for offset in range(high - low + 1):
                    mapping[low + offset] = chr(start + offset)
    return mapping


def _decode(content, fonts):
    out, current = [], {}
    for font, array, single, end in _TOKEN.findall(content):
        if font:
            current = fonts.get(font, {})
        elif end:
            out.append(' ')
        else:
            for hex_text in (re.findall(r'<([0-9a-fA-F]*)>', array) if array else [single]):
                for index in range(0, len(hex_text) - 3, 4):
                    out.append(current.get(int(hex_text[index:index + 4], 16), ''))
    return ' '.join(''.join(out).split())


def _pages(data):
    objects = _objects(data)
    unicode_maps = {}
    for number, (body, _) in objects.items():
        ref = re.search(rb'/ToUnicode\s+(\d+)\s+0\s+R', body)
        if ref and objects.get(int(ref.group(1)), (b'', None))[1] is not None:
            unicode_maps[number] = _cmap(objects[int(ref.group(1))][1])
    pages = []
    for number in sorted(objects):
        body = objects[number][0]
        if not re.search(rb'/Type\s*/Page(?![\w])', body):
            continue
        resources = re.search(rb'/Resources\s+(\d+)\s+0\s+R', body)
        resource_body = objects.get(int(resources.group(1)), (b'', None))[0] if resources else body
        fonts = {}
        font_dict = re.search(rb'/Font\s*<<(.*?)>>', resource_body, re.S)
        if font_dict:
            for name, ref in re.findall(rb'/([\w.+-]+)\s+(\d+)\s+0\s+R', font_dict.group(1)):
                fonts[name.decode()] = unicode_maps.get(int(ref), {})
        contents = re.search(rb'/Contents\s+(\d+)\s+0\s+R', body)
        stream = objects.get(int(contents.group(1)), (b'', None))[1] if contents else None
        pages.append((number, _decode((stream or b'').decode('latin-1'), fonts)))
    # pdfkit numbers the page objects in page order.
    return [text for _, text in sorted(pages)]


class PdfText:
    ROBOT_LIBRARY_SCOPE = 'GLOBAL'

    def pdf_page_texts(self, data):
        """Returns the text of every page of the PDF, one string per page. ``data`` is the PDF as
        bytes or as a base64 string (as the browser gives it)."""
        if isinstance(data, str):
            data = base64.b64decode(data)
        if not bytes(data).startswith(b'%PDF-'):
            raise AssertionError('The data is not a PDF file')
        return _pages(bytes(data))

    # pdfmake draws each piece between line break opportunities (spaces, but also after a hyphen)
    # as its own text object, so the checks below compare the texts without any whitespace.
    @staticmethod
    def _compact(value):
        return ''.join(str(value).split())

    def pdf_text_should_contain_in_order(self, text, *parts):
        """Fails unless every part is in the page text, each after the previous one (whitespace is
        ignored)."""
        compact = self._compact(text)
        position = 0
        for part in parts:
            found = compact.find(self._compact(part), position)
            if found < 0:
                where = 'at all' if self._compact(part) not in compact else 'after the previous part'
                raise AssertionError(f'The PDF text does not contain "{part}" {where}. Text: {text}')
            position = found + len(self._compact(part))

    def pdf_text_should_not_contain(self, text, *parts):
        """Fails if any part is in the text, ignoring whitespace and case."""
        compact = self._compact(text).casefold()
        for part in parts:
            if self._compact(part).casefold() in compact:
                raise AssertionError(f'The PDF text contains "{part}". Text: {text}')

    def pdf_text_count(self, text, part):
        """How many times the part is in the text (whitespace ignored)."""
        return self._compact(text).count(self._compact(part))
