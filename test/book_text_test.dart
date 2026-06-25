import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/book_text.dart';

void main() {
  test('drops header, joins verse lines with a space, splits on sentence ends',
      () {
    const html = '<header><h2>Book IX</h2><p>summary</p></header>'
        // A verse line break inside a sentence (no terminal punctuation) must
        // become a SPACE, not glue words together.
        '<p>Sing, O Muse,<br/>of the man.</p>'
        '<p>He sailed far. And wide!</p>';
    final out = sentencesFromHtml(html);
    expect(out, [
      'Sing, O Muse, of the man.',
      'He sailed far.',
      'And wide!',
    ]);
  });

  test('empty html yields no sentences', () {
    expect(sentencesFromHtml(''), isEmpty);
  });
}
