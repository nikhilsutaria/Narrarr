import 'package:flutter/foundation.dart';

import '../narration/tts_engine.dart';

/// Drives narration over a list of sentences and tells the reader which
/// sentence to highlight, using the POC's drift-free, completion-driven model:
/// highlight sentence *i*, await its audio, then advance to *i+1*. Look-ahead
/// (`precache` + `preloadNext`) keeps playback gapless.
///
/// Re-entrancy (e.g. tapping a new sentence while playing) is guarded by a
/// monotonic [_token].
///
/// Phase 3 replaces this with a position-driven sync layer (a
/// `sentence → (Locator, startMs, endMs)` table); this controller's completion
/// signal becomes the source of the measured durations there.
class NarrationController extends ChangeNotifier {
  NarrationController({required this.engine});

  final TtsEngine engine;

  /// Called to highlight (and page-follow to) sentence [index]. Wired by the
  /// reader screen to flutter_readium's decoration + navigation APIs.
  Future<void> Function(int index)? onHighlight;

  List<String> _sentences = const [];
  int _index = 0;
  bool _playing = false;
  int _token = 0;

  int get index => _index;
  bool get isPlaying => _playing;
  int get sentenceCount => _sentences.length;
  String sentenceTextAt(int index) => _sentences[index];

  void setSentences(List<String> sentences) {
    _sentences = sentences;
    _index = 0;
    notifyListeners();
  }

  /// Start (or resume) playback from [from] (defaults to the current index).
  Future<void> play({int? from}) async {
    if (_sentences.isEmpty) return;
    final token = ++_token;
    _playing = true;
    notifyListeners();

    for (var i = (from ?? _index).clamp(0, _sentences.length - 1);
        i < _sentences.length;
        i++) {
      if (token != _token) return; // superseded by a newer play()/stop()
      _index = i;
      notifyListeners();
      await onHighlight?.call(i);

      // Look-ahead: pre-synthesize the next couple of sentences and arm the
      // immediate next one on the spare player, so the hand-off is gapless.
      for (var j = i + 1; j <= i + 2 && j < _sentences.length; j++) {
        engine.precache(_sentences[j]);
      }
      if (i + 1 < _sentences.length) engine.preloadNext(_sentences[i + 1]);

      await engine.speak(_sentences[i]);
    }

    if (token == _token) {
      _playing = false;
      notifyListeners();
    }
  }

  /// Jump to [index] and play from there.
  Future<void> playFrom(int index) => play(from: index);

  Future<void> stop() async {
    _token++;
    _playing = false;
    await engine.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _token++;
    engine.dispose();
    super.dispose();
  }
}
