import 'package:audio_service/audio_service.dart';

import '../sync/narration_controller.dart';
import 'neural_narrator.dart';

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
    Future<void> Function(int index)? onHighlight,
  }) {
    controller.onHighlight = onHighlight;
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
  return _handler ??= await AudioService.init(
    builder: () => NarrationAudioHandler(
      NarrationController(engine: NeuralNarrator()),
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.narrarr.audio',
      androidNotificationChannelName: 'Narration',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
