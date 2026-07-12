import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/neural_narrator.dart';
import 'package:narrarr/narration/pcm_playback.dart';
import 'package:narrarr/narration/tts_synth_isolate.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_manager.dart';

/// In-memory synth double: no isolate, no FFI, controllable failures.
class FakeSynth extends TtsSynthIsolate {
  FakeSynth({this.failStart = false});
  bool failStart;
  bool failSynth = false;
  bool started = false;
  bool disposed = false;
  int synthCalls = 0;
  double? noiseScaleSeen;

  @override
  Future<void> start({
    required String model,
    required String tokens,
    required String dataDir,
    int numThreads = 2,
    double noiseScale = 0.667,
    double lengthScale = 1.0,
    double noiseW = 0.8,
  }) async {
    if (failStart) throw StateError('model failed to load');
    noiseScaleSeen = noiseScale;
    started = true;
  }

  @override
  Future<(Float32List, int)> synth(
    String text, {
    int sid = 0,
    double speed = 1.0,
  }) async {
    synthCalls++;
    if (failSynth) throw StateError('synth died');
    return (Float32List.fromList(List.filled(2205, 0.5)), 22050);
  }

  @override
  void dispose() {
    disposed = true;
  }
}

/// Playback double: records pushed PCM; an utterance finishes as soon as its
/// data is complete, so success-path speak() resolves in tests.
class FakePcmPlayback implements PcmPlayback {
  bool inited = false;

  /// When false, an utterance stays "playing" after [PcmUtterance.end] until
  /// stopped — mimics real audio that outlives its data feed.
  bool finishOnEnd = true;
  final List<FakePcmUtterance> utterances = [];

  @override
  Future<void> init() async => inited = true;

  @override
  Future<PcmUtterance> start(
      {required int sampleRate, double volume = 1.0}) async {
    final u = FakePcmUtterance(sampleRate, finishOnEnd: finishOnEnd);
    utterances.add(u);
    return u;
  }

  @override
  Future<void> dispose() async {}
}

class FakePcmUtterance implements PcmUtterance {
  FakePcmUtterance(this.sampleRate, {this.finishOnEnd = true});
  final int sampleRate;
  final bool finishOnEnd;
  final List<Float32List> chunks = [];
  bool ended = false;
  bool paused = false;
  bool stopped = false;
  final Completer<void> _done = Completer<void>();

  @override
  Future<void> add(Float32List samples) async => chunks.add(samples);

  @override
  void end() {
    ended = true;
    if (finishOnEnd && !_done.isCompleted) _done.complete();
  }

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> setVolume(double volume) async {}
}

/// Voice manager double: controllable failure and a gate to hold concurrent
/// callers in flight.
class FakeVoiceManager implements VoiceManager {
  FakeVoiceManager(this.dir);
  final String dir;
  bool fail = false;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<String> ensureAvailable(VoiceConfig voice) async {
    calls++;
    if (gate != null) await gate!.future;
    if (fail) throw Exception('offline: download failed');
    return dir;
  }
}

