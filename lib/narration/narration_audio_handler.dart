import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../sync/narration_controller.dart';
import '../sync/sleep_timer.dart';
import 'neural_narrator.dart';
import 'switchable_tts_engine.dart';
import 'system_narrator.dart';
import 'text_normalizer.dart';
import 'voice_catalog.dart';
import 'voice_settings.dart';
import 'voice_manager.dart';

/// Bridges the sentence-based [NarrationController] to `audio_service`, so
/// narration runs in a foreground service with a lock-screen / Now-Playing
/// `MediaSession` (transport controls, media buttons, headset, audio focus).
///
/// One handler lives for the whole app process (audio_service is a process
/// singleton). It **owns** the controller and the neural engine; a reader
/// session attaches its chapter text and highlight callback via [loadChapter]
/// and detaches via [endSession]. The engine's model load happens lazily on the
/// first [play], keeping it off the app cold-start path.
class NarrationAudioHandler extends BaseAudioHandler {
  NarrationAudioHandler(this.controller) {
    controller.addListener(_broadcast);
    _broadcast();
  }

  final NarrationController controller;

  /// Sleep timer (#44). Lives with the handler (process-wide) so it keeps
  /// counting with the screen locked or the reader backgrounded.
  late final SleepTimer sleepTimer = SleepTimer(controller);

  /// Point the session at a book/chapter: its sentences, notification metadata,
  /// and the reader's highlight callback. Replaces any previous session.
  ///
  /// [startSentence] positions the highlight (clamped) without auto-playing, so
  /// resume-from-position (#10) and chapter jumps (#12) land on the right
  /// sentence the next time the user presses play.
  void loadChapter({
    required String bookId,
    required String title,
    String? author,
    required List<String> sentences,
    String voiceId = 'unknown',
    String chapterHref = '',
    int startSentence = 0,
    List<int> paragraphStarts = const [],
    Future<void> Function(int index)? onHighlight,
  }) {
    controller.onHighlight = onHighlight;
    controller.voiceId = voiceId;
    controller.chapterHref = chapterHref;
    controller.setSentences(sentences,
        startIndex: startSentence, paragraphStarts: paragraphStarts);
    mediaItem.add(MediaItem(id: bookId, title: title, artist: author));
  }

  /// Detach the current reader (clears the highlight callback) and stop audio.
  Future<void> endSession() async {
    controller.onHighlight = null;
    await stop();
  }

  @override
  Future<void> play() =>
      controller.isPaused ? controller.resumeNarration() : controller.play();

  @override
  Future<void> pause() => controller.pauseNarration();

