import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/neural_narrator.dart';
import 'package:narrarr/narration/voice_catalog.dart';

void main() {
  test('setVoice updates the active voice and engine name when idle', () async {
    final n = NeuralNarrator(voice: VoiceCatalog.amyLow);
    expect(n.voice.id, VoiceCatalog.amyLow.id);
    await n.setVoice(VoiceCatalog.ryanMedium);
    expect(n.voice.id, VoiceCatalog.ryanMedium.id);
    expect(n.name, contains('ryan'));
  });
}
