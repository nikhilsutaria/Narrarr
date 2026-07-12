import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/switchable_tts_engine.dart';
import 'package:narrarr/narration/tts_engine.dart';

import 'support/fake_tts_engine.dart';

/// [FakeTtsEngine] with spies for the calls switching must route correctly.
class SpyEngine extends FakeTtsEngine {
  SpyEngine(this.label);
  final String label;
  int stops = 0;
  int inits = 0;
  Object? voiceApplied;

  @override
  String get name => label;

  @override
  Future<void> init() async => inits++;

  @override
  Future<void> stop() async {
    stops++;
    await super.stop();
  }

  @override
  Future<void> setVoiceIfNeeded(Object voice) async => voiceApplied = voice;
}

void main() {
  late SpyEngine system;
  late SpyEngine neural;
  late SwitchableTtsEngine engine;

  setUp(() {
    system = SpyEngine('system');
    neural = SpyEngine('neural');
    engine = SwitchableTtsEngine(system: system, neural: neural);
  });

  test('starts on the system engine (#15 out-of-the-box default)', () {
    expect(engine.isSystemActive, isTrue);
    expect(engine.name, 'system');
  });

  test('delegates calls to the active engine only', () async {
    await engine.init();
    engine.speak('Hello.');
    expect(system.inits, 1);
    expect(system.spoken, ['Hello.']);
    expect(neural.inits, 0);
    expect(neural.spoken, isEmpty);
    system.finishCurrent();
  });

  test('useNeural applies the voice, stops the outgoing engine, then routes',
      () async {
    await engine.useNeural('voice-config');
    expect(neural.voiceApplied, 'voice-config',
        reason: 'voice applies before the engine goes live');
    expect(system.stops, 1,
        reason: 'the outgoing engine must stop so a pending speak unblocks');
    expect(engine.isSystemActive, isFalse);

    engine.speak('Hello.');
    expect(neural.spoken, ['Hello.']);
    neural.finishCurrent();
  });

  test('useSystem routes back and stops the neural engine', () async {
    await engine.useNeural('voice-config');
    await engine.useSystem();
    expect(neural.stops, 1);
    expect(engine.isSystemActive, isTrue);
  });

  test('switching to the already-active engine is a no-op', () async {
    await engine.useSystem();
    expect(system.stops, 0);
    await engine.useNeural('v');
    await engine.useNeural('v');
    expect(system.stops, 1);
    expect(neural.stops, 0);
  });

  test('is a TtsEngine — usable anywhere the controller expects one', () {
    expect(engine, isA<TtsEngine>());
  });
}
