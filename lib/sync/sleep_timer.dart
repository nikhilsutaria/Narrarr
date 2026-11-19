import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'narration_controller.dart';

/// Sleep timer (#44): pauses narration after a set amount of *listening* time
/// (the countdown holds while paused), fading the volume out over the last
/// seconds — or at the end of the current chapter. Pausing (not stopping)
/// keeps the session, so the position and lock-screen controls survive.
///
/// Owned by the process-wide audio handler so it keeps running with the
/// screen locked.
class SleepTimer extends ChangeNotifier {
  SleepTimer(
    this.controller, {
    this.fadeDuration = const Duration(seconds: 10),
    this.tick = const Duration(seconds: 1),
  }) {
    controller.addListener(_onControllerChanged);
    controller.onPausedAtChapterEnd = _onPausedAtChapterEnd;
  }

  final NarrationController controller;
  final Duration fadeDuration;
  final Duration tick;

  static const presets = [
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  Duration? _remaining;
  bool _endOfChapter = false;
  bool _fading = false;
  Timer? _ticker;

  /// The most recently chosen duration; [extend] adds this much.
  Duration lastDuration = const Duration(minutes: 15);

  bool get isActive => _remaining != null || _endOfChapter;
  bool get endOfChapter => _endOfChapter;

  /// Listening time left, or null when off / in end-of-chapter mode.
  Duration? get remaining => _remaining;

  void start(Duration d) {
    _clear();
    _remaining = d;
    lastDuration = d;
    _ticker = Timer.periodic(tick, _onTick);
    notifyListeners();
  }

  void startEndOfChapter() {
    _clear();
    _endOfChapter = true;
    controller.pauseAtChapterEnd = true;
    notifyListeners();
  }

  /// Add [lastDuration] (switching an end-of-chapter timer to a countdown).
  void extend() {
    final r = _remaining;
    if (r == null) {
      start(lastDuration);
      return;
    }
    _remaining = r + lastDuration;
    _restoreVolume();
    notifyListeners();
  }

  void cancel() {
    if (!isActive) return;
    _clear();
    notifyListeners();
  }

  void _clear() {
    _ticker?.cancel();
    _ticker = null;
    _remaining = null;
    _endOfChapter = false;
    controller.pauseAtChapterEnd = false;
    _restoreVolume();
  }

  void _restoreVolume() {
    if (_fading) {
      _fading = false;
      unawaited(controller.engine.setVolume(1.0));
    }
  }

  void _onTick(Timer _) {
    final r = _remaining;
    if (r == null) return;
    // Count listening time only.
    if (!controller.isPlaying || controller.isPaused) return;

    final left = r - tick;
    _remaining = left;
    if (left <= Duration.zero) {
      _expire();
      return;
    }
    if (left <= fadeDuration) {
      _fading = true;
      final v = math.max(0.05, left.inMilliseconds / fadeDuration.inMilliseconds);
      unawaited(controller.engine.setVolume(v));
    }
    notifyListeners();
  }

  Future<void> _expire() async {
    _ticker?.cancel();
    _ticker = null;
    _remaining = null;
    notifyListeners();
    await controller.pauseNarration();
    _restoreVolume();
  }

  void _onPausedAtChapterEnd() {
    if (!_endOfChapter) return;
    _endOfChapter = false;
    notifyListeners();
  }

  void _onControllerChanged() {
    // Stopping narration (not pausing) ends the timer.
    if (!controller.isPlaying && isActive) cancel();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    controller.removeListener(_onControllerChanged);
    if (controller.onPausedAtChapterEnd == _onPausedAtChapterEnd) {
      controller.onPausedAtChapterEnd = null;
    }
    super.dispose();
  }
}

/// "14:32" for the sleep-timer chip.
String formatCountdown(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}
