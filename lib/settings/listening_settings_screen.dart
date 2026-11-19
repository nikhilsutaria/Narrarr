import 'package:flutter/material.dart';

import '../narration/voice_settings.dart';

/// Listening preferences (#45): the skip interval used by the ±skip buttons,
/// lock screen and headset, and whether to rewind after a long pause.
class ListeningSettingsScreen extends StatefulWidget {
  const ListeningSettingsScreen({super.key, required this.store});

  final VoiceSettingsStore store;

  @override
  State<ListeningSettingsScreen> createState() =>
      _ListeningSettingsScreenState();
}

class _ListeningSettingsScreenState extends State<ListeningSettingsScreen> {
  VoiceSettings? _settings;

  @override
  void initState() {
    super.initState();
    widget.store.load().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  Future<void> _update(void Function(VoiceSettings s) change) async {
    final s = _settings;
    if (s == null) return;
    setState(() => change(s));
    await widget.store.save(s);
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Skip back / forward',
                      style: theme.textTheme.titleMedium),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'How far the skip buttons, lock-screen controls and '
                    'headset buttons jump.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sec in VoiceSettings.skipOptions)
                        ChoiceChip(
                          label: Text('$sec seconds'),
                          selected: s.skipSeconds == sec,
                          onSelected: (_) =>
                              _update((v) => v.skipSeconds = sec),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Rewind after a pause'),
                  subtitle: const Text(
                      'After a pause of more than 5 minutes, resume two '
                      'sentences back; after more than an hour, from the '
                      'start of the paragraph.'),
                  value: s.autoRewind,
                  onChanged: (on) => _update((v) => v.autoRewind = on),
                ),
              ],
            ),
    );
  }
}
