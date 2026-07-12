import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/segmenter.dart';

void main() {
  const seg = Segmenter();

  test('does not split on common abbreviations', () {
    expect(
      seg.sentencesFromHtml('<p>Dr. Smith met Mr. Jones. They talked.</p>'),
      ['Dr. Smith met Mr. Jones.', 'They talked.'],
    );
  });

  test('does not split on a single initial', () {
    expect(
      seg.sentencesFromHtml('<p>He met A. B. Carter. Then left.</p>'),
      ['He met A. B. Carter.', 'Then left.'],
    );
  });

  test('skips footnotes, noterefs, and figure captions', () {
    expect(
      seg.sentencesFromHtml(
        '<p>Real text.</p>'
        '<aside epub:type="footnote"><p>A footnote.</p></aside>'
        '<figcaption>A caption.</figcaption>'
        '<p>More text.</p>',
      ),
      ['Real text.', 'More text.'],
    );
  });

  test('skips nav/toc subtrees', () {
    expect(
      seg.sentencesFromHtml(
        '<nav epub:type="toc"><ol><li>Chapter One.</li></ol></nav>'
        '<p>Body sentence.</p>',
      ),
      ['Body sentence.'],
    );
  });

  test('skips pagebreak markers and bare page numbers', () {
    expect(
      seg.sentencesFromHtml(
        '<p>Before the break.</p>'
        '<span epub:type="pagebreak">42</span>'
        '<p>123</p>'
        '<p>After the break.</p>',
      ),
      ['Before the break.', 'After the break.'],
    );
  });

  test('drops the chapter header; verse lines read line-by-line (#37)', () {
    expect(
      seg.sentencesFromHtml(
        '<header><h2>Book IX</h2></header>'
        '<p>Sing, O Muse,<br/>of the man.</p>'
        '<p>He sailed far. And wide!</p>',
      ),
      ['Sing, O Muse,', 'of the man.', 'He sailed far.', 'And wide!'],
    );
  });

  test('skips table content', () {
    expect(
      seg.sentencesFromHtml(
        '<p>Narrate this.</p>'
        '<table><tr><td>Cell one.</td><td>Cell two.</td></tr></table>',
      ),
      ['Narrate this.'],
    );
  });

  test('empty / whitespace html yields no sentences', () {
    expect(seg.sentencesFromHtml(''), isEmpty);
    expect(seg.sentencesFromHtml('   '), isEmpty);
  });
}
