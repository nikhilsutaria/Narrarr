import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/text_normalizer.dart';

void main() {
  const n = TextNormalizer();

  group('punctuation canonicalization', () {
    test('curly quotes and apostrophes straighten', () {
      expect(n.normalize('“It’s here,” she said.'),
          '"It\'s here," she said.');
    });

    test('unicode and spaced ellipses canonicalize', () {
      expect(n.normalize('Well… maybe.'), 'Well... maybe.');
      expect(n.normalize('Well . . . maybe.'), 'Well... maybe.');
    });

    test('em-dash becomes a comma pause', () {
      expect(n.normalize('He left—finally—at dawn.'),
          'He left, finally, at dawn.');
    });

    test('soft hyphen and zero-width characters are stripped', () {
      expect(n.normalize('cal­endar'), 'calendar');
      expect(n.normalize('a​b'), 'ab');
    });
  });

  group('numbers', () {
    test('integers become words', () {
      expect(n.normalize('He owned 3 ships.'), 'He owned three ships.');
      expect(n.normalize('There were 47 men.'), 'There were forty-seven men.');
      expect(
          n.normalize('It cost 1,250 in total.'),
          'It cost one thousand two hundred fifty in total.');
    });

    test('4-digit numbers read as years', () {
      expect(n.normalize('In 1876 he sailed.'),
          'In eighteen seventy-six he sailed.');
      expect(n.normalize('By 1900 it was done.'),
          'By nineteen hundred it was done.');
      expect(n.normalize('In 1905 they met.'), 'In nineteen oh five they met.');
      expect(n.normalize('Since 2020 nothing.'),
          'Since twenty twenty nothing.');
      expect(n.normalize('In 2005 it began.'),
          'In two thousand five it began.');
    });

    test('ordinals', () {
      expect(n.normalize('the 1st of May'), 'the first of May');
      expect(n.normalize('his 3rd attempt'), 'his third attempt');
      expect(n.normalize('the 22nd day'), 'the twenty-second day');
      expect(n.normalize('the 20th century'), 'the twentieth century');
    });

    test('decimals read as point digits', () {
      expect(n.normalize('pi is 3.14 roughly'),
          'pi is three point one four roughly');
    });

    test('currency', () {
      expect(n.normalize(r'It cost $5.'), 'It cost five dollars.');
      expect(n.normalize(r'Only $1 left.'), 'Only one dollar left.');
      expect(n.normalize(r'He paid $5.50 for it.'),
          'He paid five dollars and fifty cents for it.');
      expect(n.normalize('worth £10 then'), 'worth ten pounds then');
    });

    test('percent', () {
      expect(n.normalize('rose 5% overnight'), 'rose five percent overnight');
    });

    test('number ranges read as "to"', () {
      expect(n.normalize('the war of 1914–1918 ended'),
          'the war of nineteen fourteen to nineteen eighteen ended');
    });
  });

  group('abbreviations', () {
    test('titles expand', () {
      expect(n.normalize('Mr. Smith met Dr. Jones.'),
          'Mister Smith met Doctor Jones.');
      expect(n.normalize('Mrs. Hall arrived.'), 'Missus Hall arrived.');
    });

    test('St. before a capitalized word is Saint', () {
      expect(n.normalize('the church of St. Peter'),
          'the church of Saint Peter');
    });

    test('latin abbreviations', () {
      expect(n.normalize('birds, fish, etc. swarmed'),
          'birds, fish, et cetera swarmed');
      expect(n.normalize('some, e.g. gulls, flew'),
          'some, for example gulls, flew');
    });
  });

  group('roman-numeral headings', () {
    test('bare roman heading reads as a number', () {
      expect(n.normalize('XIV.'), 'fourteen.');
      expect(n.normalize('IX'), 'nine');
    });

    test('Book/Chapter + roman reads as a number', () {
      expect(n.normalize('Book IX'), 'Book nine');
      expect(n.normalize('Chapter XLII.'), 'Chapter forty-two.');
    });

    test('roman-looking words inside sentences pass through', () {
      expect(n.normalize('I MIX the batter.'), 'I MIX the batter.');
      expect(n.normalize('I did.'), 'I did.');
    });
  });

  test('ambiguous input passes through unchanged', () {
    const s = 'A perfectly ordinary sentence, nothing to change here.';
    expect(n.normalize(s), s);
  });
}
