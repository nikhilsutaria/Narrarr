import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/book.dart';
import 'package:narrarr/library/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late JsonLibraryRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('narrarr_lib_test');
    repo = JsonLibraryRepository(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Book book(String id, {int addedAtMs = 0}) => Book(
        id: id,
        title: 'Title $id',
        filePath: p.join(tmp.path, '$id.epub'),
        addedAtMs: addedAtMs,
      );

  test('add then all round-trips a book', () async {
    await repo.add(book('a'));
    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.first.id, 'a');
  });

  test('all is sorted by addedAt descending', () async {
    await repo.add(book('old', addedAtMs: 1));
    await repo.add(book('new', addedAtMs: 2));
    final ids = (await repo.all()).map((b) => b.id).toList();
    expect(ids, ['new', 'old']);
  });

  test('add upserts by id', () async {
    await repo.add(book('a'));
    await repo.add(book('a'));
    expect(await repo.all(), hasLength(1));
  });

  test('updateLocator persists the locator', () async {
    await repo.add(book('a'));
    await repo.updateLocator('a', '{"href":"x"}');
    expect((await repo.all()).first.lastLocatorJson, '{"href":"x"}');
  });

  test('remove deletes the book', () async {
    await repo.add(book('a'));
    await repo.remove('a');
    expect(await repo.all(), isEmpty);
  });
}
