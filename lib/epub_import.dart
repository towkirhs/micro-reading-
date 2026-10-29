import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'chunker.dart';
import 'models.dart';

class ParsedEpub {
  ParsedEpub(this.title, this.blocks, this.images);

  /// Empty when the EPUB has no title.
  final String title;
  final List<Block> blocks;

  /// Image file bytes keyed by the relative path used in [Block.image].
  final Map<String, Uint8List> images;
}

const Set<String> _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'ul', 'ol', 'li', 'table',
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'figure', 'figcaption', 'aside', //
  'main', 'header', 'footer', 'pre', 'dl', 'dt', 'dd', 'hr', 'body',
};
const Set<String> _skipTags = {'script', 'style', 'head', 'nav', 'svg', 'math'};
const Set<String> _imageExtensions = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};

/// Images smaller than this are decoration (dividers, bullets), not content.
const int _minImageBytes = 1500;

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Reads an EPUB and returns its content as ordered blocks.
/// Throws [FormatException] if the file is not a usable EPUB.
ParsedEpub parseEpub(Uint8List bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('This file is not a valid EPUB (not a zip).');
  }

  Uint8List? read(String name) {
    final file = archive.findFile(name) ?? archive.findFile(Uri.decodeFull(name));
    if (file == null || !file.isFile) return null;
    return Uint8List.fromList(file.content as List<int>);
  }

  String text(Uint8List data) => utf8.decode(data, allowMalformed: true);

  final containerBytes = read('META-INF/container.xml');
  if (containerBytes == null) {
    throw const FormatException('Not a valid EPUB: container.xml is missing.');
  }
  final rootfile = XmlDocument.parse(text(containerBytes))
      .findAllElements('rootfile')
      .firstOrNull
      ?.getAttribute('full-path');
  final opfBytes = rootfile == null ? null : read(rootfile);
  if (rootfile == null || opfBytes == null) {
    throw const FormatException('Not a valid EPUB: package file is missing.');
  }

  final opf = XmlDocument.parse(text(opfBytes));
  final opfDir = p.posix.dirname(rootfile);
  final title = opf
          .findAllElements('title', namespace: '*')
          .firstOrNull
          ?.innerText
          .trim() ??
      '';

  final manifest = <String, XmlElement>{
    for (final item in opf.findAllElements('item'))
      if (item.getAttribute('id') != null) item.getAttribute('id')!: item,
  };

  final blocks = <Block>[];
  final images = <String, Uint8List>{};
  final imageNames = <String, String>{};

  Block? imageBlock(dom.Element img, String docPath) {
    final src = img.attributes['src'];
    if (src == null || src.isEmpty || src.startsWith('data:')) return null;
    final resolved = p.posix.normalize(p.posix
        .join(p.posix.dirname(docPath), Uri.decodeFull(src.split('#').first)));
    final ext = p.posix.extension(resolved).toLowerCase();
    if (!_imageExtensions.contains(ext)) return null;
    final existing = imageNames[resolved];
    if (existing != null) return Block.image(existing);
    final data = read(resolved);
    if (data == null || data.length < _minImageBytes) return null;
    final name = 'img/${imageNames.length}$ext';
    imageNames[resolved] = name;
    images[name] = data;
    return Block.image(name);
  }

  void addParagraphLike(dom.Element e, String docPath) {
    final t = _clean(e.text);
    if (t.isNotEmpty) blocks.add(Block.paragraph(t));
    for (final img in e.getElementsByTagName('img')) {
      final b = imageBlock(img, docPath);
      if (b != null) blocks.add(b);
    }
  }

  void addTable(dom.Element table, String docPath) {
    final rows = <List<String>>[];
    for (final tr in table.getElementsByTagName('tr')) {
      final cells = tr.children
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .map((c) => _clean(c.text))
          .toList();
      if (cells.any((c) => c.isNotEmpty)) rows.add(cells);
    }
    if (rows.isEmpty) return;
    // Some books lay out the whole page as a one-column table.
    if (rows.every((r) => r.length == 1)) {
      for (final r in rows) {
        if (r.first.isNotEmpty) blocks.add(Block.paragraph(r.first));
      }
      return;
    }
    blocks.add(Block.table(rows));
  }

  void walk(dom.Node node, String docPath) {
    if (node is dom.Text) {
      final t = _clean(node.text);
      if (t.isNotEmpty) blocks.add(Block.paragraph(t));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';
    if (_skipTags.contains(tag) || tag == 'hr' || tag == 'br') return;
    if (tag.length == 2 && tag[0] == 'h' && '123456'.contains(tag[1])) {
      final t = _clean(node.text);
      if (t.isNotEmpty) blocks.add(Block.heading(t));
      return;
    }
    if (tag == 'img') {
      final b = imageBlock(node, docPath);
      if (b != null) blocks.add(b);
      return;
    }
    if (tag == 'table') {
      addTable(node, docPath);
      return;
    }
    final hasBlockChild =
        node.children.any((c) => _blockTags.contains(c.localName));
    if (!hasBlockChild) {
      addParagraphLike(node, docPath);
    } else {
      for (final child in node.nodes) {
        walk(child, docPath);
      }
    }
  }

  for (final ref in opf.findAllElements('itemref')) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null) continue;
    final href = item.getAttribute('href');
    final type = item.getAttribute('media-type') ?? '';
    final props = item.getAttribute('properties') ?? '';
    if (href == null || props.contains('nav')) continue;
    if (type != 'application/xhtml+xml' && type != 'text/html') continue;
    final docPath = p.posix
        .normalize(p.posix.join(opfDir, Uri.decodeFull(href.split('#').first)));
    final data = read(docPath);
    if (data == null) continue;
    final body = html_parser.parse(text(data)).body;
    if (body == null) continue;
    for (final child in body.nodes) {
      walk(child, docPath);
    }
  }

  if (blocks.isEmpty) {
    throw const FormatException('No readable text found in this EPUB.');
  }
  return ParsedEpub(title, blocks, images);
}

/// Top-level so it can run in a background isolate via `compute`.
Map<String, Object> importEpubBytes(Uint8List bytes) {
  final parsed = parseEpub(bytes);
  final chunks = chunkBlocks(parsed.blocks);
  return {
    'title': parsed.title,
    'count': chunks.length,
    'chunksJson': jsonEncode(chunks.map((c) => c.toJson()).toList()),
    'images': parsed.images,
  };
}
