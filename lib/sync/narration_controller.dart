import 'dart:async';

import 'package:flutter/foundation.dart';

import '../narration/tts_engine.dart';
import 'sentence_timing.dart';

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

  /// Supplies the next chapter's sentences when the current chapter is
  /// exhausted, for whole-book playback. Return an empty list at the book's
  /// end. The reader sets this; it also re-points the highlight target to the
  /// new chapter before returning.
  Future<List<String>> Function()? fetchNextChapter;

  /// Timing-table keys. Set by the reader before play; part of the drift cache
  /// key so timings are scoped to a book chapter and voice.
  String voiceId = 'unknown';
  String chapterHref = '';

  /// Emitted when a chapter's timings are complete (chapter exhausted or book
  /// ended). The reader persists these to drift.
  void Function(ChapterTimings finished)? onChapterTimed;

  List<String> _sentences = const [];
  int _index = 0;
  bool _playing = false;
  bool _paused = false;
  int _token = 0;

  ChapterTimingsBuilder? _timingBuilder;
  ChapterTimings? _currentTimings;

  /// Timings measured so far for the current chapter (live, may be partial).
  ChapterTimings? get currentTimings =>
      _currentTimings ?? _timingBuilder?.build();

  int get index => _index;
  bool get isPlaying => _playing;

  /// True while playback is paused (still the active session, just not emitting
  /// audio). Distinct from [isPlaying], which stays true across a pause.
  bool get isPaused => _paused;
  int get sentenceCount => _sentences.length;
  String sentenceTextAt(int index) => _sentences[index];

  /// Load a chapter's sentences and position the highlight at [startIndex]
  /// (clamped) without starting playback. A later [play] (e.g. the reader's
  /// "Listen" button) begins from there — this is how resume-from-position
  /// (#10) lands on the saved sentence instead of the chapter start.
  void setSentences(List<String> sentences, {int startIndex = 0}) {
    _sentences = sentences;
    _index =
        sentences.isEmpty ? 0 : startIndex.clamp(0, sentences.length - 1);
    _timingBuilder =
        ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
    _currentTimings = null;
    notifyListeners();
  }

  /// Start (or resume) playback from [from] (defaults to the current index).
  Future<void> play({int? from}) async {
    if (_sentences.isEmpty) return;
    final token = ++_token;
    _playing = true;
    _paused = false;
    notifyListeners();

    var i = (from ?? _index).clamp(0, _sentences.length - 1);
    while (true) {
      for (; i < _sentences.length; i++) {
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
        if (token != _token) return;
        _timingBuilder?.add(engine.lastUtteranceMs);
      }

      // Chapter exhausted — try to roll into the next one without dropping the
      // playing state (keeps the transport bar up; TTS already pauses between
      // chapters naturally).
      if (token != _token) return;
      _finalizeChapterTimings();
      final next = await fetchNextChapter?.call() ?? const [];
      if (token != _token) return;
      if (next.isEmpty) break; // end of book
      _sentences = next;
      i = 0;
      _timingBuilder =
          ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
    }

    if (token == _token) {
      _finalizeChapterTimings();
      _playing = false;
      notifyListeners();
    }
  }

  void _finalizeChapterTimings() {
    final b = _timingBuilder;
    if (b == null || b.length == 0) return;
    final timings = b.build();
    _currentTimings = timings;
    onChapterTimed?.call(timings);
  }

  /// Seed timings from the drift cache so position lookups (tap-to-seek) work
  /// before playback. Playback still re-synthesizes audio but won't re-measure.
  void primeTimings(ChapterTimings cached) {
    _currentTimings = cached;
    notifyListeners();
  }

  /// Seek narration to [index] and play from there. Alias of [playFrom] for the
  /// handler / reader tap-to-seek path.
  Future<void> seekToSentence(int index) => playFrom(index);

  /// Jump to [index] and play from there.
  Future<void> playFrom(int index) => play(from: index);

  /// Pause playback in place. The session stays alive ([isPlaying] remains
  /// true); [resumeNarration] continues the same utterance.
  Future<void> pauseNarration() async {
    if (!_playing || _paused) return;
    _paused = true;
    await engine.pause();
    notifyListeners();
  }

  /// Resume after [pauseNarration].
  Future<void> resumeNarration() async {
    if (!_paused) return;
    _paused = false;
    await engine.resume();
    notifyListeners();
  }

  /// Move [delta] sentences from the current index. If playing, restart from the
  /// new index; if idle (or paused), just reposition.
  Future<void> skipSentence(int delta) async {
    if (_sentences.isEmpty) return;
    final wasPlaying = _playing && !_paused;
    final target = (_index + delta).clamp(0, _sentences.length - 1);
    if (wasPlaying) {
      await stop(); // bumps _token (supersedes the running loop) and halts audio
      unawaited(play(from: target));
    } else {
      _index = target;
      _paused = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _token++;
    _playing = false;
    _paused = false;
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
