import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('Library')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _import(context),
            icon: const Icon(Icons.add),
            label: const Text('Add EPUB'),
          ),
          body: store.books.isEmpty
              ? const _EmptyState()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final b in store.books) _BookCard(store: store, book: b),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path == null) return;
    if (!path.toLowerCase().endsWith('.epub')) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Please pick an .epub file.')));
      return;
    }
    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Cutting your book into pieces…')),
          ],
        ),
      ),
    );
    String? error;
    try {
      await store.importEpub(path);
    } catch (e) {
      error = e is FormatException ? e.message : 'Could not import: $e';
    }
    navigator.pop();
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    } else {
      messenger.showSnackBar(const SnackBar(
          content: Text('Book added. Your first notification is on its way.')));
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No books yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Add an EPUB and I will hand it to you in tiny pieces, '
              'at random moments of the day.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.store, required this.book});

  final AppStore store;
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress =
        book.totalChunks == 0 ? 0.0 : book.position / book.totalChunks;
    final goal = (book.goalDays != null && book.goalStart != null)
        ? 'Goal: finish by '
            '${shortDate(addDays(dayOf(book.goalStart!), book.goalDays! - 1))}'
        : 'No finish goal';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(book.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
                Switch(
                  value: book.active,
                  onChanged: book.finished
                      ? null
                      : (v) => store.setActive(book, v),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _menu(context, v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'goal', child: Text('Set finish goal…')),
                    if (book.goalDays != null)
                      const PopupMenuItem(
                          value: 'nogoal', child: Text('Remove goal')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete book')),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${book.position} of ${book.totalChunks} pieces · '
              '${(progress * 100).round()}%',
              style: theme.textTheme.bodySmall,
            ),
            Text(
              book.active ? goal : '$goal · paused',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: book.finished
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => ReaderScreen(store: store, book: book),
                      )),
              child: Text(book.finished ? 'Finished 🎉' : 'Read next piece'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _menu(BuildContext context, String action) async {
    switch (action) {
      case 'goal':
        await _setGoal(context);
      case 'nogoal':
        await store.setGoal(book, null);
      case 'delete':
        await _confirmDelete(context);
    }
  }

  Future<void> _setGoal(BuildContext context) async {
    final controller = TextEditingController(text: '${book.goalDays ?? 15}');
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finish in how many days?'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(suffixText: 'days'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text)),
            child: const Text('Set goal'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (days != null && days > 0) await store.setGoal(book, days);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this book?'),
        content: Text('"${book.title}" and your progress in it will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.deleteBook(book);
  }
}
