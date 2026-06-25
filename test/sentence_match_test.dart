import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/sentence_match.dart';

void main() {
  const sentences = [
    'Sing in me, Muse, and through me tell the story.',
    'That man skilled in all ways of contending.',
    'The wanderer, harried for years on end.',
  ];

  test('exact selection matches its sentence', () {
    expect(
      resolveSentenceIndex('That man skilled in all ways of contending.',
          sentences),
      1,
    );
  });

  test('a partial selection inside a sentence matches it', () {
    expect(resolveSentenceIndex('harried for years', sentences), 2);
  });

  test('matching ignores case and extra whitespace', () {
    expect(resolveSentenceIndex('  SING   in me,   muse ', sentences), 0);
  });

  test('a selection spanning a whole sentence plus extra still matches', () {
    expect(
      resolveSentenceIndex(
          'well: The wanderer, harried for years on end. And so', sentences),
      2,
    );
  });

  test('no match returns -1', () {
    expect(resolveSentenceIndex('something not in the text', sentences), -1);
  });

  test('empty selection returns -1', () {
    expect(resolveSentenceIndex('   ', sentences), -1);
  });
}
