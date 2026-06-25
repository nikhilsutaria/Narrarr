/// A speech engine that narrates text one sentence at a time.
///
/// The contract that makes sentence-synced highlighting work for *any* engine:
/// [speak] must complete **only when the utterance has finished playing** (or
/// when [stop] interrupts it). The UI advances the highlight after each
/// [speak] returns, so the highlight stays locked to the audio regardless of
/// whether the underlying engine is the OS voice or a neural model.
abstract class TtsEngine {
  /// Human-readable name (for logs / UI).
  String get name;

  /// Prepare the engine (load voices / models). Safe to await once.
  Future<void> init();

  /// Speak [text]; the returned future completes when playback finishes
  /// naturally OR when [stop] is called.
  Future<void> speak(String text);

  /// Measured audio length (ms) of the most recently completed [speak], or 0 if
  /// none has completed. Powers the Phase-3 timing table.
  int get lastUtteranceMs;

  /// Optional hint to begin preparing [text] ahead of time so a later [speak]
  /// of the same text is instant. Engines that stream internally (e.g. system
  /// TTS) may treat this as a no-op.
  void precache(String text);

  /// Optional hint that [text] is the *immediate next* utterance, so the engine
  /// can fully arm it for instant start (e.g. pre-load the audio player), not
  /// just pre-synthesize it. No-op for engines without a per-clip start cost.
  void preloadNext(String text);

  /// Set output volume in [0.0, 1.0]. Used to duck under transient
  /// interruptions (e.g. a navigation prompt) without stopping playback.
  Future<void> setVolume(double volume);

  /// Pause the currently-playing utterance in place, keeping its position so
  /// [resume] can continue it. No-op if nothing is playing.
  Future<void> pause();

  /// Resume an utterance paused by [pause]. No-op if not paused.
  Future<void> resume();

  /// Stop any current or pending speech immediately and unblock a pending
  /// [speak] future.
  Future<void> stop();

  /// Switch the active voice if this engine supports voices. The argument is an
  /// opaque voice descriptor (a `VoiceConfig` for the neural engine); engines
  /// that don't support voices treat it as a no-op. Kept as [Object] so this
  /// interface stays free of any engine-specific imports.
  Future<void> setVoiceIfNeeded(Object voice) async {}

  /// Release native resources.
  Future<void> dispose();
}

/// Which engine the user has selected.
enum TtsMode { system, neural }

extension TtsModeLabel on TtsMode {
  String get label => this == TtsMode.system ? 'System' : 'Neural';
}
