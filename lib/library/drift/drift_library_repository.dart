import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../book.dart';
import '../library_repository.dart';
import 'library_database.dart';

/// SQLite-backed [LibraryRepository] (the MVP spec's choice).
class DriftLibraryRepository implements LibraryRepository {
  DriftLibraryRepository(this.db);

  final LibraryDatabase db;

  @override
  Future<List<Book>> all() async {
    final rows = await (db.select(db.books)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAtMs)]))
        .get();
    return rows.map(_toBook).toList();
  }

  @override
  Future<void> add(Book book) =>
      db.into(db.books).insertOnConflictUpdate(_toRow(book));

  @override
  Future<void> remove(String id) =>
      (db.delete(db.books)..where((t) => t.id.equals(id))).go();

  @override
  Future<void> updateLocator(String id, String locatorJson) =>
      (db.update(db.books)..where((t) => t.id.equals(id)))
          .write(BooksCompanion(lastLocatorJson: Value(locatorJson)));

  Book _toBook(BookRow r) => Book(
        id: r.id,
        title: r.title,
        author: r.author,
        filePath: r.filePath,
        coverPath: r.coverPath,
        addedAtMs: r.addedAtMs,
        lastLocatorJson: r.lastLocatorJson,
        isBundledSample: r.isBundledSample,
      );

  BooksCompanion _toRow(Book b) => BooksCompanion(
        id: Value(b.id),
        title: Value(b.title),
        author: Value(b.author),
        filePath: Value(b.filePath),
        coverPath: Value(b.coverPath),
        addedAtMs: Value(b.addedAtMs),
        lastLocatorJson: Value(b.lastLocatorJson),
        isBundledSample: Value(b.isBundledSample),
      );
}

/// Opens the app's library (drift), one-time migrating any legacy JSON manifest
/// from the previous store.
Future<LibraryRepository> openAppLibrary() async {
  final repo = DriftLibraryRepository(LibraryDatabase());
  await _migrateJsonIfPresent(repo);
  return repo;
}

Future<void> _migrateJsonIfPresent(DriftLibraryRepository repo) async {
  if ((await repo.all()).isNotEmpty) return;
  final support = await getApplicationSupportDirectory();
  final legacy = File(p.join(support.path, 'library', 'library.json'));
  if (!await legacy.exists()) return;
  final json = JsonLibraryRepository(legacy.parent);
  for (final book in await json.all()) {
    await repo.add(book);
  }
  await legacy.rename('${legacy.path}.migrated');
}
