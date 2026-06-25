import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'library_database.g.dart';

/// Library books table (Phase 1 Task 7 — replaces the JSON manifest store).
/// Row class is `BookRow` to avoid colliding with the domain [Book] model.
@DataClassName('BookRow')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get filePath => text()();
  TextColumn get coverPath => text().nullable()();
  IntColumn get addedAtMs => integer().withDefault(const Constant(0))();
  TextColumn get lastLocatorJson => text().nullable()();
  BoolColumn get isBundledSample =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-sentence measured timings (Phase 3). Cache key is
/// (bookId, chapterHref, voiceId, sentenceIndex); voice is part of the key so a
/// voice switch misses the cache rather than serving stale timings.
@DataClassName('SentenceTimingRow')
class SentenceTimings extends Table {
  TextColumn get bookId => text()();
  TextColumn get chapterHref => text()();
  TextColumn get voiceId => text()();
  IntColumn get sentenceIndex => integer()();
  IntColumn get startMs => integer()();
  IntColumn get durationMs => integer()();

  @override
  Set<Column> get primaryKey => {bookId, chapterHref, voiceId, sentenceIndex};
}

@DriftDatabase(tables: [Books, SentenceTimings])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(sentenceTimings);
        },
      );

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'library.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
