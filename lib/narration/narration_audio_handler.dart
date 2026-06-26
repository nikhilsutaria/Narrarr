import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../sync/narration_controller.dart';
import 'neural_narrator.dart';
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

  /// Point the session at a book/chapter: its sentences, notification metadata,
  /// and the reader's highlight callback. Replaces any previous session.
  void loadChapter({
    required String bookId,
    required String title,
    String? author,
    required List<String> sentences,
    String voiceId = 'unknown',
    String chapterHref = '',
    Future<void> Function(int index)? onHighlight,
  }) {
    controller.onHighlight = onHighlight;
    controller.voiceId = voiceId;
    controller.chapterHref = chapterHref;
    controller.setSentences(sentences);
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
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.ready,
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
        engine: NeuralNarrator(voiceManager: DownloadingVoiceManager()),
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
