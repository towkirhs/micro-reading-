import 'dart:math';

import 'models.dart';

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Whole calendar days from [a] to [b] (negative if [b] is earlier).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

Set<DateTime> readDays(Iterable<ReadEvent> events) =>
    {for (final e in events) if (e.isRead) dayOf(e.time)};

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// Consecutive days with at least one confirmed chunk, ending today.
///
/// Today not being read yet does not break the streak. One missed day per
/// calendar week (Mon-Sun) is forgiven ("freeze"); a second miss in the same
/// week ends the streak. Forgiven days do not add to the count.
int computeStreak(Set<DateTime> days, DateTime now) {
  if (days.isEmpty) return 0;
  final today = dayOf(now);
  final earliest = days.reduce((a, b) => a.isBefore(b) ? a : b);
  var streak = days.contains(today) ? 1 : 0;
  final frozenWeeks = <DateTime>{};
  var d = addDays(today, -1);
  while (!d.isBefore(earliest)) {
    if (days.contains(d)) {
      streak++;
    } else {
      final week = weekStart(d);
      if (frozenWeeks.contains(week)) break;
      frozenWeeks.add(week);
    }
    d = addDays(d, -1);
  }
  return streak;
}

int readCountOn(Iterable<ReadEvent> events, DateTime day, {String? bookId}) {
  final target = dayOf(day);
  return events
      .where((e) =>
          e.isRead &&
          dayOf(e.time) == target &&
          (bookId == null || e.bookId == bookId))
      .length;
}

class Pace {
  const Pace({
    required this.remaining,
    required this.perDay,
    this.projectedFinish,
    this.goalFinish,
  });

  final int remaining;

  /// Average confirmed chunks per day since the book was added.
  final double perDay;
  final DateTime? projectedFinish;
  final DateTime? goalFinish;

  /// Positive: finishing before the goal. Negative: behind. Null: no goal or
  /// no projection yet.
  int? get daysAhead => (projectedFinish != null && goalFinish != null)
      ? daysBetween(projectedFinish!, goalFinish!)
      : null;
}

Pace paceFor({
  required int totalChunks,
  required int position,
  required DateTime startedAt,
  required DateTime now,
  DateTime? goalStart,
  int? goalDays,
}) {
  final today = dayOf(now);
  final elapsed = max(1, daysBetween(dayOf(startedAt), today) + 1);
  final remaining = totalChunks - position;
  final perDay = position / elapsed;
  DateTime? projected;
  if (remaining <= 0) {
    projected = today;
  } else if (perDay > 0) {
    projected = addDays(today, (remaining / perDay).ceil());
  }
  DateTime? goalFinish;
  if (goalDays != null && goalStart != null) {
    goalFinish = addDays(dayOf(goalStart), goalDays - 1);
  }
  return Pace(
    remaining: remaining,
    perDay: perDay,
    projectedFinish: projected,
    goalFinish: goalFinish,
  );
}

/// Cumulative confirmed chunks of [bookId] at the end of each day from
/// [from] to [to] inclusive.
List<int> cumulativeReads({
  required Iterable<ReadEvent> events,
  required String bookId,
  required DateTime from,
  required DateTime to,
}) {
  final start = dayOf(from);
  final days = max(0, daysBetween(start, dayOf(to))) + 1;
  final perDay = List<int>.filled(days, 0);
  for (final e in events) {
    if (!e.isRead || e.bookId != bookId) continue;
    final i = daysBetween(start, dayOf(e.time));
    if (i < 0) {
      // Read before the series starts: counts from the first day.
      perDay[0]++;
    } else if (i < days) {
      perDay[i]++;
    }
  }
  final out = <int>[];
  var running = 0;
  for (final n in perDay) {
    running += n;
    out.add(running);
  }
  return out;
}

/// Share of notifications that got a reaction (a confirmed chunk or a snooze)
/// within [window]. Only notifications whose window has closed are counted.
/// Returns null when there is nothing to measure yet.
double? responseRate({
  required List<Slot> slots,
  required List<ReadEvent> events,
  required DateTime now,
  Duration window = const Duration(minutes: 60),
}) {
  final closed = slots.where((s) => s.time.add(window).isBefore(now)).toList();
  if (closed.isEmpty) return null;
  var answered = 0;
  for (final s in closed) {
    final end = s.time.add(window);
    final hit = events
        .any((e) => !e.time.isBefore(s.time) && e.time.isBefore(end));
    if (hit) answered++;
  }
  return answered / closed.length;
}
