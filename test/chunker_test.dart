import 'package:flutter_test/flutter_test.dart';
import 'package:micro_reader/chunker.dart';
import 'package:micro_reader/models.dart';

String words(int n, [String tag = 'w']) =>
    List.generate(n, (i) => '$tag$i').join(' ');

Block para(int n, [String tag = 'w']) => Block.paragraph(words(n, tag));

List<Block> flatten(List<Chunk> chunks) =>
    [for (final c in chunks) ...c.blocks];

void main() {
  group('chunkBlocks', () {
    test('keeps order and never cuts a paragraph', () {
      final input = [for (var i = 0; i < 40; i++) para(60, 'p${i}_')];
      final chunks = chunkBlocks(input);
      final out = flatten(chunks);
      expect(out.length, input.length);
      for (var i = 0; i < input.length; i++) {
        expect(out[i].text, input[i].text);
      }
      for (final c in chunks.sublist(0, chunks.length - 1)) {
        expect(c.words, inInclusiveRange(kMinWords, 350));
      }
    });

    test('splits an over-long paragraph only at sentence ends', () {
      final sentences = [
        for (var i = 0; i < 40; i++) 'Sentence number $i has exactly seven words.'
      ];
      final long = sentences.join(' ');
      final chunks = chunkBlocks([Block.paragraph(long)]);
      final pieces = flatten(chunks).map((b) => b.text!).toList();
      expect(pieces.length, greaterThan(1));
      for (final p in pieces) {
        expect(p.endsWith('.'), isTrue);
        expect(countWords(p), lessThanOrEqualTo(kMaxWords));
      }
      expect(pieces.join(' '), long);
    });

    test('a heading opens a new chunk once the current one is long enough', () {
      final chunks = chunkBlocks([
        para(160),
        const Block.heading('Chapter 2'),
        para(50),
      ]);
      expect(chunks.length, 2);
      expect(chunks[1].blocks.first.kind, BlockKind.heading);
      expect(chunks[0].chapter, isNull);
      expect(chunks[1].chapter, 'Chapter 2');
    });

    test('a heading is never left at the end of a chunk', () {
      final chunks = chunkBlocks([
        para(140),
        const Block.heading('Chapter 2'),
        para(245),
      ]);
      expect(chunks.length, 2);
      for (final c in chunks) {
        expect(c.blocks.last.kind, isNot(BlockKind.heading));
      }
      expect(chunks[1].blocks.first.kind, BlockKind.heading);
    });

    test('images and tables stay with their chunk', () {
      final table = Block.table([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      final chunks = chunkBlocks([
        para(200),
        const Block.image('img/0.png'),
        table,
      ]);
      expect(chunks.length, 1);
      expect(chunks.single.blocks.map((b) => b.kind), [
        BlockKind.paragraph,
        BlockKind.image,
        BlockKind.table,
      ]);
    });

    test('a tiny tail is folded into the previous chunk', () {
      final chunks = chunkBlocks([para(240), para(20, 'tail')]);
      expect(chunks.length, 1);
      expect(chunks.single.blocks.length, 2);
    });

    test('empty input gives no chunks', () {
      expect(chunkBlocks(const []), isEmpty);
    });
  });

  group('splitSentences', () {
    test('basic punctuation', () {
      expect(splitSentences('Hello there. How are you? Fine!'),
          ['Hello there.', 'How are you?', 'Fine!']);
    });

    test('does not split after abbreviations or initials', () {
      expect(splitSentences('Mr. Smith met J. Brown. They left.'),
          ['Mr. Smith met J. Brown.', 'They left.']);
    });

    test('handles dialogue quotes', () {
      expect(splitSentences('"Go away," she said. "Never."'),
          ['"Go away," she said.', '"Never."']);
    });

    test('single sentence without final punctuation', () {
      expect(splitSentences('No full stop here'), ['No full stop here']);
    });
  });

  group('recapSnippet', () {
    test('returns the last two sentences with an ellipsis', () {
      final prev = Chunk([
        const Block.paragraph('One. Two. Three. Four.'),
      ], null);
      expect(recapSnippet(prev), '… Three. Four.');
    });

    test('long recap returns more sentences', () {
      final prev = Chunk([
        const Block.paragraph(
            'Alpha one. Beta two. Gamma three. Delta four. Epsilon five. '
            'Zeta six. Eta seven.'),
      ], null);
      expect(recapSnippet(prev, long: true),
          '… Gamma three. Delta four. Epsilon five. Zeta six. Eta seven.');
    });

    test('short paragraph is returned whole', () {
      final prev = Chunk([const Block.paragraph('Only this.')], null);
      expect(recapSnippet(prev), 'Only this.');
    });

    test('no paragraph gives an empty string', () {
      final prev = Chunk([const Block.image('img/0.png')], null);
      expect(recapSnippet(prev), '');
    });
  });
}
