import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/build_flavor.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vs'));
  tearDown(() {
    tmp.deleteSync(recursive: true);
    BuildFlavor.debugOverride = null;
  });

  test('prod (and unflavored) defaults to the system voice — #15', () async {
    final store = VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json')));
    final s = await store.load();
    expect(s.activeVoiceId, kSystemVoiceId);
  });

  test('qa flavor defaults to the bundled amy voice', () async {
    BuildFlavor.debugOverride = 'qa';
    final store = VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json')));
    final s = await store.load();
    expect(s.activeVoiceId, VoiceCatalog.amyLow.id);
  });

  test('round-trips the active voice id', () async {
    final f = File(p.join(tmp.path, 'v.json'));
    await VoiceSettingsStore(file: f)
        .save(VoiceSettings(activeVoiceId: 'vits-piper-en_US-ryan-medium'));
    final s = await VoiceSettingsStore(file: f).load();
    expect(s.activeVoiceId, 'vits-piper-en_US-ryan-medium');
  });
}
