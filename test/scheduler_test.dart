import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:micro_reader/models.dart';
import 'package:micro_reader/scheduler.dart';

void main() {
  final now = DateTime(2026, 10, 29, 12, 0);
  const start = 9 * 60;
  const end = 22 * 60;
  const gap = Duration(minutes: 45);

  List<DateTime> plan(List<int> counts,
          {int seed = 1, DateTime? lastSlot, int s = start, int e = end}) =>
      planSlots(
        now: now,
        perDayCounts: counts,
        awakeStartMin: s,
        awakeEndMin: e,
        minGap: gap,
        rng: Random(seed),
        lastSlot: lastSlot,
      );

  group('planSlots', () {
    test('stays inside awake hours, after now, and respects the gap', () {
      for (var seed = 0; seed < 50; seed++) {
        final slots = plan([4, 5, 5], seed: seed);
        expect(slots.length, 14);
        for (final t in slots) {
          expect(t.isAfter(now), isTrue);
          final minutes = t.hour * 60 + t.minute;
          expect(minutes, greaterThanOrEqualTo(start));
          expect(minutes, lessThanOrEqualTo(end));
        }
        for (var i = 1; i < slots.length; i++) {
          expect(slots[i].difference(slots[i - 1]) >= gap, isTrue);
        }
        expect(slots.take(4).every((t) => t.day == now.day), isTrue);
      }
    });

    test('places fewer notifications when the window is too short', () {
      final slots = plan([10], s: 9 * 60, e: 10 * 60 + 30);
      // today's window is only 12:01 -> 10:30 of the same day = empty
      expect(slots, isEmpty);
      final tomorrow = plan([0, 10], s: 9 * 60, e: 10 * 60);
      expect(tomorrow.length, 2);
    });

    test('keeps the gap from the last fired notification', () {
      final slots = plan([3], lastSlot: now);
      expect(slots.first.isBefore(now.add(gap)), isFalse);
    });

    test('is deterministic for a given seed', () {
      expect(plan([3, 3], seed: 7), plan([3, 3], seed: 7));
    });

    test('different seeds give different times', () {
      expect(plan([3], seed: 1), isNot(plan([3], seed: 2)));
    });

    test('zero count places nothing', () {
      expect(plan([0, 0]), isEmpty);
    });
  });

  group('dailyTarget', () {
    Book book(String id, int total, int pos,
            {int? goalDays, DateTime? goalStart, bool active = true}) =>
        Book(
          id: id,
          title: id,
          totalChunks: total,
          addedAt: now,
          position: pos,
          active: active,
          goalDays: goalDays,
          goalStart: goalStart,
        );

    int target(List<Book> books,
            {Settings settings = const Settings(),
            Map<String, int> readToday = const {}}) =>
        dailyTarget(
          books: books,
          settings: settings,
          now: now,
          readTodayByBook: readToday,
        );

    test('is 0 when nothing is active', () {
      expect(target([]), 0);
      expect(target([book('a', 100, 0, active: false)]), 0);
      expect(target([book('a', 100, 100)]), 0);
    });

    test('goal pace: remaining chunks spread over the days left', () {
      final b = book('a', 30, 0, goalDays: 15, goalStart: now);
      expect(target([b]), 2);
    });

    test('is clamped to the daily cap', () {
      final b = book('a', 300, 0, goalDays: 15, goalStart: now);
      expect(target([b]), 8);
      expect(
          target([b], settings: const Settings(dailyCap: 5)), 5);
    });

    test('stays steady while reading through the day', () {
      final b = book('a', 30, 3, goalDays: 15, goalStart: now);
      expect(target([b], readToday: {'a': 3}), 2);
    });

    test('without a goal, the default is shared between active books', () {
      final a = book('a', 100, 0);
      final b = book('b', 100, 0);
      expect(target([a]), 5);
      expect(target([a, b]), 6); // ceil(5/2) each
    });

    test('goal in the past still asks for at least the remaining work', () {
      final b = book('a', 20, 10,
          goalDays: 5, goalStart: DateTime(2026, 10, 1));
      expect(target([b]), 8); // 10 remaining, 1 day left, capped at 8
    });
  });
}
