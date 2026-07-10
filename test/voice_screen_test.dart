import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/build_flavor.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:narrarr/narration/voice_screen.dart';
import 'package:narrarr/narration/voice_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  tearDown(() => BuildFlavor.debugOverride = null);

  Future<void> pumpScreen(WidgetTester tester, Directory tmp) async {
    await tester.pumpWidget(MaterialApp(
      home: VoiceScreen(
        manager: DownloadingVoiceManager(baseDir: tmp),
        settingsStore:
            VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json'))),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('qa: lists catalog voices with bundled amy marked active',
      (tester) async {
    BuildFlavor.debugOverride = 'qa';
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await pumpScreen(tester, tmp);
    expect(find.text('Amy (low) — bundled'), findsOneWidget);
    expect(find.text('Ryan (medium)'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // amy active by default
    expect(find.text('Download'), findsWidgets); // downloadable voices
  });

  testWidgets('prod: default amy is a download, not bundled', (tester) async {
    // No flavor override — unflavored behaves as prod.
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await pumpScreen(tester, tmp);
    expect(find.text('Amy (low)'), findsOneWidget);
    expect(find.text('Amy (low) — bundled'), findsNothing);
    // Nothing is installed on a fresh prod install: every voice (the active
    // default included) offers Download instead of Active/Use.
    expect(find.text('Download'), findsNWidgets(3));
    expect(find.text('Active'), findsNothing);
  });
}
