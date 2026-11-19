import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/book_text.dart';
import 'package:narrarr/reader/page_anchor.dart';
import 'package:narrarr/sync/book_position.dart';

// Shaped like the bundled Odyssey: verse lines are <span>s separated by <br/>,
// so Readium's "first visible element" is often a line or a <br>.
const _html = '''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Book IX</title><link href="../css/core.css" rel="stylesheet" type="text/css"/></head>
<body>
  <section>
    <header><h2>Book IX</h2></header>
    <p>
      <span>No eye discerned the isle, nor the long waves</span>
      <br/>
      <span>That rolled against the shore, till our good ships</span>
      <br/>
      <span>Touched land.</span>
    </p>
    <p><span epub:type="pagebreak" id="p5" title="5"/>It was night.   The sea
      was calm.</p>
  </section>
</body>
</html>''';

void main() {
  test('follows a Readium :root > :nth-child path to the element (#63)', () {
    final a = pageAnchorAt(_html,
        ':root > :nth-child(2) > :nth-child(1) > :nth-child(2) > :nth-child(3)');
    expect(a, isNotNull);
    expect(a!.highlight, 'That rolled against the shore, till our good ships');
    expect(a.matchText,
        startsWith('That rolled against the shore, till our good ships Touched land.'));
    expect(a.cssSelector,
        ':root > :nth-child(2) > :nth-child(1) > :nth-child(2) > :nth-child(3)');
  });

  test('an empty element (a <br>) anchors on the text that follows it', () {
    final a = pageAnchorAt(_html,
        ':root > :nth-child(2) > :nth-child(1) > :nth-child(2) > :nth-child(2)');
    expect(a!.highlight, 'That rolled against the shore, till our good ships');
    // The selector handed back to Readium names the element holding the text.
    expect(a.cssSelector,
        ':root > :nth-child(2) > :nth-child(1) > :nth-child(2) > :nth-child(3)');
  });

  test('self-closing XHTML elements count as empty, as in the WebView', () {
    // The pagebreak <span/> is empty in XHTML; an HTML parser would otherwise
    // open it and swallow the paragraph text, shifting every nth-child count.
    final a = pageAnchorAt(
        _html, ':root > :nth-child(2) > :nth-child(1) > :nth-child(3) > :nth-child(1)');
    // highlight is the raw DOM text (Readium searches the live DOM for it);
    // matchText is whitespace-collapsed for comparing with sentences.
    expect(a!.highlight, 'It was night.   The sea\n      was calm.');
    expect(a.matchText, 'It was night. The sea was calm.');
    expect(a.cssSelector, ':root > :nth-child(2) > :nth-child(1) > :nth-child(3)');
  });

  test('text narration skips (the chapter header) is skipped here too', () {
    // html-rooted, pointing at the <header>: "Book IX" is never narrated, so
    // the anchor is the first line that is.
    final a = pageAnchorAt(
        _html, 'html > :nth-child(2) > :nth-child(1) > :nth-child(1) > :nth-child(1)');
    expect(a!.highlight, 'No eye discerned the isle, nor the long waves');
    expect(a.cssSelector,
        ':root > :nth-child(2) > :nth-child(1) > :nth-child(2) > :nth-child(1)');
  });

  test('a selector that does not resolve gives null', () {
    expect(pageAnchorAt(_html, ':root > :nth-child(2) > :nth-child(9)'), isNull);
    expect(pageAnchorAt(_html, ''), isNull);
    expect(pageAnchorAt('', ':root > :nth-child(2)'), isNull);
  });

  test('matchText is capped', () {
    final long = '<html><head></head><body><p>${'word ' * 200}</p></body></html>';
    final a = pageAnchorAt(long, ':root > :nth-child(2) > :nth-child(1)');
    expect(a!.matchText.length, lessThanOrEqualTo(PageAnchor.maxMatchChars));
    expect(a.highlight.length, lessThanOrEqualTo(PageAnchor.maxHighlightChars));
  });

  group('bundled Odyssey, page locators saved on the P30 (#63)', () {
    late List<ResolvedChapter> spine;
    setUpAll(() async {
      spine = await resolveSpine(
          File('assets/the-odyssey-homer.epub').readAsBytesSync());
    });

    String narratedFrom(String selector, double progression) {
      final pos = resolveBookPosition(
        spine: [
          for (final c in spine) (hrefHint: c.hrefHint, sentences: c.sentences)
        ],
        locatorHref: 'epub/text/book-9.xhtml',
        progression: progression,
        anchorTextAt: (i) => pageAnchorAt(spine[i].html, selector)?.matchText,
      )!;
      return spine[pos.spineIndex].sentences[pos.sentenceIndex];
    }

    test('starts on the first visible line, not 30% of the sentences', () {
      // Reopened at progression 0.3 this used to start at "A high enclosure
      // of hewn stone", pages past the line the locator pointed at.
      expect(
          narratedFrom(
              ':root > :nth-child(2) > :nth-child(1) > :nth-child(9) > :nth-child(11)',
              0.3),
          'That so our crews might make their morning meal.');
      expect(
          narratedFrom(
              ':root > :nth-child(2) > :nth-child(1) > :nth-child(11) > :nth-child(13)',
              0.35),
          'Gave me, when, moved with reverence, we saved');
    });
  });
}
