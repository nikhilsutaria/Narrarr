import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/bookmark_repository.dart';
import 'package:narrarr/library/drift/library_database.dart';

void main() {
  late LibraryDatabase db;
  late BookmarkRepository repo;

  setUp(() {
    db = LibraryDatabase(NativeDatabase.memory());
    repo = BookmarkRepository(db);
  });
  tearDown(() => db.close());

  Future<int> add(String book, int at, {String snippet = 'A line.'}) =>
      repo.add(
        bookId: book,
        chapterHref: 'book-9.xhtml',
        sentenceIndex: at,
        snippet: snippet,
        createdAtMs: at,
      );

  test('add / list round-trips, newest first (#48)', () async {
    await add('b1', 1);
    await add('b1', 5);
    await add('b2', 3);
    final list = await repo.forBook('b1');
    expect(list.map((b) => b.sentenceIndex), [5, 1]);
    expect(list.first.chapterHref, 'book-9.xhtml');
    expect(list.first.snippet, 'A line.');
  });

  test('delete removes one; deleteForBook removes a book\'s bookmarks', () async {
    final id = await add('b1', 1);
    await add('b1', 2);
    await add('b2', 3);
    await repo.delete(id);
    expect((await repo.forBook('b1')).map((b) => b.sentenceIndex), [2]);
    await repo.deleteForBook('b1');
    expect(await repo.forBook('b1'), isEmpty);
    expect(await repo.forBook('b2'), hasLength(1));
  });

  test('long snippets are trimmed with an ellipsis', () async {
    await add('b1', 1, snippet: 'x' * 500);
    final s = (await repo.forBook('b1')).single.snippet;
    expect(s.length, BookmarkRepository.snippetMax);
    expect(s.endsWith('…'), isTrue);
  });
}
