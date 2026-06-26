import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_readium/flutter_readium.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Reader font choice. `publisher` keeps the book's own styling.
enum ReaderFont { publisher, atkinson, serif, sans }

extension ReaderFontX on ReaderFont {
  String get label => switch (this) {
        ReaderFont.publisher => 'Publisher',
        ReaderFont.atkinson => 'Atkinson Hyperlegible',
        ReaderFont.serif => 'Serif',
        ReaderFont.sans => 'Sans-serif',
      };

  /// CSS font-family for the Readium webview (null = keep publisher font).
  String? get cssFamily => switch (this) {
        ReaderFont.publisher => null,
        ReaderFont.atkinson => 'Atkinson Hyperlegible',
        ReaderFont.serif => 'Georgia, serif',
        ReaderFont.sans => 'system-ui, sans-serif',
      };
}

/// Reading page theme (page background + text color).
enum ReaderTheme { light, sepia, dark }

extension ReaderThemeX on ReaderTheme {
  String get label => switch (this) {
        ReaderTheme.light => 'Light',
        ReaderTheme.sepia => 'Sepia',
        ReaderTheme.dark => 'Dark',
      };

  Color get background => switch (this) {
        ReaderTheme.light => const Color(0xFFFFFBEB), // warm cream page
        ReaderTheme.sepia => const Color(0xFFF4ECD8),
        ReaderTheme.dark => const Color(0xFF121212),
      };

  Color get text => switch (this) {
        ReaderTheme.light => const Color(0xFF1A1A1A),
        ReaderTheme.sepia => const Color(0xFF5B4636),
        ReaderTheme.dark => const Color(0xFFE0E0E0),
      };

  Brightness get brightness =>
      this == ReaderTheme.dark ? Brightness.dark : Brightness.light;
}

/// User reading preferences, persisted app-wide as a small JSON file.
class ReaderSettings {
  ReaderSettings({
    this.font = ReaderFont.atkinson, // accessibility-first default
    this.fontSizePercent = 110,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
    this.letterSpacing = 0.0,
    this.wordSpacing = 0.0,
    this.paragraphSpacing = 0.0,
  });

  ReaderFont font;
  int fontSizePercent; // 80–250
  double lineHeight; // 1.0–2.2
  ReaderTheme theme;
  // Dyslexia-friendly spacing (0 = publisher default). em units.
  double letterSpacing; // 0.0–0.25
  double wordSpacing; // 0.0–0.5
  double paragraphSpacing; // 0.0–2.0

  /// Translate to flutter_readium preferences. Any non-publisher override
  /// requires `publisherStyles: false`, otherwise the book's CSS wins.
  EPUBPreferences toEpubPreferences() {
    final overriding = font != ReaderFont.publisher ||
        letterSpacing != 0 ||
        wordSpacing != 0 ||
        paragraphSpacing != 0;
    return EPUBPreferences(
      publisherStyles: overriding ? false : null,
      fontFamily: font.cssFamily,
      fontSize: fontSizePercent,
      lineHeight: lineHeight,
      backgroundColor: theme.background,
      textColor: theme.text,
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
      wordSpacing: wordSpacing == 0 ? null : wordSpacing,
      paragraphSpacing: paragraphSpacing == 0 ? null : paragraphSpacing,
      scroll: false,
    );
  }

  Map<String, dynamic> toJson() => {
        'font': font.name,
        'fontSizePercent': fontSizePercent,
        'lineHeight': lineHeight,
        'theme': theme.name,
        'letterSpacing': letterSpacing,
        'wordSpacing': wordSpacing,
        'paragraphSpacing': paragraphSpacing,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
        font: ReaderFont.values.firstWhere(
          (f) => f.name == j['font'],
          orElse: () => ReaderFont.atkinson,
        ),
        fontSizePercent: (j['fontSizePercent'] as num?)?.toInt() ?? 110,
        lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.6,
        theme: ReaderTheme.values.firstWhere(
          (t) => t.name == j['theme'],
          orElse: () => ReaderTheme.light,
        ),
        letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0.0,
        wordSpacing: (j['wordSpacing'] as num?)?.toDouble() ?? 0.0,
        paragraphSpacing: (j['paragraphSpacing'] as num?)?.toDouble() ?? 0.0,
      );

  ReaderSettings copyWith({
    ReaderFont? font,
    int? fontSizePercent,
    double? lineHeight,
    ReaderTheme? theme,
    double? letterSpacing,
    double? wordSpacing,
    double? paragraphSpacing,
  }) =>
      ReaderSettings(
        font: font ?? this.font,
        fontSizePercent: fontSizePercent ?? this.fontSizePercent,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        wordSpacing: wordSpacing ?? this.wordSpacing,
        paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      );
}

/// Loads/saves [ReaderSettings] to a JSON file in app-support storage.
class ReaderSettingsStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'reader_settings.json'));
  }

  Future<ReaderSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return ReaderSettings();
      return ReaderSettings.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
    } catch (_) {
      return ReaderSettings();
    }
  }

  Future<void> save(ReaderSettings s) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(s.toJson()));
  }
}
