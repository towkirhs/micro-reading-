import 'dart:math';

import 'models.dart';
import 'stats.dart';

/// Picks random notification times.
///
/// [perDayCounts] holds how many notifications to place on each day, starting
/// with today. Every time lands inside the awake window, consecutive times are
/// at least [minGap] apart, and nothing is placed before `now + 1 minute` (or
/// before [lastSlot] + [minGap]). If a window is too short for the requested
/// count, fewer notifications are placed.
///
/// Method: choose `count` uniform offsets in the slack left after reserving
/// the gaps, sort them, then add `i * gap` to the i-th one.
List<DateTime> planSlots({
  required DateTime now,
  required List<int> perDayCounts,
  required int awakeStartMin,
  required int awakeEndMin,
  required Duration minGap,
  required Random rng,
  DateTime? lastSlot,
}) {
  final out = <DateTime>[];
  final gapSec = max(1, minGap.inSeconds);
  for (var i = 0; i < perDayCounts.length; i++) {
    final day = addDays(now, i);
    var start = DateTime(day.year, day.month, day.day, 0, awakeStartMin);
    final end = DateTime(day.year, day.month, day.day, 0, awakeEndMin);
    if (i == 0) {
      final earliest = now.add(const Duration(minutes: 1));
      if (earliest.isAfter(start)) start = earliest;
      if (lastSlot != null) {
        final afterLast = lastSlot.add(minGap);
        if (afterLast.isAfter(start)) start = afterLast;
      }
    }
    var count = perDayCounts[i];
    final length = end.difference(start).inSeconds;
    if (count <= 0 || length <= 0) continue;
    if ((count - 1) * gapSec > length) count = length ~/ gapSec + 1;
    final slack = length - (count - 1) * gapSec;
    final offsets = List<int>.generate(count, (_) => rng.nextInt(slack + 1))
      ..sort();
    for (var k = 0; k < count; k++) {
      out.add(start.add(Duration(seconds: offsets[k] + k * gapSec)));
    }
  }
  return out;
}

/// How many chunks to read today, across all active books.
///
/// A book with a goal contributes `ceil(remaining at the start of today /
/// days left)`, so the number stays steady while you read through the day.
/// A book without a goal contributes its share of `defaultPerDay`. The total
/// is clamped to `1..dailyCap`; 0 when nothing is active.
int dailyTarget({
  required List<Book> books,
  required Settings settings,
  required DateTime now,
  required Map<String, int> readTodayByBook,
}) {
  final active = books.where((b) => b.active && !b.finished).toList();
  if (active.isEmpty) return 0;
  final today = dayOf(now);
  var total = 0;
  for (final b in active) {
    if (b.goalDays != null && b.goalStart != null) {
      final goalEnd = addDays(dayOf(b.goalStart!), b.goalDays!);
      final daysLeft = max(1, daysBetween(today, goalEnd));
      final remainingAtDayStart = b.remaining + (readTodayByBook[b.id] ?? 0);
      total += (remainingAtDayStart / daysLeft).ceil();
    } else {
      total += (settings.defaultPerDay / active.length).ceil();
    }
  }
  return total.clamp(1, settings.dailyCap).toInt();
}
