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

  /// Optional hint to begin preparing [text] ahead of time so a later [speak]
  /// of the same text is instant. Engines that stream internally (e.g. system
  /// TTS) may treat this as a no-op.
  void precache(String text);

  /// Optional hint that [text] is the *immediate next* utterance, so the engine
  /// can fully arm it for instant start (e.g. pre-load the audio player), not
  /// just pre-synthesize it. No-op for engines without a per-clip start cost.
  void preloadNext(String text);

  /// Stop any current or pending speech immediately and unblock a pending
  /// [speak] future.
  Future<void> stop();

  /// Release native resources.
  Future<void> dispose();
}

/// Which engine the user has selected.
enum TtsMode { system, neural }

extension TtsModeLabel on TtsMode {
  String get label => this == TtsMode.system ? 'System' : 'Neural';
}
