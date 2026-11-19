import 'package:flutter/material.dart';

import '../narration/voice_manager.dart';
import '../narration/voice_screen.dart';
import '../narration/voice_settings.dart';
import 'listening_settings_screen.dart';
import 'pronunciations_screen.dart';

/// App settings / about. Entry point to voice management and the privacy note.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Voices'),
            subtitle: const Text('Choose the reading voice — your device’s '
                'built-in speech or downloadable neural voices'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VoiceScreen(
                manager: DownloadingVoiceManager(),
                settingsStore: VoiceSettingsStore(),
              ),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.headphones),
            title: const Text('Listening'),
            subtitle: const Text('Skip interval and rewinding after a pause'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ListeningSettingsScreen(store: VoiceSettingsStore()),
            )),
          ),
          ListTile(
            leading: const Icon(Icons.spellcheck),
            title: const Text('Pronunciations'),
            subtitle: const Text('Words you’ve taught the voice to say'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const PronunciationsScreen(),
            )),
          ),
          const ListTile(
            leading: Icon(Icons.accessibility_new),
            title: Text('Accessibility'),
            subtitle: Text(
                'Atkinson Hyperlegible font and adjustable spacing are in the '
                'reader’s text settings. With TalkBack on, the page is not '
                'double-read while Narrarr narrates.'),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Narrarr',
            applicationVersion: '1.1.0',
            aboutBoxChildren: [
              Text(
                  'Immersion reading for your own EPUBs. Fully offline, no '
                  'account, no telemetry. Open source.'),
            ],
          ),
        ],
      ),
    );
  }
}
