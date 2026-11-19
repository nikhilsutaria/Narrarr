import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/book_files.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory books;
  late Directory elsewhere;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bf');
    books = Directory(p.join(root.path, 'books'))..createSync();
    elsewhere = Directory(p.join(root.path, 'Download'))..createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  File make(Directory d, String name, {Duration age = const Duration(days: 1)}) {
    final f = File(p.join(d.path, name))..writeAsStringSync('epub');
    f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  group('deleteBookCopy (#69)', () {
    test("deletes Narrarr's copy in the books folder", () async {
      final copy = make(books, 'a-1.epub');
      await deleteBookCopy(copy.path, books);
      expect(copy.existsSync(), isFalse);
    });

    test('never deletes a file outside the books folder', () async {
      final original = make(elsewhere, 'a.epub');
      await deleteBookCopy(original.path, books);
      expect(original.existsSync(), isTrue);
      // Not even via a path that walks out of the folder.
      await deleteBookCopy(p.join(books.path, '..', 'Download', 'a.epub'), books);
      expect(original.existsSync(), isTrue);
    });

    test('a missing file is fine', () async {
      await deleteBookCopy(p.join(books.path, 'gone.epub'), books);
    });
  });

  group('deleteOrphanBookCopies (#69)', () {
    test('removes copies no book refers to and keeps the rest', () async {
      final kept = make(books, 'kept.epub');
      final orphan = make(books, 'orphan.epub');
      final original = make(elsewhere, 'orphan.epub');
      await deleteOrphanBookCopies(books, {kept.path});
      expect(kept.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
      expect(original.existsSync(), isTrue);
    });

    test('leaves a just-written copy alone (an import may be in flight)',
        () async {
      final fresh = make(books, 'importing.epub', age: Duration.zero);
      await deleteOrphanBookCopies(books, const {});
      expect(fresh.existsSync(), isTrue);
    });

    test('a missing books folder is fine', () async {
      books.deleteSync(recursive: true);
      await deleteOrphanBookCopies(books, const {});
    });
  });
}
