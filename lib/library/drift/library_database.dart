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

@DriftDatabase(tables: [Books])
class LibraryDatabase extends _$LibraryDatabase {
  LibraryDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'library.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
