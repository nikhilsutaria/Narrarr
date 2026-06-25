import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:narrarr/narration/voice_screen.dart';
import 'package:narrarr/narration/voice_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('lists catalog voices with amy marked active', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
      home: VoiceScreen(
        manager: DownloadingVoiceManager(baseDir: tmp),
        settingsStore:
            VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json'))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Amy (low) — bundled'), findsOneWidget);
    expect(find.text('Ryan (medium)'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // amy active by default
    expect(find.text('Download'), findsWidgets); // downloadable voices
  });
}
