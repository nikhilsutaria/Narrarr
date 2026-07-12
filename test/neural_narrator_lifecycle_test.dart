import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/neural_narrator.dart';
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

  @override
  Future<void> start({
    required String model,
    required String tokens,
    required String dataDir,
    int numThreads = 2,
  }) async {
    if (failStart) throw StateError('model failed to load');
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
  late List<FakeSynth> synths;

  NeuralNarrator narrator({bool firstSynthFailsStart = false}) {
    synths = [];
    var first = true;
    return NeuralNarrator(
      voice: VoiceCatalog.ryanMedium,
      voiceManager: manager,
      tempDir: tmp,
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
}
