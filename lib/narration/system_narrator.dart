import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import 'tts_engine.dart';

/// The minimal platform-TTS surface [SystemNarrator] needs. Injectable so the
/// narrator's contract logic is unit-tested without platform channels (the
/// repo-wide "tests avoid native code" rule); production uses
/// [FlutterTtsAdapter].
abstract class SystemTts {
  /// Begin speaking [text]. Returns once the utterance is queued/started —
  /// completion is reported via [onComplete].
  Future<void> speak(String text);

  /// Stop the current utterance (fires [onCancel], not [onComplete]).
  Future<void> stop();

  Future<void> setVolume(double volume);

  /// Set the platform speech rate (0.0–1.0; 0.5 is normal speed on both
  /// Android and iOS in flutter_tts).
  Future<void> setSpeechRate(double rate);

  /// Fired when the current utterance finishes playing naturally.
  set onComplete(void Function() handler);

  /// Fired when the current utterance is interrupted by [stop].
  set onCancel(void Function() handler);

  Future<void> dispose();
}

/// Production [SystemTts] backed by the `flutter_tts` plugin.
class FlutterTtsAdapter implements SystemTts {
  FlutterTtsAdapter({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> setVolume(double volume) => _tts.setVolume(volume);

  @override
  Future<void> setSpeechRate(double rate) => _tts.setSpeechRate(rate);

  @override
  set onComplete(void Function() handler) => _tts.setCompletionHandler(handler);

  @override
  set onCancel(void Function() handler) => _tts.setCancelHandler(handler);

  @override
  Future<void> dispose() => _tts.stop();
}

/// [TtsEngine] backed by the device's built-in TTS — the out-of-the-box
/// narrator on a fresh install (#15): no model download, works offline on
/// virtually every device.
///
/// Honours the engine contract that makes sentence-synced highlighting work:
/// **[speak] completes only when the utterance has finished playing** (wired to
/// the platform's completion callback) or when [stop] interrupts it.
///
/// Pause: Android's `TextToSpeech` has no native pause, so [pause] stops the
/// current utterance while keeping the [speak] future pending, and [resume]
/// re-speaks the same sentence from its start. Sentence-level granularity
/// matches the app's sync model, and the platform cancel callback is gated so
/// the parked future doesn't complete (which would advance the highlight).
class SystemNarrator implements TtsEngine {
  SystemNarrator({SystemTts? tts}) : _tts = tts ?? FlutterTtsAdapter();

  final SystemTts _tts;

  bool _inited = false;
  bool _paused = false;
  bool _stopRequested = false;
  String _currentText = '';
  Completer<void>? _utterance;
  // Wall-clock per utterance — approximate, but keys the timing table the same
  // way the neural engine's measured clip durations do.
  final Stopwatch _clock = Stopwatch();
  int _lastUtteranceMs = 0;

  @override
  String get name => 'System';

  @override
  int get lastUtteranceMs => _lastUtteranceMs;

  /// The system engine streams with no synth latency; never raised.
  @override
  void Function(bool isBuffering)? onBuffering;

  @override
  Future<void> init() async {
    if (_inited) return;
    _tts.onComplete = _onComplete;
    _tts.onCancel = _onCancel;
    _inited = true;
  }

  void _onComplete() {
    _lastUtteranceMs = _clock.elapsedMilliseconds;
    final c = _utterance;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _onCancel() {
    // A cancel fires both for a real stop() and for the stop that parks a
    // pause(); only the former may unblock speak() — completing the parked
    // future on pause would advance the highlight while silent.
    if (_paused && !_stopRequested) return;
    final c = _utterance;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> speak(String text) async {
    if (!_inited) await init();
    _stopRequested = false;
    final s = text.trim();
    if (s.isEmpty) return;

    _currentText = s;
    final c = _utterance = Completer<void>();
    _clock
      ..reset()
      ..start();
    await _tts.speak(s);
    // Re-assert a pause that raced the speak start (same pattern as the
    // neural engine's #11 fix): the future stays parked until resume().
    if (_paused && !_stopRequested) await _tts.stop();
    await c.future;
    _clock.stop();
    _utterance = null;
    _currentText = '';
  }

  /// Streaming engine: nothing to pre-synthesize or pre-arm.
  @override
  void precache(String text) {}

  @override
  void preloadNext(String text) {}

  /// The system engine speaks with the OS-selected voice; per-app voice
  /// pickers are a #15 open question, so this is a no-op.
  @override
  Future<void> setVoiceIfNeeded(Object voice) async {}

  @override
  Future<void> setVolume(double volume) =>
      _tts.setVolume(volume.clamp(0.0, 1.0));

  /// Narration speed (#34): the platform rate scale puts normal at 0.5, so a
  /// 1.0× UI speed maps to 0.5 and the ceiling (1.0) is ~2× — the system
  /// engine tops out earlier than the neural one. Takes effect from the next
  /// utterance (an in-flight one keeps its rate).
  @override
  Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.5, 3.0);
    await _tts.setSpeechRate((0.5 * v).clamp(0.0, 1.0));
  }

  @override
  Future<void> pause() async {
    if (_utterance == null || _paused) return;
    _paused = true;
    _clock.stop();
    await _tts.stop(); // parks: _onCancel is gated by _paused
  }

  @override
  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    _clock.start();
    final c = _utterance;
    if (c != null && !c.isCompleted && _currentText.isNotEmpty) {
      await _tts.speak(_currentText); // re-speak the parked sentence
    }
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    _paused = false;
    await _tts.stop();
    // Belt and braces: unblock even if the platform emits no cancel callback
    // (e.g. stop() while idle between utterances).
    final c = _utterance;
    if (c != null && !c.isCompleted) c.complete();
  }

  @override
  Future<void> dispose() => _tts.dispose();
}
