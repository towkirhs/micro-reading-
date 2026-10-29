import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../chunker.dart';
import '../models.dart';
import '../store.dart';

/// Shows one chunk. The app only moves forward when you press Done.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.store, required this.book});

  final AppStore store;
  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _scroll = ScrollController();
  Timer? _ticker;

  late List<Chunk> _chunks;
  late int _view;
  late bool _longGap;
  int _secondsLeft = 0;
  bool _reachedEnd = false;

  Book get _book => widget.book;

  bool get _isPending => !_book.finished && _view == _book.position;

  @override
  void initState() {
    super.initState();
    _chunks = widget.store.chunksOf(_book);
    _view = min(_book.position, _chunks.length - 1);
    final last = widget.store.lastReadTime(_book);
    _longGap =
        last != null && DateTime.now().difference(last) > const Duration(days: 1);
    _scroll.addListener(_checkEnd);
    _enterChunk();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft > 0 && mounted) setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Resets the read-gate for the chunk now on screen.
  void _enterChunk() {
    _reachedEnd = false;
    _secondsLeft =
        _isPending ? max(5, estimateSeconds(_chunks[_view]) ~/ 2) : 0;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _checkEnd() {
    if (!_scroll.hasClients) return;
    final m = _scroll.position;
    final atEnd = m.maxScrollExtent <= 0 || m.pixels >= m.maxScrollExtent - 24;
    if (atEnd != _reachedEnd && mounted) setState(() => _reachedEnd = atEnd);
  }

  void _go(int index) {
    setState(() {
      _view = index;
      _enterChunk();
    });
  }

  Future<void> _done() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.store.markRead(_book);
    final today = widget.store.readToday();
    final target = widget.store.todayTarget();
    final streak = widget.store.streak;
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text('Nice! $today of $target today · $streak-day streak 🔥'),
    ));
  }

  Future<void> _snooze() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await widget.store.snooze(_book);
    navigator.pop();
    messenger.showSnackBar(const SnackBar(
      content: Text('Snoozed. I will remind you in $kSnoozeMinutes minutes.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEnd());
    final theme = Theme.of(context);
    final chunk = _chunks[_view];
    final recap =
        _view > 0 ? recapSnippet(_chunks[_view - 1], long: _longGap) : '';
    final bookPath = widget.store.bookDir(_book.id).path;
    final canDone = _isPending && _reachedEnd && _secondsLeft <= 0;
    final canGoNext = _view < _book.position && _view + 1 < _chunks.length;

    String doneLabel() {
      if (canDone) return 'Done ✓';
      if (_secondsLeft > 0) return 'Done in ${_secondsLeft}s';
      return 'Scroll to the end';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: (_view + 1) / _chunks.length),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${chunk.chapter ?? _book.title} · '
                      'piece ${_view + 1} of ${_chunks.length}',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                    if (recap.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Previously… $recap',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    for (final b in chunk.blocks) _BlockView(b, bookPath),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous piece',
                        onPressed: _view > 0 ? () => _go(_view - 1) : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: _isPending
                            ? FilledButton(
                                onPressed: canDone ? _done : null,
                                child: Text(doneLabel()),
                              )
                            : _book.finished
                                ? const Center(child: Text('Finished 🎉'))
                                : OutlinedButton(
                                    onPressed: () => _go(_book.position),
                                    child: const Text('Back to where I was'),
                                  ),
                      ),
                      IconButton(
                        tooltip: 'Next piece',
                        onPressed: canGoNext ? () => _go(_view + 1) : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  if (_isPending)
                    TextButton(
                      onPressed: _snooze,
                      child: const Text('Snooze $kSnoozeMinutes min'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView(this.block, this.bookPath);

  final Block block;
  final String bookPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (block.kind) {
      case BlockKind.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 12),
          child: Text(block.text ?? '', style: theme.textTheme.titleLarge),
        );
      case BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            block.text ?? '',
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18, height: 1.6),
          ),
        );
      case BlockKind.image:
        final file = File(p.join(bookPath, block.path ?? ''));
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: GestureDetector(
            onTap: () => _showFullImage(context, file),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        );
      case BlockKind.table:
        final rows = block.rows ?? const <List<String>>[];
        final columns = rows.fold<int>(0, (m, r) => max(m, r.length));
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Table(
            border: TableBorder.all(color: theme.colorScheme.outlineVariant),
            children: [
              for (final r in rows)
                TableRow(children: [
                  for (var i = 0; i < columns; i++)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        i < r.length ? r[i] : '',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ]),
            ],
          ),
        );
    }
  }

  void _showFullImage(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 6,
                child: Center(child: Image.file(file)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
