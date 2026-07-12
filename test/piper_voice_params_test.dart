import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/piper_voice_params.dart';

void main() {
  test('reads the inference block of a Piper voice config (#38)', () {
    const json = '''
    {"audio": {"sample_rate": 16000},
     "inference": {"noise_scale": 0.667, "length_scale": 1.2, "noise_w": 0.6}}
    ''';
    final p = PiperVoiceParams.fromJsonString(json);
    expect(p.noiseScale, 0.667);
    expect(p.lengthScale, 1.2);
    expect(p.noiseW, 0.6);
  });

  test('missing fields keep defaults', () {
    final p =
        PiperVoiceParams.fromJsonString('{"inference": {"length_scale": 1.1}}');
    expect(p.lengthScale, 1.1);
    expect(p.noiseScale, 0.667);
    expect(p.noiseW, 0.8);
  });

  test('missing inference block / malformed json fall back to defaults', () {
    for (final bad in ['{}', 'not json at all', '[1,2]', '{"inference": 3}']) {
      final p = PiperVoiceParams.fromJsonString(bad);
      expect(p.noiseScale, 0.667);
      expect(p.lengthScale, 1.0);
      expect(p.noiseW, 0.8);
    }
  });
}