  @override
  Future<void> stop() async {
    await controller.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() => controller.skipSentence(1);

  @override
  Future<void> skipToPrevious() => controller.skipSentence(-1);

  /// Seek narration to a specific sentence (tap-to-seek from the reader).
  Future<void> seekToSentence(int index) => controller.seekToSentence(index);

  /// Re-read the persisted voice settings and apply them: route the engine to
  /// the system TTS (#15) or a neural voice, and apply speed (#34) and the
  /// listening preferences (#45). Called at reader open, on every Listen, and
  /// before a pronunciation preview, so changes made in Settings apply
  /// without reopening the book (#30).
  Future<VoiceSettings> applyVoiceSettings({VoiceSettingsStore? store}) async {
    final vs = await (store ?? VoiceSettingsStore()).load();
    final id = vs.activeVoiceId;
    final engine = controller.engine;
    if (engine is SwitchableTtsEngine) {
      if (id == kSystemVoiceId) {
        await engine.useSystem();
      } else {
        await engine.useNeural(VoiceCatalog.byId(id) ?? VoiceCatalog.amyLow);
      }
    } else {
      // Injected test engines aren't switchable; still forward the voice.
      await engine
          .setVoiceIfNeeded(VoiceCatalog.byId(id) ?? VoiceCatalog.amyLow);
    }
    // Keep the timing-cache key in step with the selection mid-session.
    controller.voiceId = id;
    controller.speechSpeed = vs.speechSpeed;
    await engine.setSpeed(vs.speechSpeed);
    skipInterval = Duration(seconds: vs.skipSeconds);
    controller.autoRewind = vs.autoRewind;
    return vs;
  }

  /// Speak [text] once with the current voice — the pronunciation preview
  /// (#47). Stops any narration first (the session's position is kept), so
  /// the preview never interleaves with a paused utterance.
  Future<void> previewSpeech(String text, {VoiceSettingsStore? store}) async {
    if (controller.isPlaying) await stop();
    await applyVoiceSettings(store: store);
    await controller.engine.init();
    await controller.engine.speak(const TextNormalizer().normalize(text));
  }

  /// Time-skip interval for rewind / fast-forward (#45); the reader applies
  /// the user's setting.
  Duration skipInterval = const Duration(seconds: 30);

  /// Lock-screen / headset rewind: skip back by [skipInterval] (#45).
  @override
  Future<void> rewind() => controller.skipTime(-skipInterval);

  /// Lock-screen / headset fast-forward: skip ahead by [skipInterval] (#45).
  @override
  Future<void> fastForward() => controller.skipTime(skipInterval);

  // ---- audio focus / interruptions (#9) ----

  static const double _duckVolume = 0.3;
  bool _resumeAfterInterruption = false;

  /// React to an audio-focus interruption (incoming call, other media, a
  /// transient navigation prompt). Pure logic — unit-tested; wired to
  /// `AudioSession.interruptionEventStream` in [narrationHandler].
  Future<void> onInterruption(AudioInterruptionEvent event) async {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          await controller.engine.setVolume(_duckVolume);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = controller.isPlaying && !controller.isPaused;
          await pause();
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          await controller.engine.setVolume(1.0);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          if (_resumeAfterInterruption) {
            _resumeAfterInterruption = false;
            await play();
          }
      }
    }
  }

  /// The output route became noisy (headset unplugged / Bluetooth disconnect).
  /// Standard behaviour: pause so audio doesn't blast from the speaker.
  Future<void> onBecomingNoisy() => pause();

  /// Translate controller state into the playback state audio_service publishes
  /// to the system (notification + lock screen).
  void _broadcast() {
    final playing = controller.isPlaying && !controller.isPaused;
    playbackState.add(playbackState.value.copyWith(
      // Time skip (#45) is the most useful lock-screen control, so the compact
      // view shows rewind / play-pause / fast-forward; sentence skip stays in
      // the expanded view and on headset next/previous.
      controls: [
        MediaControl.rewind,
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 2, 4],
      // Surface synth stalls as buffering (#40) so the lock screen shows a
      // loading state instead of a frozen "playing".
      processingState: controller.isBuffering
          ? AudioProcessingState.buffering
          : AudioProcessingState.ready,
      playing: playing,
    ));
  }
}

NarrationAudioHandler? _handler;

/// Lazily initialise (once) and return the process-wide narration handler.
/// Called by the reader the first time it needs narration — not at app launch,
/// to keep `AudioService.init` and the engine off the cold-start path.
Future<NarrationAudioHandler> narrationHandler() async {
  final existing = _handler;
  if (existing != null) return existing;

  final handler = await AudioService.init(
    builder: () => NarrationAudioHandler(
      NarrationController(
        // System TTS is the safe default until the reader applies the user's
        // persisted selection (#15); the neural engine only loads its model on
        // its own lazy init.
        engine: SwitchableTtsEngine(
          system: SystemNarrator(),
          neural: NeuralNarrator(voiceManager: DownloadingVoiceManager()),
        ),
      ),
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.narrarr.audio',
      androidNotificationChannelName: 'Narration',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  // Own audio focus + interruptions through audio_session (speech profile).
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());
  session.interruptionEventStream.listen(handler.onInterruption);
  session.becomingNoisyEventStream.listen((_) => handler.onBecomingNoisy());

  return _handler = handler;
}
