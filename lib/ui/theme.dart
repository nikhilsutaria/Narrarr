import 'package:flutter/material.dart';

/// Semantic reading-specific colors exposed as a [ThemeExtension] so widgets
/// never hardcode hex values (ui-ux-pro-max `color-semantic` rule).
@immutable
class ReadingColors extends ThemeExtension<ReadingColors> {
  const ReadingColors({required this.sentenceHighlight});

  /// Background tint drawn behind the sentence currently being read aloud.
  ///
  /// A warm "highlighter" yellow: dark EPUB body text on this pale band keeps
  /// text contrast far above the WCAG 4.5:1 minimum, it's the universally
  /// recognized read-aloud cue, and warm yellow is low-glare on the eyes
  /// (unlike the previous indigo tint).
  ///
  /// Tuned for the reader's default light page. When a dark reading theme
  /// lands (Phase 1 reader controls), add a dark-page variant keyed off the
  /// *reader* theme — not the app brightness, since the reader page is themed
  /// independently of the app chrome.
  final Color sentenceHighlight;

  /// Warm highlighter-yellow tuned for a light reader page (dark text).
  static const _highlightLight = Color(0x8CFFD54F); // amber 300 @ ~0.55

  /// Lower-alpha amber for a dark reader page (light text): keeps the band
  /// dark enough that light text stays readable.
  static const _highlightDark = Color(0x4DFFC107); // amber 500 @ 0.30

  static const light = ReadingColors(sentenceHighlight: _highlightLight);
  static const dark = ReadingColors(sentenceHighlight: _highlightDark);

  /// Pick the highlight that matches the current reader page background.
  static Color forReaderBrightness(Brightness b) =>
      b == Brightness.dark ? _highlightDark : _highlightLight;

  // App-chrome default (light page).
  static const value = light;

  @override
  ReadingColors copyWith({Color? sentenceHighlight}) =>
      ReadingColors(sentenceHighlight: sentenceHighlight ?? this.sentenceHighlight);

  @override
  ReadingColors lerp(ThemeExtension<ReadingColors>? other, double t) {
    if (other is! ReadingColors) return this;
    return ReadingColors(
      sentenceHighlight:
          Color.lerp(sentenceHighlight, other.sentenceHighlight, t)!,
    );
  }
}

/// Warm, calm "book" palette (ui-ux-pro-max recommendation for an
/// accessibility-first reader) — replaces the harsh indigo seed so the app
/// chrome doesn't compete with the page.
const _seed = Color(0xFF8D6E63); // warm brown (Material brown 400)

/// Atkinson Hyperlegible — bundled dyslexia-/low-vision-friendly family, used
/// for all app UI text (the reader page font is chosen separately via
/// EPUBPreferences).
const appFontFamily = 'Atkinson Hyperlegible';

ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
      useMaterial3: true,
      fontFamily: appFontFamily,
      extensions: const [ReadingColors.value],
    );

ThemeData get narrarrLightTheme => _theme(Brightness.light);
ThemeData get narrarrDarkTheme => _theme(Brightness.dark);
