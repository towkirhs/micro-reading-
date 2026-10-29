import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'epub_import.dart';
import 'models.dart';
import 'notifications.dart';
import 'scheduler.dart';
import 'stats.dart';

const int kSnoozeMinutes = 20;
const int _firstSlotId = 1000;
const int _planDays = 3;

const List<String> _nudges = [
  'A few minutes of your story are waiting.',
  'Your book misses you. One small piece?',
  'Got a minute? The next bit is short.',
  'Plot twist: it only takes two minutes.',
  'Quick one: pick up where you left off.',
  'Your next piece is ready.',
];

/// All app state, kept in one JSON file plus one folder per book.
class AppStore extends ChangeNotifier {
  AppStore._(this._root, this._notifications);

  final Directory _root;
  final NotificationService _notifications;
  final Random _rng = Random();
  final Map<String, List<Chunk>> _chunkCache = {};

  List<Book> books = [];
  Settings settings = const Settings();
  List<ReadEvent> events = [];
  List<Slot> slots = [];

  static Future<AppStore> open(NotificationService notifications) async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(docs.path, 'micro_reader'))
      ..createSync(recursive: true);
    final store = AppStore._(root, notifications);
    await store._load();
    return store;
  }

  File get _stateFile => File(p.join(_root.path, 'state.json'));

  Directory bookDir(String id) => Directory(p.join(_root.path, 'books', id));

  Future<void> _load() async {
    if (!_stateFile.existsSync()) return;
    final j = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
    books = (j['books'] as List? ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    settings = Settings.fromJson(
        (j['settings'] as Map<String, dynamic>?) ?? <String, dynamic>{});
    events = (j['events'] as List? ?? [])
        .map((e) => ReadEvent.fromJson(e as Map<String, dynamic>))
        .toList();
    slots = (j['slots'] as List? ?? [])
        .map((e) => Slot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save() async {
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'books': books.map((b) => b.toJson()).toList(),
      'settings': settings.toJson(),
      'events': events.map((e) => e.toJson()).toList(),
      'slots': slots.map((s) => s.toJson()).toList(),
    }));
    await tmp.rename(_stateFile.path);
  }

  Book? bookById(String id) {
    for (final b in books) {
      if (b.id == id) return b;
    }
    return null;
  }

  List<Chunk> chunksOf(Book b) => _chunkCache.putIfAbsent(b.id, () {
        final file = File(p.join(bookDir(b.id).path, 'chunks.json'));
        final list = jsonDecode(file.readAsStringSync()) as List;
        return list
            .map((e) => Chunk.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  // --- today's numbers -----------------------------------------------------

  int readToday([String? bookId]) =>
      readCountOn(events, DateTime.now(), bookId: bookId);

  Map<String, int> _readTodayByBook() =>
      {for (final b in books) b.id: readToday(b.id)};

  int todayTarget() {
    final target = dailyTarget(
      books: books,
      settings: settings,
      now: DateTime.now(),
      readTodayByBook: _readTodayByBook(),
    );
    return target == 0 ? 0 : max(target, readToday());
  }

  int get streak => computeStreak(readDays(events), DateTime.now());

  /// 0..1, or null when there is nothing to measure yet.
  double? get responseRateNow =>
      responseRate(slots: slots, events: events, now: DateTime.now());

  DateTime? lastReadTime(Book b) {
    DateTime? last;
    for (final e in events) {
      if (e.isRead && e.bookId == b.id && (last == null || e.time.isAfter(last))) {
        last = e.time;
      }
    }
    return last;
  }

  // --- actions -------------------------------------------------------------

  /// Imports an EPUB file. Throws on unreadable files.
  Future<Book> importEpub(String path) async {
    final bytes = await File(path).readAsBytes();
    final result = await compute(importEpubBytes, bytes);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = bookDir(id)..createSync(recursive: true);
    final images = (result['images']! as Map).cast<String, Uint8List>();
    for (final entry in images.entries) {
      final file = File(p.join(dir.path, entry.key));
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(entry.value);
    }
    await File(p.join(dir.path, 'chunks.json'))
        .writeAsString(result['chunksJson']! as String);
    var title = (result['title']! as String).trim();
    if (title.isEmpty) title = p.basenameWithoutExtension(path);
    final book = Book(
      id: id,
      title: title,
      totalChunks: result['count']! as int,
      addedAt: DateTime.now(),
    );
    books.add(book);
    await _save();
    notifyListeners();
    await replan();
    return book;
  }

  /// Confirms the pending chunk as read and moves on to the next one.
  Future<void> markRead(Book b) async {
    if (b.finished) return;
    events.add(ReadEvent(
        time: DateTime.now(), bookId: b.id, chunk: b.position, type: 'read'));
    b.position++;
    await _save();
    notifyListeners();
    await replan();
  }

  /// Keeps the same chunk pending and reminds again in [kSnoozeMinutes].
  Future<void> snooze(Book b) async {
    events.add(ReadEvent(
        time: DateTime.now(), bookId: b.id, chunk: b.position, type: 'snooze'));
    await _notifications.schedule(
      id: NotificationService.snoozeId,
      when: DateTime.now().add(const Duration(minutes: kSnoozeMinutes)),
      title: '📖 ${b.title}',
      body: 'Snooze over. Ready for that piece now?',
      bookId: b.id,
    );
    await _save();
    notifyListeners();
  }

  Future<void> setActive(Book b, bool active) async {
    b.active = active;
    await _save();
    notifyListeners();
    await replan();
  }

  Future<void> setGoal(Book b, int? days) async {
    b.goalDays = days;
    b.goalStart = days == null ? null : dayOf(DateTime.now());
    await _save();
    notifyListeners();
    await replan();
  }

  Future<void> deleteBook(Book b) async {
    books.remove(b);
    _chunkCache.remove(b.id);
    final dir = bookDir(b.id);
    if (dir.existsSync()) await dir.delete(recursive: true);
    await _save();
    notifyListeners();
    await replan();
  }

  Future<void> updateSettings(Settings s) async {
    settings = s;
    await _save();
    notifyListeners();
    await replan();
  }

  Future<void> sendTestNotification() => _notifications.schedule(
        id: NotificationService.testId,
        when: DateTime.now().add(const Duration(seconds: 15)),
        title: '📖 Test notification',
        body: 'If you can read this, reminders work on this phone.',
        bookId: books.isEmpty ? '' : books.first.id,
      );

  /// Throws away future notifications and plans fresh random ones for the
  /// next few days. Safe to call at any time.
  Future<void> replan() async {
    final now = DateTime.now();
    for (final s in slots.where((s) => s.time.isAfter(now))) {
      await _notifications.cancel(s.id);
    }
    slots.removeWhere((s) => s.time.isAfter(now));
    slots.removeWhere(
        (s) => s.time.isBefore(now.subtract(const Duration(days: 60))));
    events.removeWhere(
        (e) => e.time.isBefore(now.subtract(const Duration(days: 400))));

    final active = books.where((b) => b.active && !b.finished).toList();
    if (active.isNotEmpty) {
      final target = dailyTarget(
        books: books,
        settings: settings,
        now: now,
        readTodayByBook: _readTodayByBook(),
      );
      final todayLeft = max(0, target - readToday());
      DateTime? lastFired;
      for (final s in slots) {
        if (lastFired == null || s.time.isAfter(lastFired)) lastFired = s.time;
      }
      final times = planSlots(
        now: now,
        perDayCounts: [todayLeft, for (var i = 1; i < _planDays; i++) target],
        awakeStartMin: settings.awakeStartMin,
        awakeEndMin: settings.awakeEndMin,
        minGap: Duration(minutes: settings.minGapMin),
        rng: _rng,
        lastSlot: lastFired,
      );
      var id = _firstSlotId;
      for (final t in times) {
        final book = active[_rng.nextInt(active.length)];
        slots.add(Slot(time: t, bookId: book.id, id: id));
        try {
          await _notifications.schedule(
            id: id,
            when: t,
            title: '📖 ${book.title}',
            body: _nudges[_rng.nextInt(_nudges.length)],
            bookId: book.id,
          );
        } catch (e) {
          debugPrint('Could not schedule notification $id: $e');
        }
        id++;
      }
    }
    await _save();
    notifyListeners();
  }
}
