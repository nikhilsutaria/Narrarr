import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_settings.dart';

void main() {
  test('speechSpeed defaults to 1.0 and round-trips through the store (#34)',
      () async {
    final dir = Directory.systemTemp.createTempSync('vs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/voice_settings.json');

    final store = VoiceSettingsStore(file: file);
    final fresh = await store.load();
    expect(fresh.speechSpeed, 1.0);

    fresh.speechSpeed = 1.5;
    await store.save(fresh);

    final reloaded = await VoiceSettingsStore(file: file).load();
    expect(reloaded.speechSpeed, 1.5);
    expect(reloaded.activeVoiceId, fresh.activeVoiceId);
  });

  test('a settings file from v1.1 (no speechSpeed key) loads at 1.0', () async {
    final dir = Directory.systemTemp.createTempSync('vs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/voice_settings.json')
      ..writeAsStringSync('{"activeVoiceId": "system"}');
    final s = await VoiceSettingsStore(file: file).load();
    expect(s.activeVoiceId, 'system');
    expect(s.speechSpeed, 1.0);
  });
}
