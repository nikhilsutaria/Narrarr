import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/book_text.dart';

void main() {
  test('drops header, verse lines read line-by-line, splits on sentence ends',
      () {
    const html = '<header><h2>Book IX</h2><p>summary</p></header>'
        // A verse line break ends the utterance (#37): each line narrates
        // with its own natural pause instead of gluing into a run-on.
        '<p>Sing, O Muse,<br/>of the man.</p>'
        '<p>He sailed far. And wide!</p>';
    final out = sentencesFromHtml(html);
    expect(out, [
      'Sing, O Muse,',
      'of the man.',
      'He sailed far.',
      'And wide!',
    ]);
  });

  test('empty html yields no sentences', () {
    expect(sentencesFromHtml(''), isEmpty);
  });
}
