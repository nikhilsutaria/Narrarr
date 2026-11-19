import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/system_narrator.dart';

/// Platform-TTS double: records calls and lets the test fire the completion /
/// cancel callbacks the way the real plugin would.
class FakeSystemTts implements SystemTts {
  final List<String> spoken = [];
  int stopCalls = 0;
  double? volume;
  double? rate;
  void Function()? _complete;
  void Function()? _cancel;

  void fireComplete() => _complete?.call();

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async {
    stopCalls++;
    _cancel?.call(); // the real plugin fires the cancel handler on stop
  }

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> setSpeechRate(double r) async => rate = r;

  @override
  set onComplete(void Function() handler) => _complete = handler;

  @override
  set onCancel(void Function() handler) => _cancel = handler;

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeSystemTts tts;
  late SystemNarrator n;

  setUp(() {
    tts = FakeSystemTts();
    n = SystemNarrator(tts: tts);
  });

  test('speak completes only when the platform reports completion', () async {
    var done = false;
    final f = n.speak('Hello there.').then((_) => done = true);
    await pumpEventQueue();
    expect(tts.spoken, ['Hello there.']);
    expect(done, isFalse, reason: 'the engine contract: speak resolves on '
        'audio end, not on utterance start');

    tts.fireComplete();
    await f;
    expect(done, isTrue);
  });

  test('stop unblocks a pending speak', () async {
    final f = n.speak('Hello there.');
    await pumpEventQueue();
    await n.stop();
    await f; // must not hang
  });

  test('pause parks the utterance; resume re-speaks the same sentence',
      () async {
    var done = false;
    final f = n.speak('Hello there.').then((_) => done = true);
    await pumpEventQueue();

    await n.pause(); // stops the platform utterance, fires its cancel handler
    await pumpEventQueue();
    expect(done, isFalse,
        reason: 'the parked future must not complete — that would advance '
            'the highlight while silent');

    await n.resume();
    expect(tts.spoken, ['Hello there.', 'Hello there.'],
        reason: 'no native pause on Android: resume re-speaks the sentence');

    tts.fireComplete();
    await f;
    expect(done, isTrue);
  });

  test('stop while paused still unblocks', () async {
    final f = n.speak('Hello there.');
    await pumpEventQueue();
    await n.pause();
    await n.stop();
    await f; // must not hang
  });

  test('empty text returns immediately', () async {
    await n.speak('   ');
    expect(tts.spoken, isEmpty);
  });

  test('volume is clamped to [0, 1]', () async {
    await n.setVolume(2.0);
    expect(tts.volume, 1.0);
    await n.setVolume(-1.0);
    expect(tts.volume, 0.0);
  });

  test('speed maps to the platform rate scale (0.5 = normal) (#34)', () async {
    await n.setSpeed(1.0);
    expect(tts.rate, 0.5);
    await n.setSpeed(1.5);
    expect(tts.rate, 0.75);
    // The platform scale tops out at 1.0 (~2×): 3× clamps rather than breaks.
    await n.setSpeed(3.0);
    expect(tts.rate, 1.0);
    await n.setSpeed(0.1); // below the supported floor clamps to 0.5×
    expect(tts.rate, 0.25);
  });
}
