import 'package:flutter/material.dart';

import 'voice_catalog.dart';
import 'voice_manager.dart';
import 'voice_settings.dart';

/// Manage offline voices: download, select active, delete. Bundled amy is
/// always available and cannot be deleted.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.manager,
    required this.settingsStore,
  });

  final DownloadingVoiceManager manager;
  final VoiceSettingsStore settingsStore;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  String _activeId = VoiceCatalog.amyLow.id;
  final _installed = <String, bool>{};
  final _busy = <String, bool>{};
  final _error = <String, String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await widget.settingsStore.load();
    for (final v in VoiceCatalog.all) {
      _installed[v.id] = await widget.manager.isInstalled(v);
    }
    if (mounted) setState(() => _activeId = s.activeVoiceId);
  }

  Future<void> _download(VoiceConfig v) async {
    setState(() {
      _busy[v.id] = true;
      _error.remove(v.id);
    });
    try {
      await widget.manager.ensureAvailable(v);
      _installed[v.id] = true;
    } catch (_) {
      _error[v.id] = 'Download failed. Tap to retry.';
    } finally {
      if (mounted) setState(() => _busy[v.id] = false);
    }
  }

  Future<void> _select(String voiceId) async {
    await widget.settingsStore.save(VoiceSettings(activeVoiceId: voiceId));
    if (mounted) setState(() => _activeId = voiceId);
  }

  Future<void> _delete(VoiceConfig v) async {
    await widget.manager.delete(v);
    _installed[v.id] = false;
    // Deleting the active voice falls back to the flavor default (system TTS
    // in prod) — never to a voice that would need a download to work.
    if (_activeId == v.id) await _select(VoiceSettings.defaultVoiceId);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voices')),
      body: ListView(
        children: [
          _systemTile(),
          for (final v in VoiceCatalog.all) _tile(v),
        ],
      ),
    );
  }

  /// The device's built-in TTS (#15): always available, nothing to download or
  /// delete. Pinned above the neural voices.
  Widget _systemTile() {
    final active = _activeId == kSystemVoiceId;
    return ListTile(
      title: const Text('System voice'),
      subtitle: const Text("Your device's built-in speech • no download"),
      trailing: active
          ? const Text('Active')
          : TextButton(
              onPressed: () => _select(kSystemVoiceId),
              child: const Text('Use'),
            ),
    );
  }

  Widget _tile(VoiceConfig v) {
    // A bundled voice ships inside the APK: it is always available even before
    // its first-use extraction to disk, so never offer it as a "Download".
    final installed = (_installed[v.id] ?? false) || v.isBundled;
    final active = _activeId == v.id;
    final busy = _busy[v.id] ?? false;
    final err = _error[v.id];

    Widget trailing;
    if (busy) {
      trailing = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (!installed) {
      // Even the active voice offers Download when its files aren't on disk
      // yet — in the prod flavor the default voice starts uninstalled.
      trailing = TextButton(
        onPressed: () => _download(v),
        child: Text(err != null ? 'Retry' : 'Download'),
      );
    } else if (active) {
      trailing = const Text('Active');
    } else {
      trailing =
          TextButton(onPressed: () => _select(v.id), child: const Text('Use'));
    }

    return ListTile(
      title: Text(v.displayName),
      subtitle: Text(err ??
          (v.isBundled
              ? 'Bundled • offline'
              : '${(v.sizeBytes / 1024 / 1024).round()} MB download')),
      trailing: trailing,
      onLongPress: (installed && !v.isBundled) ? () => _delete(v) : null,
    );
  }
}
