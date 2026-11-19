import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/segmenter.dart';

void main() {
  const seg = Segmenter();

  test('reports the first sentence of every paragraph (#45)', () {
    final r = seg.segment('<p>One. Two.</p><p>Three.</p><div>Four. Five.</div>');
    expect(r.sentences, ['One.', 'Two.', 'Three.', 'Four.', 'Five.']);
    expect(r.paragraphStarts, [0, 2, 3]);
  });

  test('verse line breaks are not paragraph boundaries', () {
    final r = seg.segment(
        '<p>Sing in me, Muse,<br/>and through me tell the story</p><p>Next.</p>');
    expect(r.sentences.length, 3);
    expect(r.paragraphStarts, [0, 2]);
  });

  test('empty paragraphs and skipped content do not create starts', () {
    final r = seg.segment(
        '<p>A.</p><p>   </p><aside epub:type="footnote"><p>Note.</p></aside><p>B.</p>');
    expect(r.sentences, ['A.', 'B.']);
    expect(r.paragraphStarts, [0, 1]);
  });

  test('sentencesFromHtml is unchanged by the paragraph tracking', () {
    const html = '<p>Dr. Who arrived. He left . . . Then.</p><p>X.</p>';
    expect(seg.sentencesFromHtml(html), seg.segment(html).sentences);
  });
}
