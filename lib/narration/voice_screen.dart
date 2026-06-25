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

  Future<void> _select(VoiceConfig v) async {
    await widget.settingsStore.save(VoiceSettings(activeVoiceId: v.id));
    if (mounted) setState(() => _activeId = v.id);
  }

  Future<void> _delete(VoiceConfig v) async {
    await widget.manager.delete(v);
    _installed[v.id] = false;
    if (_activeId == v.id) await _select(VoiceCatalog.amyLow);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voices')),
      body: ListView(
        children: [for (final v in VoiceCatalog.all) _tile(v)],
      ),
    );
  }

  Widget _tile(VoiceConfig v) {
    final installed = _installed[v.id] ?? v.isBundled;
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
    } else if (active) {
      trailing = const Text('Active');
    } else if (installed) {
      trailing = TextButton(onPressed: () => _select(v), child: const Text('Use'));
    } else {
      trailing = TextButton(
        onPressed: () => _download(v),
        child: Text(err != null ? 'Retry' : 'Download'),
      );
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
