import 'models.dart';

const int kMinWords = 150;
const int kMaxWords = 250;

const String _openers = "\"“‘'([«";
const String _closers = ".!?…\"”’')]";

const Set<String> _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc', 'mt', //
  'no', 'fig', 'inc', 'ltd', 'col', 'gen', 'capt', 'lt', 'sgt', 'rev', 'hon',
  'e.g', 'i.e',
};

bool _isSpace(String c) =>
    c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == ' ';

bool _startsSentence(String c) {
  if (_openers.contains(c)) return true;
  if (RegExp(r'[0-9]').hasMatch(c)) return true;
  return c != c.toLowerCase() && c == c.toUpperCase();
}

bool _isAbbreviation(String s, int dotIndex) {
  if (s[dotIndex] != '.') return false;
  var i = dotIndex - 1;
  while (i >= 0 && !_isSpace(s[i]) && !_openers.contains(s[i])) {
    i--;
  }
  final word = s.substring(i + 1, dotIndex).toLowerCase();
  if (word.isEmpty) return false;
  if (_abbreviations.contains(word)) return true;
  return word.length == 1 && RegExp(r'[a-z]').hasMatch(word);
}

/// Splits prose into sentences. Good enough for novels, not a linguist.
List<String> splitSentences(String text) {
  final s = text.trim();
  final out = <String>[];
  var start = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '.' || c == '!' || c == '?' || c == '…') {
      var j = i + 1;
      while (j < s.length && _closers.contains(s[j])) {
        j++;
      }
      if (j < s.length && _isSpace(s[j])) {
        var k = j;
        while (k < s.length && _isSpace(s[k])) {
          k++;
        }
        if (k < s.length && _startsSentence(s[k]) && !_isAbbreviation(s, i)) {
          out.add(s.substring(start, j).trim());
          start = k;
          i = k;
          continue;
        }
      }
      i = j;
      continue;
    }
    i++;
  }
  if (start < s.length) out.add(s.substring(start).trim());
  return out.where((e) => e.isNotEmpty).toList();
}

/// Splits one very long paragraph at sentence ends into pieces of at most
/// [maxWords] words. A single sentence longer than that stays whole.
List<String> _splitLongParagraph(String text, int maxWords) {
  final pieces = <String>[];
  var current = <String>[];
  var currentWords = 0;
  for (final sentence in splitSentences(text)) {
    final w = countWords(sentence);
    if (current.isNotEmpty && currentWords + w > maxWords) {
      pieces.add(current.join(' '));
      current = <String>[];
      currentWords = 0;
    }
    current.add(sentence);
    currentWords += w;
  }
  if (current.isNotEmpty) pieces.add(current.join(' '));
  return pieces;
}

int _sum(List<Block> blocks) => blocks.fold<int>(0, (a, b) => a + b.words);

/// Groups [blocks] into chunks of roughly [minWords]..[maxWords] words.
///
/// Rules: order is never changed; a block is never cut (except a paragraph
/// longer than [maxWords], which is split at sentence ends); a heading never
/// ends a chunk; images and tables stay with the text around them.
List<Chunk> chunkBlocks(
  List<Block> blocks, {
  int minWords = kMinWords,
  int maxWords = kMaxWords,
}) {
  assert(minWords > 0 && maxWords >= minWords);
  final hardMax = maxWords + (maxWords - minWords);

  final prepared = <Block>[];
  for (final b in blocks) {
    if (b.kind == BlockKind.paragraph && b.words > maxWords) {
      for (final piece in _splitLongParagraph(b.text!, maxWords)) {
        prepared.add(Block.paragraph(piece));
      }
    } else {
      prepared.add(b);
    }
  }

  final groups = <List<Block>>[];
  var current = <Block>[];
  var count = 0;

  void flush() {
    if (current.isEmpty) return;
    Block? orphan;
    if (current.length > 1 && current.last.kind == BlockKind.heading) {
      orphan = current.removeLast();
    }
    groups.add(current);
    current = orphan == null ? <Block>[] : <Block>[orphan];
    count = orphan?.words ?? 0;
  }

  for (final b in prepared) {
    final w = b.words;
    if (b.kind == BlockKind.heading) {
      if (count >= minWords) flush();
    } else if (current.isNotEmpty &&
        ((count >= minWords && count + w > maxWords) ||
            count + w > hardMax)) {
      flush();
    }
    current.add(b);
    count += w;
  }
  if (current.isNotEmpty) groups.add(current);

  // Fold a tiny tail into the previous chunk, unless it opens a new chapter.
  if (groups.length >= 2) {
    final last = groups.last;
    final prev = groups[groups.length - 2];
    if (_sum(last) < minWords ~/ 2 &&
        _sum(prev) + _sum(last) <= hardMax &&
        last.first.kind != BlockKind.heading) {
      prev.addAll(last);
      groups.removeLast();
    }
  }

  final chunks = <Chunk>[];
  String? chapter;
  for (final g in groups) {
    for (final b in g) {
      if (b.kind == BlockKind.heading) chapter = b.text;
    }
    chunks.add(Chunk(g, chapter));
  }
  return chunks;
}

/// The "Previously..." lead-in: the last sentences of the previous chunk.
String recapSnippet(Chunk previous, {bool long = false}) {
  Block? para;
  for (final b in previous.blocks.reversed) {
    if (b.kind == BlockKind.paragraph) {
      para = b;
      break;
    }
  }
  if (para == null) return '';
  final sentences = splitSentences(para.text!);
  final take = long ? 5 : 2;
  if (sentences.length <= take) return sentences.join(' ');
  return '… ${sentences.sublist(sentences.length - take).join(' ')}';
}

/// Estimated reading time in seconds at ~230 words per minute.
int estimateSeconds(Chunk chunk) => (chunk.words / 230 * 60).round();
