import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/reader_settings.dart';

void main() {
  test('spacing fields round-trip through json', () {
    final s = ReaderSettings(
        letterSpacing: 0.06, wordSpacing: 0.16, paragraphSpacing: 1.4);
    final back = ReaderSettings.fromJson(s.toJson());
    expect(back.letterSpacing, 0.06);
    expect(back.wordSpacing, 0.16);
    expect(back.paragraphSpacing, 1.4);
  });

  test('spacing maps into EPUBPreferences', () {
    final prefs = ReaderSettings(letterSpacing: 0.06).toEpubPreferences();
    expect(prefs.letterSpacing, 0.06);
  });

  test('zero spacing maps to null (publisher default)', () {
    final prefs = ReaderSettings().toEpubPreferences();
    expect(prefs.letterSpacing, isNull);
    expect(prefs.wordSpacing, isNull);
    expect(prefs.paragraphSpacing, isNull);
  });
}
