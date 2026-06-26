import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/chapter_titles.dart';

void main() {
  test('humanizes file names when no TOC is available', () {
    expect(
      chapterTitles(hrefHints: ['book-9.xhtml', 'chapter_01.xhtml']),
      ['Book 9', 'Chapter 01'],
    );
  });

  test('prefers a matching table-of-contents title', () {
    final titles = chapterTitles(
      hrefHints: ['OEBPS/book-9.xhtml', 'OEBPS/book-10.xhtml'],
      toc: const [
        (href: 'OEBPS/book-9.xhtml#start', title: 'Book IX: In the One-Eyed Giant\'s Cave'),
        (href: 'OEBPS/book-10.xhtml', title: 'Book X: The Bewitching Queen of Aeaea'),
      ],
    );
    expect(titles, [
      'Book IX: In the One-Eyed Giant\'s Cave',
      'Book X: The Bewitching Queen of Aeaea',
    ]);
  });

  test('matches TOC by file basename even when paths differ', () {
    final titles = chapterTitles(
      hrefHints: ['text/book-9.xhtml'],
      toc: const [(href: '../book-9.xhtml#frag', title: 'The Cyclops')],
    );
    expect(titles, ['The Cyclops']);
  });

  test('ignores blank TOC titles and falls back to the file name', () {
    final titles = chapterTitles(
      hrefHints: ['preface.xhtml'],
      toc: const [(href: 'preface.xhtml', title: '   ')],
    );
    expect(titles, ['Preface']);
  });

  test('falls back to a generic section label when nothing is usable', () {
    expect(chapterTitles(hrefHints: ['']), ['Section 1']);
  });
}
