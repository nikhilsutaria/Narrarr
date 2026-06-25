/// One sentence's place in a chapter's measured audio timeline.
class SentenceTiming {
  const SentenceTiming({
    required this.index,
    required this.startMs,
    required this.durationMs,
  });

  final int index;
  final int startMs;
  final int durationMs;

  int get endMs => startMs + durationMs;
}

/// A chapter's full timeline, built from measured per-sentence durations.
///
/// The single source of truth for the position↔index mapping: [indexAt] is the
/// position-driven primitive (used by tap-to-seek today; speed control and a
/// scrubber later). Timings are voice-specific — [voiceId] is the cache key.
class ChapterTimings {
  ChapterTimings({
    required this.chapterHref,
    required this.voiceId,
    required this.sentences,
  });

  final String chapterHref;
  final String voiceId;
  final List<SentenceTiming> sentences;

  int get totalMs => sentences.isEmpty ? 0 : sentences.last.endMs;

  int startMsOf(int index) => sentences[index].startMs;

  /// Which sentence is playing at [ms] (clamped to range). O(log n).
  int indexAt(int ms) {
    if (sentences.isEmpty) return 0;
    if (ms < 0) return 0;
    if (ms >= totalMs) return sentences.length - 1;
    var lo = 0, hi = sentences.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ms < sentences[mid].endMs) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static ChapterTimingsBuilder builder({
    required String chapterHref,
    required String voiceId,
  }) =>
      ChapterTimingsBuilder(chapterHref: chapterHref, voiceId: voiceId);
}

/// Accumulates measured durations into a [ChapterTimings] as playback proceeds.
class ChapterTimingsBuilder {
  ChapterTimingsBuilder({required this.chapterHref, required this.voiceId});

  final String chapterHref;
  final String voiceId;
  final List<SentenceTiming> _sentences = [];
  int _cursorMs = 0;

  int get length => _sentences.length;

  /// Append the next sentence with its measured [durationMs].
  void add(int durationMs) {
    _sentences.add(SentenceTiming(
      index: _sentences.length,
      startMs: _cursorMs,
      durationMs: durationMs,
    ));
    _cursorMs += durationMs;
  }

  ChapterTimings build() => ChapterTimings(
        chapterHref: chapterHref,
        voiceId: voiceId,
        sentences: List.unmodifiable(_sentences),
      );
}
