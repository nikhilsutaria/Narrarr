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
    // _refresh() does real file IO (settings load + isInstalled checks) whose
    // await-chain can't progress inside testWidgets' fake-async zone — build
    // the screen and let that chain finish on the real event loop.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: VoiceScreen(
          manager: DownloadingVoiceManager(baseDir: tmp),
          settingsStore:
              VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json'))),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
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
    // No neural voice is installed on a fresh prod install: every one offers
    // Download; the system voice is the out-of-the-box active engine (#15).
    expect(find.text('Download'), findsNWidgets(3));
    expect(find.text('Active'), findsOneWidget);
  });

  testWidgets('system voice is pinned, needs no download, active on prod',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await pumpScreen(tester, tmp);
    expect(find.text('System voice'), findsOneWidget);
    // The one Active tile on a fresh prod install is the system voice —
    // narration works with no download (#15).
    final tile = tester.widget<ListTile>(find.ancestor(
      of: find.text('System voice'),
      matching: find.byType(ListTile),
    ));
    expect((tile.trailing as Text?)?.data, 'Active');
  });

  testWidgets('qa: selecting the system voice persists it', (tester) async {
    BuildFlavor.debugOverride = 'qa';
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await pumpScreen(tester, tmp);

    // Amy is active by default in qa; the system tile offers Use. The tap's
    // save() and our read-back are real file IO — real event loop again.
    final saved = await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(TextButton, 'Use').first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json'))).load();
    });
    await tester.pumpAndSettle();
    expect(saved!.activeVoiceId, 'system');
  });
}
