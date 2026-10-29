import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:micro_reader/epub_import.dart';
import 'package:micro_reader/models.dart';

Uint8List buildEpub({bool includeContainer = true}) {
  final archive = Archive();
  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
  void addText(String name, String content) => add(name, utf8.encode(content));

  addText('mimetype', 'application/epub+zip');
  if (includeContainer) {
    addText(
      'META-INF/container.xml',
      '<?xml version="1.0"?>'
          '<container version="1.0" '
          'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
          '<rootfiles><rootfile full-path="OEBPS/content.opf" '
          'media-type="application/oebps-package+xml"/></rootfiles>'
          '</container>',
    );
  }
  addText(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>The Test Novel</dc:title></metadata>'
        '<manifest>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="c1" href="text/ch1.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="c2" href="text/ch2.xhtml" '
        'media-type="application/xhtml+xml"/>'
        '<item id="img" href="images/pic one.png" media-type="image/png"/>'
        '</manifest>'
        '<spine><itemref idref="nav"/><itemref idref="c1"/>'
        '<itemref idref="c2"/></spine></package>',
  );
  addText(
    'OEBPS/nav.xhtml',
    '<html><body><nav><ol><li>Chapter One</li></ol></nav></body></html>',
  );
  addText(
    'OEBPS/text/ch1.xhtml',
    '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml">'
        '<body><h1>Chapter One</h1>'
        '<p>It was a dark night.</p>'
        '<div><p>Second   paragraph &amp; more.</p>'
        '<p><img src="../images/pic%20one.png" alt="x"/></p></div>'
        '<table><tr><th>Name</th><th>Age</th></tr>'
        '<tr><td>Ann</td><td>30</td></tr></table>'
        '</body></html>',
  );
  addText(
    'OEBPS/text/ch2.xhtml',
    '<html><body><h2>Chapter Two</h2><p>The next day.</p></body></html>',
  );
  // Fake PNG: parseEpub does not decode images, it only copies the bytes.
  add('OEBPS/images/pic one.png', List<int>.filled(3000, 7));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  test('reads title, spine order, headings, paragraphs, image and table', () {
    final parsed = parseEpub(buildEpub());
    expect(parsed.title, 'The Test Novel');

    final kinds = parsed.blocks.map((b) => b.kind).toList();
    expect(kinds, [
      BlockKind.heading,
      BlockKind.paragraph,
      BlockKind.paragraph,
      BlockKind.image,
      BlockKind.table,
      BlockKind.heading,
      BlockKind.paragraph,
    ]);
    expect(parsed.blocks[0].text, 'Chapter One');
    expect(parsed.blocks[1].text, 'It was a dark night.');
    expect(parsed.blocks[2].text, 'Second paragraph & more.');
    expect(parsed.blocks[3].path, 'img/0.png');
    expect(parsed.blocks[4].rows, [
      ['Name', 'Age'],
      ['Ann', '30'],
    ]);
    expect(parsed.blocks[5].text, 'Chapter Two');
    expect(parsed.images.keys, ['img/0.png']);
    expect(parsed.images['img/0.png']!.length, 3000);
  });

  test('the nav document is not part of the story', () {
    final parsed = parseEpub(buildEpub());
    expect(parsed.blocks.where((b) => b.text == 'Chapter One').length, 1);
  });

  test('importEpubBytes returns chunks as JSON', () {
    final result = importEpubBytes(buildEpub());
    expect(result['title'], 'The Test Novel');
    expect(result['count'], 1);
    final chunks = jsonDecode(result['chunksJson']! as String) as List;
    expect(chunks.length, 1);
    final chunk = Chunk.fromJson(chunks.first as Map<String, dynamic>);
    expect(chunk.chapter, 'Chapter Two');
    expect(chunk.blocks.length, 7);
  });

  test('rejects files that are not EPUBs', () {
    expect(() => parseEpub(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<FormatException>()));
    expect(() => parseEpub(buildEpub(includeContainer: false)),
        throwsA(isA<FormatException>()));
  });
}
