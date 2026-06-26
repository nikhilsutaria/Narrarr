import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'voice_catalog.dart';

/// Which voice the user has selected as active.
class VoiceSettings {
  VoiceSettings({String? activeVoiceId})
      : activeVoiceId = activeVoiceId ?? VoiceCatalog.amyLow.id;
  String activeVoiceId;

  Map<String, dynamic> toJson() => {'activeVoiceId': activeVoiceId};
  factory VoiceSettings.fromJson(Map<String, dynamic> j) =>
      VoiceSettings(activeVoiceId: j['activeVoiceId'] as String?);
}

/// Persists [VoiceSettings] as a small JSON file in app-support storage.
class VoiceSettingsStore {
  VoiceSettingsStore({File? file}) : _injected = file;
  final File? _injected;

  Future<File> _file() async =>
      _injected ??
      File(p.join((await getApplicationSupportDirectory()).path,
          'voice_settings.json'));

  Future<VoiceSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return VoiceSettings();
      return VoiceSettings.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
    } catch (_) {
      return VoiceSettings();
    }
  }

  Future<void> save(VoiceSettings s) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(s.toJson()));
  }
}
