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

  group('resolveAnchorIndex (#63)', () {
    const verse = [
      'And when at length the daughter of the Dawn,', // 0
      'The rosy-fingered Morn, appeared, we walked', // 1
      'Around the isle.', // 2
      'No.', // 3
      'And when at length the daughter of the Dawn,', // 4 (Homer repeats)
      'The rosy-fingered Morn, appeared, we rose', // 5
    ];

    test('an anchor starting with a whole sentence lands on it', () {
      expect(
          resolveAnchorIndex(
              'Around the isle. No. And when at length', verse),
          2);
    });

    test('an anchor that is the start of a long sentence lands on it', () {
      expect(resolveAnchorIndex('The rosy-fingered Morn, appeared, we ro', verse), 5);
    });

    test('a repeated line picks the occurrence nearest the page position', () {
      const a = 'And when at length the daughter of the Dawn, The rosy';
      expect(resolveAnchorIndex(a, verse), 0);
      expect(resolveAnchorIndex(a, verse, near: 0.9), 4);
      expect(resolveAnchorIndex(a, verse, near: 0.1), 0);
    });

    test('a short sentence inside the anchor does not win', () {
      // "No." is contained in the anchor but the anchor does not start with it.
      expect(resolveAnchorIndex('I said no. Around the isle.', verse), -1);
    });

    test('an anchor starting mid-sentence falls back to containment', () {
      expect(resolveAnchorIndex('Morn, appeared, we walked', verse), 1);
    });

    test('blank anchor gives -1', () {
      expect(resolveAnchorIndex('  ', verse), -1);
    });
  });
}
