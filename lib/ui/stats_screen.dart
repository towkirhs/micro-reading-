import 'package:flutter/material.dart';

import '../models.dart';
import '../stats.dart';
import '../store.dart';
import 'charts.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final theme = Theme.of(context);
        final today = store.readToday();
        final target = store.todayTarget();
        final progress = target == 0 ? 0.0 : today / target;
        final streak = store.streak;
        final rate = store.responseRateNow;

        return Scaffold(
          appBar: AppBar(title: const Text('Progress')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 112,
                        height: 112,
                        child: CustomPaint(
                          painter: RingPainter(
                            progress: progress,
                            color: theme.colorScheme.primary,
                            track: theme.colorScheme.surfaceContainerHighest,
                          ),
                          child: Center(
                            child: Text(
                              target == 0 ? '–' : '$today/$target',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Today's pieces",
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              target == 0
                                  ? 'Add a book or resume one to get started.'
                                  : today >= target
                                      ? 'Ring closed. Anything more is a bonus.'
                                      : '${target - today} to go today.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Streak',
                      value: '$streak 🔥',
                      note: 'One missed day per week is forgiven.',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Response rate',
                      value: rate == null ? '–' : '${(rate * 100).round()}%',
                      note: 'Notifications you reacted to within an hour.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Pace', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (store.books.isEmpty)
                const Text('No books yet.')
              else
                for (final b in store.books) _PaceCard(store: store, book: b),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.note});

  final String title;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(note,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _PaceCard extends StatelessWidget {
  const _PaceCard({required this.store, required this.book});

  final AppStore store;
  final Book book;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final pace = paceFor(
      totalChunks: book.totalChunks,
      position: book.position,
      startedAt: book.addedAt,
      goalStart: book.goalStart,
      goalDays: book.goalDays,
      now: now,
    );
    final series = cumulativeReads(
      events: store.events,
      bookId: book.id,
      from: book.addedAt,
      to: now,
    );

    String status;
    if (book.finished) {
      status = 'Finished 🎉';
    } else if (pace.projectedFinish == null) {
      status = 'Read your first piece to see a projection.';
    } else {
      status = 'At this pace you finish ${shortDate(pace.projectedFinish!)}';
      final ahead = pace.daysAhead;
      if (ahead != null) {
        status += ahead >= 0
            ? ' · ${ahead == 0 ? 'right on goal' : '$ahead days ahead of goal'}'
            : ' · ${-ahead} days behind goal';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(status, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              width: double.infinity,
              child: CustomPaint(
                painter: PaceChartPainter(
                  actual: series,
                  total: book.totalChunks,
                  goalDays: book.goalDays,
                  actualColor: theme.colorScheme.primary,
                  goalColor: theme.colorScheme.outline,
                  axisColor: theme.colorScheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              book.goalDays == null
                  ? 'Line: pieces read. Set a goal on the Library tab to see the target line.'
                  : 'Coloured line: pieces read. Grey line: the path to your goal.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
