import 'dart:async';

import 'package:narrarr/narration/tts_engine.dart';

/// A controllable [TtsEngine] test double: [speak] returns a future that stays
/// pending until the test resolves it (via [finishCurrent]) or [stop]/[pause]
/// acts on it — mirroring the real "speak completes on audio-end" contract
/// without any audio or native code.
class FakeTtsEngine implements TtsEngine {
  FakeTtsEngine({this.durationMs = 1000});

  /// Reported [lastUtteranceMs] for each completed utterance. A single value
  /// applies to all; override per call by pushing to [durations].
  int durationMs;
  final List<int> durations = [];

  final List<String> spoken = [];
  Completer<void>? _current;
  int _lastUtteranceMs = 0;
  bool paused = false;
  double volume = 1.0;

  @override
  String get name => 'fake';

  @override
  int get lastUtteranceMs => _lastUtteranceMs;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    final c = _current = Completer<void>();
    return c.future;
  }

  /// Resolve the pending [speak], setting [lastUtteranceMs] to the next queued
  /// duration (or the default).
  void finishCurrent() {
    if (_current != null && !_current!.isCompleted) {
      _lastUtteranceMs =
          durations.isNotEmpty ? durations.removeAt(0) : durationMs;
      _current!.complete();
    }
  }

  @override
  void precache(String text) {}

  @override
  void preloadNext(String text) {}

  @override
  Future<void> setVoiceIfNeeded(Object voice) async {}

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async {
    if (_current != null && !_current!.isCompleted) _current!.complete();
  }

  @override
  Future<void> dispose() async {}
}
