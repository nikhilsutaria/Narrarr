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

  /// Fraction of the book's narratable text read so far (#46; schema v3).
  RealColumn get progress => real().nullable()();

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

/// User bookmarks (#48; schema v4): a sentence in a spine chapter, with a
/// text snippet for the list. Deleted with the book.
@DataClassName('BookmarkRow')
class Bookmarks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookId => text()();
  TextColumn get chapterHref => text()();
  IntColumn get sentenceIndex => integer()();
  TextColumn get snippet => text()();
  IntColumn get createdAtMs => integer()();
}

/// User pronunciation fixes (#47; schema v5). A null [bookId] applies to
/// every book.
@DataClassName('PronunciationRow')
class Pronunciations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get bookId => text().nullable()();
  TextColumn get word => text()();
  TextColumn get replacement => text()();
  BoolColumn get caseSensitive =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAtMs => integer()();
}

/// The app's single database connection. Every repository shares it — two
/// connections to the same SQLite file race (drift warns about exactly this).
LibraryDatabase appDatabase() => _appDatabase ??= LibraryDatabase();
LibraryDatabase? _appDatabase;

@DriftDatabase(tables: [Books, SentenceTimings, Bookmarks, Pronunciations])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(sentenceTimings);
          if (from < 3) await m.addColumn(books, books.progress);
          if (from < 4) await m.createTable(bookmarks);
          if (from < 5) await m.createTable(pronunciations);
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
