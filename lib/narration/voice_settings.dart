import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../build_flavor.dart';
import 'voice_catalog.dart';

/// Which voice the user has selected as active. [kSystemVoiceId] selects the
/// device's built-in TTS; any other id selects that neural voice.
class VoiceSettings {
  VoiceSettings({String? activeVoiceId})
      : activeVoiceId = activeVoiceId ?? defaultVoiceId;
  String activeVoiceId;

  /// Out-of-the-box selection (#15): prod (and unflavored tests) default to the
  /// system voice so a fresh install narrates with no download; the QA flavor
  /// keeps the bundled Amy so device QA of the neural path stays zero-setup.
  static String get defaultVoiceId =>
      BuildFlavor.isQa ? VoiceCatalog.amyLow.id : kSystemVoiceId;

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
