import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/drift/library_database.dart';
import 'package:narrarr/narration/pronunciation_repository.dart';

void main() {
  late LibraryDatabase db;
  late PronunciationRepository repo;

  setUp(() {
    db = LibraryDatabase(NativeDatabase.memory());
    repo = PronunciationRepository(db);
  });
  tearDown(() => db.close());

  Future<void> save(String w, String r, {String? book}) => repo.save(
      word: w, replacement: r, caseSensitive: false, bookId: book, nowMs: 1);

  test('forBook returns global entries plus that book\'s (#47)', () async {
    await save('Circe', 'SUR-see');
    await save('Ithaca', 'ITH-a-ka', book: 'odyssey');
    await save('Hermione', 'her-MY-oh-nee', book: 'potter');
    final words = (await repo.forBook('odyssey')).map((e) => e.word).toSet();
    expect(words, {'Circe', 'Ithaca'});
  });

  test('saving the same word in the same scope updates instead of duplicating',
      () async {
    await save('Circe', 'SUR-see');
    await save('circe', 'KEER-keh');
    final all = await repo.all();
    expect(all, hasLength(1));
    expect(all.single.replacement, 'KEER-keh');
    // Same word, different scope → a separate entry.
    await save('Circe', 'book-specific', book: 'odyssey');
    expect(await repo.all(), hasLength(2));
  });

  test('all() lists global entries first; deleteForBook clears a book', () async {
    await save('Zed', 'zee', book: 'b1');
    await save('Alpha', 'al-fa');
    expect((await repo.all()).map((e) => e.word), ['Alpha', 'Zed']);
    await repo.deleteForBook('b1');
    expect((await repo.all()).map((e) => e.word), ['Alpha']);
  });

  test('blank words or replacements are ignored', () async {
    await save('  ', 'x');
    await save('word', '  ');
    expect(await repo.all(), isEmpty);
  });
}
