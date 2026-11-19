import 'dart:async';

import 'package:flutter/foundation.dart';

import '../narration/text_normalizer.dart';
import '../narration/tts_engine.dart';
import 'progress_estimate.dart';
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
  NarrationController({required this.engine}) {
    engine.onBuffering = _onEngineBuffering;
  }

  final TtsEngine engine;

  /// Written-form → spoken-form transform applied to every sentence at the
  /// engine boundary (#36) — speak, precache and preload all see the same
  /// text so the engine cache keys line up. Highlighting keeps using the
  /// **original** sentence text; nothing reader-facing sees this.
  String Function(String) normalizeForSpeech =
      const TextNormalizer().normalize;

  /// Called to highlight (and page-follow to) sentence [index]. Wired by the
  /// reader screen to flutter_readium's decoration + navigation APIs.
  Future<void> Function(int index)? onHighlight;

  /// Supplies the next chapter's sentences when the current chapter is
  /// exhausted, for whole-book playback. Return an empty list at the book's
  /// end. The reader sets this; it also re-points the highlight target to the
  /// new chapter before returning.
  Future<List<String>> Function()? fetchNextChapter;

  /// Side-effect-free preview of the next chapter's sentences (#35): unlike
  /// [fetchNextChapter] it must not re-point highlights or advance any state.
  /// When set, the loop precaches the next chapter's opening sentences while
  /// the current chapter's tail is still playing, so chapter rollover starts
  /// without a cold-synth stall.
  Future<List<String>> Function()? peekNextChapter;
  bool _peekedAhead = false;

  /// Supplies the previous chapter's sentences for backward skips across a
  /// chapter start (#45). Like [fetchNextChapter] it re-points the highlight
  /// target (and [chapterHref] / [paragraphStarts]); empty at the book start.
  Future<List<String>> Function()? fetchPreviousChapter;

  /// Sentence indices where paragraphs begin in the current chapter (#45).
  /// Chapter callbacks update it alongside the sentences they return.
  List<int> paragraphStarts = const [];

  /// Resume a little earlier after a long pause (#45).
  bool autoRewind = true;

  /// When set, the play loop pauses at the end of the current chapter instead
  /// of reading on (sleep timer "end of chapter", #44). Cleared once used.
  bool pauseAtChapterEnd = false;

  /// Called when [pauseAtChapterEnd] has paused playback.
  void Function()? onPausedAtChapterEnd;

  /// Injectable clock for auto-rewind (tests).
  DateTime Function() clock = DateTime.now;
  DateTime? _pausedAt;

  /// Paused with no utterance in flight (a skip while paused): resuming must
  /// start a fresh play loop rather than un-pause the engine.
  bool _deferredStart = false;

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
  bool _buffering = false;
  int _token = 0;
  String? _error;

  /// True while the engine is stalled on synthesis (#40); the audio handler
  /// mirrors this into the media session's processing state.
  bool get isBuffering => _buffering;

  void _onEngineBuffering(bool buffering) {
    if (_buffering == buffering) return;
    _buffering = buffering;
    notifyListeners();
  }

  /// The narration speed the engine is currently using (#34). Measured
  /// durations are normalised by it so timings recorded at different speeds
  /// stay comparable (#46). The reader keeps this in sync with the engine.
  double speechSpeed = 1.0;

  /// Live narration rate this session, in ms per character at 1x, or null
  /// until at least two sentences have been measured (#46).
  double? get msPerChar =>
      _rateSentences >= 2 && _rateChars > 0 ? _rateMs / _rateChars : null;
  double _rateMs = 0;
  int _rateChars = 0;
  int _rateSentences = 0;

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

  /// Consume the most recent playback error, if any (cleared on read). Set when
  /// the engine fails mid-playback — the loop stops loudly instead of skipping
  /// sentences or dying silently (#30). The reader's change listener reads this
  /// and shows a message.
  String? takeError() {
    final e = _error;
    _error = null;
    return e;
  }

  /// Load a chapter's sentences and position the highlight at [startIndex]
  /// (clamped) without starting playback. A later [play] (e.g. the reader's
  /// "Listen" button) begins from there — this is how resume-from-position
  /// (#10) lands on the saved sentence instead of the chapter start.
  void setSentences(
    List<String> sentences, {
    int startIndex = 0,
    List<int> paragraphStarts = const [],
  }) {
    _sentences = sentences;
    this.paragraphStarts = paragraphStarts;
    _deferredStart = false;
    _index =
        sentences.isEmpty ? 0 : startIndex.clamp(0, sentences.length - 1);
    _peekedAhead = false;
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
    _deferredStart = false;
    notifyListeners();

    var i = (from ?? _index).clamp(0, _sentences.length - 1);
    while (true) {
      for (; i < _sentences.length; i++) {
        if (token != _token) return; // superseded by a newer play()/stop()
        _index = i;
        notifyListeners();
        await onHighlight?.call(i);

        // Look-ahead: pre-synthesize the next couple of sentences so the
        // hand-off is gapless.
        for (var j = i + 1; j <= i + 2 && j < _sentences.length; j++) {
          engine.precache(normalizeForSpeech(_sentences[j]));
        }
        if (i + 1 < _sentences.length) {
          engine.preloadNext(normalizeForSpeech(_sentences[i + 1]));
        }
        // Nearing the chapter's tail: warm the next chapter's opening so the
        // rollover has no cold-synth stall (#35).
        if (i + 2 >= _sentences.length && !_peekedAhead) {
          _peekedAhead = true;
          unawaited(_precacheNextChapterOpening(token));
        }

        try {
          await engine.speak(normalizeForSpeech(_sentences[i]));
        } catch (e) {
          if (token != _token) return; // superseded while failing — stay quiet
          debugPrint('[narration] engine failed on sentence $i: $e');
          _error = e.toString();
          _playing = false;
          _paused = false;
          notifyListeners();
          return;
        }
        if (token != _token) return;
        final ms = (engine.lastUtteranceMs * speechSpeed).round();
        _timingBuilder?.add(ms);
        if (ms > 0) {
          _rateMs += ms;
          _rateChars += _sentences[i].length;
          _rateSentences++;
        }
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
      _peekedAhead = false;
      _timingBuilder =
          ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
      // Sleep timer "end of chapter" (#44): stop at the boundary, positioned
      // at the next chapter's start, paused so the session (and lock-screen
      // controls) survive and resume reads on.
      if (pauseAtChapterEnd) {
        pauseAtChapterEnd = false;
        _index = 0;
        _paused = true;
        _deferredStart = true;
        _pausedAt = clock();
        notifyListeners();
        onPausedAtChapterEnd?.call();
        await onHighlight?.call(0);
        return;
      }
    }

    if (token == _token) {
      _finalizeChapterTimings();
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> _precacheNextChapterOpening(int token) async {
    final peek = peekNextChapter;
    if (peek == null) return;
    try {
      final next = await peek();
      if (token != _token || next.isEmpty) return;
      for (var j = 0; j < 2 && j < next.length; j++) {
        engine.precache(normalizeForSpeech(next[j]));
      }
    } catch (e) {
      // A peek is a hint; the rollover still works, just cold.
      debugPrint('[narration] next-chapter peek failed: $e');
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
    _pausedAt = clock();
    await engine.pause();
    notifyListeners();
  }

  /// Resume after [pauseNarration]. After a long pause, auto-rewind restarts
  /// a little earlier so the listener gets their bearings back (#45).
  Future<void> resumeNarration() async {
    if (!_paused) return;
    final rewindTo = _autoRewindTarget();
    if (_deferredStart || rewindTo != null) {
      _token++;
      await engine.stop();
      unawaited(play(from: rewindTo ?? _index));
      return;
    }
    _paused = false;
    await engine.resume();
    notifyListeners();
  }

  /// Auto-rewind rules (#45): under 5 min resume in place; 5–60 min go back
  /// two sentences; over an hour go back to the start of the paragraph (and
  /// at least two sentences). Never crosses a chapter boundary.
  int? _autoRewindTarget() {
    final at = _pausedAt;
    if (!autoRewind || at == null || _sentences.isEmpty) return null;
    final paused = clock().difference(at);
    if (paused < const Duration(minutes: 5)) return null;
    var target = _index - 2;
    if (paused >= const Duration(hours: 1)) {
      final para = _paragraphStartFor(_index);
      if (para < target) target = para;
    }
    return target.clamp(0, _sentences.length - 1);
  }

  /// Move [delta] sentences from the current index (within the chapter).
  Future<void> skipSentence(int delta) =>
      _moveTo(() async => _index + delta);

  /// Skip by roughly [by] of narration (negative = back), crossing chapter
  /// boundaries in either direction (#45). Durations come from measured
  /// timings when the whole chapter has been timed, else from the live (or
  /// default) per-character rate, at the current [speechSpeed].
  Future<void> skipTime(Duration by) => _moveTo(() async {
        var remaining = by.inMilliseconds.abs();
        var target = _index;
        if (by.isNegative) {
          while (remaining > 0) {
            if (target == 0) {
              final prev = await fetchPreviousChapter?.call() ?? const [];
              if (prev.isEmpty) break;
              _swapChapter(prev);
              target = prev.length;
              continue;
            }
            target--;
            remaining -= _estimatedMs(target);
          }
        } else {
          while (remaining > 0) {
            remaining -= _estimatedMs(target);
            if (target + 1 >= _sentences.length) {
              final next = await fetchNextChapter?.call() ?? const [];
              if (next.isEmpty) break; // end of book: stay on the last sentence
              _swapChapter(next);
              target = 0;
              continue;
            }
            target++;
          }
        }
        return target;
      });

  /// Skip to the next paragraph (delta > 0), or back to the start of the
  /// current paragraph — the previous one if already at its start (#45).
  Future<void> skipParagraph(int delta) => _moveTo(() async {
        if (delta > 0) {
          for (final p in paragraphStarts) {
            if (p > _index) return p;
          }
          final next = await fetchNextChapter?.call() ?? const [];
          if (next.isEmpty) return _index;
          _swapChapter(next);
          return 0;
        }
        final current = _paragraphStartFor(_index);
        if (current < _index) return current;
        for (final p in paragraphStarts.reversed) {
          if (p < current) return p;
        }
        if (_index > 0) return 0;
        final prev = await fetchPreviousChapter?.call() ?? const [];
        if (prev.isEmpty) return 0;
        _swapChapter(prev);
        return paragraphStarts.isEmpty ? 0 : paragraphStarts.last;
      });

  /// Shared reposition: halt any running loop, compute the target (which may
  /// swap chapters), then restore the session state — playing resumes from the
  /// target; paused stays paused there; idle just moves the highlight.
  Future<void> _moveTo(Future<int> Function() computeTarget) async {
    if (_sentences.isEmpty) return;
    final wasPlaying = _playing && !_paused;
    final wasPaused = _playing && _paused;
    if (_playing) {
      _token++; // supersede the running loop
      await engine.stop();
    }
    final target = await computeTarget();
    _index = target.clamp(0, _sentences.length - 1);
    if (wasPlaying) {
      unawaited(play(from: _index));
      return;
    }
    _playing = wasPaused;
    _paused = wasPaused;
    _deferredStart = wasPaused;
    notifyListeners();
    await onHighlight?.call(_index);
  }

  /// Swap in a neighbouring chapter's sentences during a skip. Partial timing
  /// measurements are discarded (they'd misalign with sentence indices).
  void _swapChapter(List<String> sentences) {
    _sentences = sentences;
    _peekedAhead = false;
    _timingBuilder =
        ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
    _currentTimings = null;
  }

  int _paragraphStartFor(int index) {
    var start = 0;
    for (final p in paragraphStarts) {
      if (p > index) break;
      start = p;
    }
    return start;
  }

  /// Estimated duration of sentence [k] at the current speed.
  int _estimatedMs(int k) {
    final t = currentTimings;
    final double ms;
    if (t != null && t.sentences.length == _sentences.length) {
      ms = t.sentences[k].durationMs.toDouble();
    } else {
      ms = _sentences[k].length *
          (msPerChar ?? BookLength.defaultMsPerChar.toDouble());
    }
    return (ms / (speechSpeed <= 0 ? 1 : speechSpeed)).round();
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
