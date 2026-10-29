import 'package:flutter_test/flutter_test.dart';
import 'package:micro_reader/models.dart';
import 'package:micro_reader/stats.dart';

void main() {
  // Thursday.
  final now = DateTime(2026, 10, 29, 20, 0);

  Set<DateTime> days(List<int> daysAgo) =>
      {for (final n in daysAgo) addDays(dayOf(now), -n)};

  ReadEvent read(DateTime t, {String book = 'a', String type = 'read'}) =>
      ReadEvent(time: t, bookId: book, chunk: 0, type: type);

  group('computeStreak', () {
    test('no reads gives 0', () {
      expect(computeStreak({}, now), 0);
    });

    test('counts consecutive days including today', () {
      expect(computeStreak(days([0, 1, 2, 3, 4]), now), 5);
    });

    test('today not read yet does not break the streak', () {
      expect(computeStreak(days([1, 2, 3]), now), 3);
    });

    test('one missed day in a week is forgiven', () {
      // Read Thu, Wed, (Tue missed), Mon.
      expect(computeStreak(days([0, 1, 3]), now), 3);
    });

    test('two missed days in the same week end the streak', () {
      // Read Thu; Wed and Tue missed; Mon read.
      expect(computeStreak(days([0, 3]), now), 1);
    });

    test('a forgiven day does not add to the count', () {
      expect(computeStreak(days([1, 3]), now), 2);
    });

    test('a long gap resets it', () {
      expect(computeStreak(days([10, 11, 12]), now), 0);
    });
  });

  group('paceFor', () {
    test('projects the finish from the average pace', () {
      final p = paceFor(
        totalChunks: 100,
        position: 20,
        startedAt: addDays(dayOf(now), -3), // 4 days including today
        now: now,
      );
      expect(p.perDay, 5);
      expect(p.projectedFinish, addDays(dayOf(now), 16));
      expect(p.goalFinish, isNull);
      expect(p.daysAhead, isNull);
    });

    test('compares the projection with the goal', () {
      final p = paceFor(
        totalChunks: 100,
        position: 20,
        startedAt: addDays(dayOf(now), -3),
        goalStart: addDays(dayOf(now), -3),
        goalDays: 30,
        now: now,
      );
      // Goal finish: start + 29 days = 26 days from today; projected: 16.
      expect(p.daysAhead, 10);
    });

    test('no reads yet gives no projection', () {
      final p = paceFor(
          totalChunks: 100, position: 0, startedAt: now, now: now);
      expect(p.projectedFinish, isNull);
    });

    test('finished book projects today', () {
      final p = paceFor(
          totalChunks: 10, position: 10, startedAt: now, now: now);
      expect(p.projectedFinish, dayOf(now));
      expect(p.remaining, 0);
    });
  });

  group('cumulativeReads', () {
    test('accumulates per day for one book', () {
      final events = [
        read(addDays(dayOf(now), -2)),
        read(addDays(dayOf(now), -2)),
        read(addDays(dayOf(now), 0)),
        read(addDays(dayOf(now), -1), book: 'other'),
        read(addDays(dayOf(now), -1), type: 'snooze'),
      ];
      final series = cumulativeReads(
        events: events,
        bookId: 'a',
        from: addDays(dayOf(now), -2),
        to: now,
      );
      expect(series, [2, 2, 3]);
    });
  });

  group('responseRate', () {
    Slot slot(DateTime t) => Slot(time: t, bookId: 'a', id: 1);

    test('is null with nothing to measure', () {
      expect(responseRate(slots: [], events: [], now: now), isNull);
      // Window still open: not counted yet.
      expect(
          responseRate(
              slots: [slot(now.subtract(const Duration(minutes: 10)))],
              events: [],
              now: now),
          isNull);
    });

    test('counts reactions inside the window', () {
      final s1 = now.subtract(const Duration(hours: 5));
      final s2 = now.subtract(const Duration(hours: 4));
      final s3 = now.subtract(const Duration(hours: 3));
      final events = [
        read(s1.add(const Duration(minutes: 5))),
        read(s2.add(const Duration(minutes: 200))), // outside every window
        read(s3.add(const Duration(minutes: 20)), type: 'snooze'),
      ];
      final rate = responseRate(
          slots: [slot(s1), slot(s2), slot(s3)], events: events, now: now);
      expect(rate, closeTo(2 / 3, 1e-9));
    });
  });
}
