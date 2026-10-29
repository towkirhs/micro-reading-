enum BlockKind { paragraph, heading, image, table }

int countWords(String s) {
  final t = s.trim();
  return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).length;
}

/// One piece of book content: a paragraph, a heading, an image or a table.
class Block {
  const Block._(this.kind, {this.text, this.path, this.rows});
  const Block.paragraph(String text) : this._(BlockKind.paragraph, text: text);
  const Block.heading(String text) : this._(BlockKind.heading, text: text);
  const Block.image(String path) : this._(BlockKind.image, path: path);
  Block.table(List<List<String>> rows) : this._(BlockKind.table, rows: rows);

  final BlockKind kind;
  final String? text;

  /// Image path relative to the book folder, e.g. `img/0.png`.
  final String? path;
  final List<List<String>>? rows;

  int get words {
    switch (kind) {
      case BlockKind.paragraph:
      case BlockKind.heading:
        return countWords(text ?? '');
      case BlockKind.table:
        return (rows ?? const <List<String>>[]).fold<int>(
            0, (a, r) => a + r.fold<int>(0, (b, c) => b + countWords(c)));
      case BlockKind.image:
        return 0;
    }
  }

  Map<String, Object?> toJson() => {
        'k': kind.name,
        if (text != null) 't': text,
        if (path != null) 'p': path,
        if (rows != null) 'r': rows,
      };

  factory Block.fromJson(Map<String, dynamic> j) {
    return Block._(
      BlockKind.values.byName(j['k'] as String),
      text: j['t'] as String?,
      path: j['p'] as String?,
      rows: (j['r'] as List?)
          ?.map((r) => (r as List).map((c) => c as String).toList())
          .toList(),
    );
  }
}

/// A short reading unit: whole blocks only, in book order.
class Chunk {
  Chunk(this.blocks, this.chapter);

  final List<Block> blocks;

  /// Title of the last heading seen up to and including this chunk.
  final String? chapter;

  int get words => blocks.fold<int>(0, (a, b) => a + b.words);

  Map<String, Object?> toJson() => {
        if (chapter != null) 'c': chapter,
        'b': blocks.map((b) => b.toJson()).toList(),
      };

  factory Chunk.fromJson(Map<String, dynamic> j) => Chunk(
        (j['b'] as List)
            .map((b) => Block.fromJson(b as Map<String, dynamic>))
            .toList(),
        j['c'] as String?,
      );
}

class Book {
  Book({
    required this.id,
    required this.title,
    required this.totalChunks,
    required this.addedAt,
    this.position = 0,
    this.active = true,
    this.goalDays,
    this.goalStart,
  });

  final String id;
  final String title;
  final int totalChunks;
  final DateTime addedAt;

  /// Index of the next chunk to confirm. Everything before it is read.
  int position;
  bool active;
  int? goalDays;
  DateTime? goalStart;

  bool get finished => position >= totalChunks;
  int get remaining => totalChunks - position;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'total': totalChunks,
        'added': addedAt.toIso8601String(),
        'pos': position,
        'active': active,
        if (goalDays != null) 'goalDays': goalDays,
        if (goalStart != null) 'goalStart': goalStart!.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        totalChunks: j['total'] as int,
        addedAt: DateTime.parse(j['added'] as String),
        position: j['pos'] as int,
        active: j['active'] as bool,
        goalDays: j['goalDays'] as int?,
        goalStart: j['goalStart'] == null
            ? null
            : DateTime.parse(j['goalStart'] as String),
      );
}

class Settings {
  const Settings({
    this.awakeStartMin = 9 * 60,
    this.awakeEndMin = 22 * 60,
    this.dailyCap = 8,
    this.defaultPerDay = 5,
    this.minGapMin = 45,
  });

  /// Minutes after midnight.
  final int awakeStartMin;
  final int awakeEndMin;
  final int dailyCap;
  final int defaultPerDay;
  final int minGapMin;

  Settings copyWith({
    int? awakeStartMin,
    int? awakeEndMin,
    int? dailyCap,
    int? defaultPerDay,
    int? minGapMin,
  }) =>
      Settings(
        awakeStartMin: awakeStartMin ?? this.awakeStartMin,
        awakeEndMin: awakeEndMin ?? this.awakeEndMin,
        dailyCap: dailyCap ?? this.dailyCap,
        defaultPerDay: defaultPerDay ?? this.defaultPerDay,
        minGapMin: minGapMin ?? this.minGapMin,
      );

  Map<String, Object?> toJson() => {
        'start': awakeStartMin,
        'end': awakeEndMin,
        'cap': dailyCap,
        'perDay': defaultPerDay,
        'gap': minGapMin,
      };

  factory Settings.fromJson(Map<String, dynamic> j) {
    const d = Settings();
    return Settings(
      awakeStartMin: j['start'] as int? ?? d.awakeStartMin,
      awakeEndMin: j['end'] as int? ?? d.awakeEndMin,
      dailyCap: j['cap'] as int? ?? d.dailyCap,
      defaultPerDay: j['perDay'] as int? ?? d.defaultPerDay,
      minGapMin: j['gap'] as int? ?? d.minGapMin,
    );
  }
}

/// `type` is `read` (chunk confirmed) or `snooze`.
class ReadEvent {
  const ReadEvent({
    required this.time,
    required this.bookId,
    required this.chunk,
    required this.type,
  });

  final DateTime time;
  final String bookId;
  final int chunk;
  final String type;

  bool get isRead => type == 'read';

  Map<String, Object?> toJson() => {
        't': time.toIso8601String(),
        'b': bookId,
        'c': chunk,
        'y': type,
      };

  factory ReadEvent.fromJson(Map<String, dynamic> j) => ReadEvent(
        time: DateTime.parse(j['t'] as String),
        bookId: j['b'] as String,
        chunk: j['c'] as int,
        type: j['y'] as String,
      );
}

/// A scheduled (or already fired) notification.
class Slot {
  const Slot({required this.time, required this.bookId, required this.id});

  final DateTime time;
  final String bookId;
  final int id;

  Map<String, Object?> toJson() =>
      {'t': time.toIso8601String(), 'b': bookId, 'i': id};

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        time: DateTime.parse(j['t'] as String),
        bookId: j['b'] as String,
        id: j['i'] as int,
      );
}
