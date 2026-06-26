import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/book.dart';
import 'package:narrarr/library/drift/drift_library_repository.dart';
import 'package:narrarr/library/drift/library_database.dart';

/// CRUD coverage for the production SQLite-backed library repository, against an
/// in-memory drift database (no platform / path_provider dependency).
void main() {
  late LibraryDatabase db;
  late DriftLibraryRepository repo;

  setUp(() {
    db = LibraryDatabase(NativeDatabase.memory());
    repo = DriftLibraryRepository(db);
  });
  tearDown(() => db.close());

  Book book(String id, {int addedAtMs = 0, String title = 'T'}) => Book(
        id: id,
        title: title,
        author: 'A',
        filePath: '/books/$id.epub',
        coverPath: '/covers/$id.png',
        addedAtMs: addedAtMs,
        lastLocatorJson: null,
        isBundledSample: false,
      );

  test('add then all round-trips every field', () async {
    await repo.add(book('b1', addedAtMs: 10, title: 'Odyssey'));
    final all = await repo.all();
    expect(all.length, 1);
    final b = all.single;
    expect(b.id, 'b1');
    expect(b.title, 'Odyssey');
    expect(b.author, 'A');
    expect(b.filePath, '/books/b1.epub');
    expect(b.coverPath, '/covers/b1.png');
    expect(b.addedAtMs, 10);
    expect(b.isBundledSample, false);
  });

  test('all() orders by addedAtMs descending (newest first)', () async {
    await repo.add(book('old', addedAtMs: 1));
    await repo.add(book('new', addedAtMs: 3));
    await repo.add(book('mid', addedAtMs: 2));
    expect((await repo.all()).map((b) => b.id), ['new', 'mid', 'old']);
  });

  test('add upserts on conflicting id (insert-or-update)', () async {
    await repo.add(book('b1', title: 'First'));
    await repo.add(book('b1', title: 'Second'));
    final all = await repo.all();
    expect(all.length, 1);
    expect(all.single.title, 'Second');
  });

  test('remove deletes by id', () async {
    await repo.add(book('b1'));
    await repo.add(book('b2'));
    await repo.remove('b1');
    expect((await repo.all()).map((b) => b.id), ['b2']);
  });

  test('updateLocator persists the reading position', () async {
    await repo.add(book('b1'));
    await repo.updateLocator('b1', '{"href":"ch1","type":"x"}');
    expect((await repo.all()).single.lastLocatorJson,
        '{"href":"ch1","type":"x"}');
  });

  test('updateLocator on a missing id is a no-op (does not throw)', () async {
    await repo.updateLocator('missing', '{}');
    expect(await repo.all(), isEmpty);
  });
}
