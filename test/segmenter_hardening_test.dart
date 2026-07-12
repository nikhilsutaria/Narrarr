import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/segmenter.dart';

/// #37 hardening cases: ellipses, dialogue quotes, decimals, new
/// abbreviations, verse line breaks, and run-on capping.
void main() {
  const seg = Segmenter();

  List<String> split(String html) => seg.sentencesFromHtml('<p>$html</p>');

  group('ellipses', () {
    test('spaced ellipsis does not fragment', () {
      expect(split('He waited . . . and waited.'),
          ['He waited... and waited.']);
    });

    test('trailing-off ellipsis before lowercase continues the sentence', () {
      expect(split('Well... maybe it was true. She left.'),
          ['Well... maybe it was true.', 'She left.']);
    });

    test('ellipsis before a capital ends the sentence', () {
      expect(split('He stopped... Then silence fell.'),
          ['He stopped...', 'Then silence fell.']);
    });
  });

  group('dialogue quotes', () {
    test('terminal punctuation inside quotes splits cleanly', () {
      expect(split('She said "leave now." He stayed.'),
          ['She said "leave now."', 'He stayed.']);
    });

    test('curly closing quote after punctuation splits cleanly', () {
      expect(split('She said “leave now.” He stayed.'),
          ['She said “leave now.”', 'He stayed.']);
    });

    test('question mark inside quotes', () {
      expect(split('"Who goes there?" the guard called.'),
          ['"Who goes there?"', 'the guard called.']);
    });
  });

  group('numbers and abbreviations', () {
    test('a decimal split across a space does not break the sentence', () {
      expect(split('The value was 3. 14 more or less.'),
          ['The value was 3. 14 more or less.']);
    });

    test('newer abbreviations do not end a sentence', () {
      expect(split('He worked at Smith Inc. for years. Then he left.'),
          ['He worked at Smith Inc. for years.', 'Then he left.']);
      expect(split('It was 5 a.m. when the ship sailed.'),
          ['It was 5 a.m. when the ship sailed.']);
    });
  });

  group('verse', () {
    test('br ends the utterance so verse reads line-by-line', () {
      final out = seg.sentencesFromHtml(
          '<p>Sing to me of the man, Muse<br/>the man of twists and turns<br/>'
          'driven time and again off course</p>');
      expect(out, [
        'Sing to me of the man, Muse',
        'the man of twists and turns',
        'driven time and again off course',
      ]);
    });
  });

  group('run-on capping', () {
    test('an unpunctuated run-on is re-split at clause punctuation', () {
      final clause = 'and the long grey shadow fell over the silent water';
      final runOn = List.filled(9, clause).join(', ');
      expect(runOn.length, greaterThan(400));
      final out = split(runOn);
      expect(out.length, greaterThan(1), reason: 'must not stay one giant '
          'utterance — downstream chunking would operate blind');
      expect(out.join(' ').replaceAll('  ', ' '), runOn,
          reason: 'no words lost');
      for (final s in out) {
        expect(s.length, lessThanOrEqualTo(250));
      }
    });

    test('normal punctuated prose is untouched by the cap', () {
      final s = 'A modest sentence. ${'word ' * 60}end.';
      final out = split(s);
      expect(out.first, 'A modest sentence.');
    });
  });
}