void main() {
  late Directory tmp;
  late FakeVoiceManager manager;
  late FakePcmPlayback playback;
  late List<FakeSynth> synths;

  NeuralNarrator narrator({bool firstSynthFailsStart = false}) {
    synths = [];
    var first = true;
    playback = FakePcmPlayback();
    return NeuralNarrator(
      voice: VoiceCatalog.ryanMedium,
      voiceManager: manager,
      playback: playback,
      synthFactory: () {
        final s = FakeSynth(failStart: firstSynthFailsStart && first);
        first = false;
        synths.add(s);
        return s;
      },
    );
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nn');
    manager = FakeVoiceManager(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a failed download leaves init retryable — no restart needed (#30)',
      () async {
    final n = narrator();
    manager.fail = true;
    await expectLater(n.init(), throwsA(isA<Exception>()));
    // The user "downloads the voice in Settings" — the very next init works.
    manager.fail = false;
    await n.init();
    expect(synths.last.started, isTrue);
    expect(synths.first.disposed, isTrue,
        reason: 'the failed attempt must clean up its isolate');
  });

  test('a failed model load throws from init and retries on a fresh isolate',
      () async {
    final n = narrator(firstSynthFailsStart: true);
    await expectLater(n.init(), throwsStateError);
    expect(synths, hasLength(1));
    expect(synths.first.disposed, isTrue);

    await n.init(); // second attempt gets a fresh isolate from the factory
    expect(synths, hasLength(2));
    expect(synths.last.started, isTrue);
  });

  test('concurrent init calls share one attempt (#30 double-tap race)',
      () async {
    final n = narrator();
    manager.gate = Completer<void>();
    final first = n.init();
    final second = n.init();
    manager.gate!.complete();
    await Future.wait([first, second]);
    expect(manager.calls, 1, reason: 'one shared download, not two');
    expect(synths, hasLength(1), reason: 'one shared isolate spawn, not two');
  });

  test('init after success is a no-op', () async {
    final n = narrator();
    await n.init();
    await n.init();
    expect(manager.calls, 1);
    expect(synths, hasLength(1));
  });

  test('speak before init throws instead of failing silently in release',
      () async {
    final n = narrator();
    await expectLater(n.speak('Hello there.'), throwsStateError);
  });

  test('a dead synth surfaces from speak — not an empty clip that skips',
      () async {
    final n = narrator();
    await n.init();
    synths.single.failSynth = true;
    await expectLater(n.speak('Hello there.'), throwsStateError);
  });

  test('a failed precache surfaces from the speak that consumes it', () async {
    final n = narrator();
    await n.init();
    synths.single.failSynth = true;
    n.precache('Hello there.');
    await pumpEventQueue();
    await expectLater(n.speak('Hello there.'), throwsStateError);
  });

  test('setVoice after init re-inits on a fresh isolate (#30 poisoning)',
      () async {
    final n = narrator();
    await n.init();
    final firstSynth = synths.single;

    await n.setVoice(VoiceCatalog.amyMedium);
    expect(firstSynth.disposed, isTrue);
    expect(synths, hasLength(2), reason: 'never reuse a disposed isolate');
    expect(synths.last.started, isTrue);
    expect(n.voice.id, VoiceCatalog.amyMedium.id);

    // And the new synth actually serves speech attempts (throws only once we
    // kill it — proving the engine is live, not wedged).
    synths.last.failSynth = true;
    await expectLater(n.speak('Still alive.'), throwsStateError);
  });

  test('speak streams PCM into playback and completes on audio end (#33)',
      () async {
    final n = narrator();
    await n.init();
    await n.speak('Hello there.');
    expect(playback.inited, isTrue);
    expect(playback.utterances, hasLength(1));
    final u = playback.utterances.single;
    expect(u.chunks, isNotEmpty, reason: 'PCM pushed straight to playback');
    expect(u.ended, isTrue, reason: 'the stream must be closed after the '
        'last chunk or the utterance never finishes');
    expect(n.lastUtteranceMs, greaterThan(0));
  });

  test('a precached sentence plays from RAM (no re-synthesis)', () async {
    final n = narrator();
    await n.init();
    final warmupCalls = synths.single.synthCalls;
    n.precache('Hello there.');
    await pumpEventQueue();
    final afterPrecache = synths.single.synthCalls;
    expect(afterPrecache, greaterThan(warmupCalls));
    await n.speak('Hello there.');
    expect(synths.single.synthCalls, afterPrecache,
        reason: 'speak must consume the cached PCM, not synthesize again');
    expect(playback.utterances.single.ended, isTrue);
  });

  test('stop unblocks an in-flight speak (#33)', () async {
    final n = narrator();
    await n.init();
    // The audio "keeps playing" after its data ends until stopped, so the
    // speak future genuinely parks on the utterance like on a device.
    playback.finishOnEnd = false;
    final speaking = n.speak('Hello there.');
    await pumpEventQueue();
    await n.stop();
    await speaking; // must not hang
    expect(playback.utterances.single.stopped, isTrue);
  });

  test('pause before playback start still sticks (#11)', () async {
    final n = narrator();
    await n.init();
    await n.pause(); // pause lands before any utterance exists
    final speaking = n.speak('Hello there.');
    await pumpEventQueue();
    expect(playback.utterances.single.paused, isTrue,
        reason: 'the utterance start must re-assert a pre-existing pause');
    await n.stop();
    await speaking;
  });

  test('speed change clears the look-ahead cache (#34)', () async {
    final n = narrator();
    await n.init();
    n.precache('Hello there.');
    await pumpEventQueue();
    final calls = synths.single.synthCalls;
    await n.setSpeed(1.5);
    await n.speak('Hello there.');
    expect(synths.single.synthCalls, greaterThan(calls),
        reason: 'cached PCM was synthesized at the old speed — it must be '
            're-synthesized, not replayed');
  });
}
