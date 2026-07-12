import 'tts_engine.dart';

/// A [TtsEngine] that delegates to one of two engines — the device's system
/// TTS or the neural narrator — and can switch between them at runtime (#15).
///
/// The [NarrationAudioHandler]/controller keep their single `engine`
/// reference; the reader points this wrapper at the persisted voice selection
/// before each play. Switching stops the outgoing engine first, so a pending
/// `speak()` unblocks and the play loop can't advance on the wrong engine.
/// Engines are kept alive across switches (construction is cheap and lazy;
/// the neural model only loads on its own `init`).
class SwitchableTtsEngine implements TtsEngine {
  SwitchableTtsEngine({
    required TtsEngine system,
    required TtsEngine neural,
    bool startWithSystem = true,
  })  : _system = system,
        _neural = neural {
    _active = startWithSystem ? _system : _neural;
  }

  final TtsEngine _system;
  final TtsEngine _neural;
  late TtsEngine _active;

  /// The engine calls are currently routed to.
  TtsEngine get active => _active;
  bool get isSystemActive => identical(_active, _system);

  /// Route narration to the device's system TTS.
  Future<void> useSystem() => _use(_system);

  /// Route narration to the neural engine, speaking with [voice] (a
  /// `VoiceConfig`). Applies the voice first so a required re-init happens
  /// before the engine goes live.
  Future<void> useNeural(Object voice) async {
    await _neural.setVoiceIfNeeded(voice);
    await _use(_neural);
  }

  Future<void> _use(TtsEngine next) async {
    if (identical(next, _active)) return;
    await _active.stop();
    _active = next;
  }

  // ---- TtsEngine delegation ----

  @override
  String get name => _active.name;

  @override
  int get lastUtteranceMs => _active.lastUtteranceMs;

  @override
  Future<void> init() => _active.init();

  @override
  Future<void> speak(String text) => _active.speak(text);

  @override
  void precache(String text) => _active.precache(text);

  @override
  void preloadNext(String text) => _active.preloadNext(text);

  @override
  Future<void> setVolume(double volume) => _active.setVolume(volume);

  @override
  Future<void> pause() => _active.pause();

  @override
  Future<void> resume() => _active.resume();

  @override
  Future<void> stop() => _active.stop();

  @override
  Future<void> setVoiceIfNeeded(Object voice) => _active.setVoiceIfNeeded(voice);

  @override
  Future<void> dispose() async {
    await _system.dispose();
    await _neural.dispose();
  }
}
