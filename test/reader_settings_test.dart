import 'package:flutter/material.dart';
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

  test('publisher font with no overrides keeps publisher styles', () {
    final prefs = ReaderSettings(font: ReaderFont.publisher).toEpubPreferences();
    // No override → publisherStyles untouched (null) and no font-family forced.
    expect(prefs.publisherStyles, isNull);
    expect(prefs.fontFamily, isNull);
  });

  test('choosing a non-publisher font disables publisher styles', () {
    final prefs = ReaderSettings(font: ReaderFont.serif).toEpubPreferences();
    expect(prefs.publisherStyles, isFalse);
    expect(prefs.fontFamily, 'Georgia, serif');
  });

  test('a spacing override alone disables publisher styles', () {
    final prefs =
        ReaderSettings(font: ReaderFont.publisher, wordSpacing: 0.2)
            .toEpubPreferences();
    expect(prefs.publisherStyles, isFalse);
    expect(prefs.wordSpacing, 0.2);
  });

  test('each font maps to its expected css family', () {
    expect(ReaderFont.publisher.cssFamily, isNull);
    expect(ReaderFont.atkinson.cssFamily, 'Atkinson Hyperlegible');
    expect(ReaderFont.serif.cssFamily, 'Georgia, serif');
    expect(ReaderFont.sans.cssFamily, 'system-ui, sans-serif');
  });

  test('theme background/text/brightness are consistent', () {
    expect(ReaderTheme.dark.brightness, Brightness.dark);
    expect(ReaderTheme.light.brightness, Brightness.light);
    expect(ReaderTheme.sepia.brightness, Brightness.light);
  });

  test('full settings round-trip through json', () {
    final s = ReaderSettings(
      font: ReaderFont.sans,
      fontSizePercent: 140,
      lineHeight: 1.9,
      theme: ReaderTheme.sepia,
      letterSpacing: 0.05,
      wordSpacing: 0.1,
      paragraphSpacing: 1.2,
    );
    final back = ReaderSettings.fromJson(s.toJson());
    expect(back.font, ReaderFont.sans);
    expect(back.fontSizePercent, 140);
    expect(back.lineHeight, 1.9);
    expect(back.theme, ReaderTheme.sepia);
  });

  test('fromJson falls back to safe defaults on unknown/missing values', () {
    final back = ReaderSettings.fromJson({'font': 'bogus', 'theme': 'bogus'});
    expect(back.font, ReaderFont.atkinson);
    expect(back.theme, ReaderTheme.light);
    expect(back.fontSizePercent, 110);
  });
}
