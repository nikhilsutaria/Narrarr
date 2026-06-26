import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/book_position.dart';

void main() {
  const spine = <SpineChapter>[
    (hrefHint: 'cover.xhtml', sentences: ['Cover.']),
    (
      hrefHint: 'book-9.xhtml',
      sentences: [
        'Sing in me, Muse, and through me tell the story.',
        'That man skilled in all ways of contending.',
        'The wanderer, harried for years on end.',
      ],
    ),
    (
      hrefHint: 'book-10.xhtml',
      sentences: ['We came to the Aeolian island next.', 'There Aeolus lived.'],
    ),
  ];

  test('matches the chapter by href fragment and the sentence by highlight', () {
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'EPUB/text/book-9.xhtml',
      highlightText: 'That man skilled in all ways of contending.',
    );
    expect(pos, (spineIndex: 1, sentenceIndex: 1));
  });

  test('a partial highlight inside a sentence still resolves it', () {
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'OPS/book-10.xhtml',
      highlightText: 'Aeolus lived',
    );
    expect(pos, (spineIndex: 2, sentenceIndex: 1));
  });

  test('falls back to sentence 0 when the chapter matches but text does not',
      () {
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'book-9.xhtml',
      highlightText: 'nothing that appears in this chapter',
    );
    expect(pos, (spineIndex: 1, sentenceIndex: 0));
  });

  test('uses progression to estimate the sentence when no text is given', () {
    // chapter has 3 sentences; 0.7 -> floor(0.7*3) = 2
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'book-9.xhtml',
      progression: 0.7,
    );
    expect(pos, (spineIndex: 1, sentenceIndex: 2));
  });

  test('progression of 1.0 clamps to the last sentence', () {
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'book-9.xhtml',
      progression: 1.0,
    );
    expect(pos, (spineIndex: 1, sentenceIndex: 2));
  });

  test('returns null when the locator chapter is not in the narratable spine',
      () {
    final pos = resolveBookPosition(
      spine: spine,
      locatorHref: 'EPUB/text/footnotes.xhtml',
      highlightText: 'anything',
    );
    expect(pos, isNull);
  });

  test('returns null for an empty spine', () {
    expect(
      resolveBookPosition(spine: const [], locatorHref: 'book-9.xhtml'),
      isNull,
    );
  });

  test('chapter match without text or progression lands on sentence 0', () {
    final pos = resolveBookPosition(spine: spine, locatorHref: 'book-10.xhtml');
    expect(pos, (spineIndex: 2, sentenceIndex: 0));
  });

  test('ignores empty hrefHints so blank front-matter never spuriously matches',
      () {
    const spineWithBlank = <SpineChapter>[
      (hrefHint: '', sentences: ['x']),
      (hrefHint: 'book-9.xhtml', sentences: ['Sing in me.']),
    ];
    final pos = resolveBookPosition(
      spine: spineWithBlank,
      locatorHref: 'book-9.xhtml',
    );
    expect(pos, (spineIndex: 1, sentenceIndex: 0));
  });
}
