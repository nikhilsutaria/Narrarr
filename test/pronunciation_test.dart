import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/pronunciation.dart';

PronunciationEntry e(String word, String say,
        {bool caseSensitive = false, String? bookId}) =>
    (id: 0, bookId: bookId, word: word, replacement: say, caseSensitive: caseSensitive);

void main() {
  test('replaces whole words only (#47)', () {
    final d = PronunciationDictionary([e('Ulysses', 'you-LISS-eez')]);
    expect(d.apply('Then Ulysses spoke.'), 'Then you-LISS-eez spoke.');
    expect(d.apply('Ulyssesian'), 'Ulyssesian');
    expect(d.apply('(Ulysses)'), '(you-LISS-eez)');
    expect(d.apply("Ulysses' ship"), "you-LISS-eez' ship");
  });

  test('is case-insensitive by default, case-sensitive on request', () {
    final d = PronunciationDictionary([
      e('hermione', 'her-MY-oh-nee'),
      e('Will', 'William', caseSensitive: true),
    ]);
    expect(d.apply('HERMIONE and Hermione'), 'her-MY-oh-nee and her-MY-oh-nee');
    expect(d.apply('Will said he will go.'), 'William said he will go.');
  });

  test('longer phrases win over words they contain', () {
    final d = PronunciationDictionary([
      e('Sea', 'see'),
      e('Wine-dark Sea', 'wine dark sea of Homer'),
    ]);
    expect(d.apply('Across the wine-dark sea.'), 'Across the wine dark sea of Homer.');
  });

  test('replacements are not re-processed by other entries', () {
    final d = PronunciationDictionary([e('Zeus', 'Jove'), e('Jove', 'Zoose')]);
    expect(d.apply('Zeus and Jove'), 'Jove and Zoose');
  });

  test('a book entry overrides a global entry for the same word', () {
    final d = PronunciationDictionary([
      e('Circe', 'SUR-see'),
      e('circe', 'KEER-keh', bookId: 'odyssey'),
    ]);
    expect(d.apply('Circe smiled.'), 'KEER-keh smiled.');
  });

  test('handles non-ASCII letters and regex metacharacters in words', () {
    final d = PronunciationDictionary([e('Alcinoüs', 'al-SIN-oh-us'), e('C++', 'C plus plus')]);
    expect(d.apply('King Alcinoüs!'), 'King al-SIN-oh-us!');
    expect(d.apply('I like C++ a lot'), 'I like C plus plus a lot');
  });

  test('an empty dictionary returns the text unchanged', () {
    expect(PronunciationDictionary(const []).apply('As is.'), 'As is.');
  });
}
