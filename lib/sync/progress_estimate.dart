import 'sentence_timing.dart';

/// Time left in the chapter and book, and how far through the book (#46).
typedef ProgressEstimate = ({
  Duration chapterRemaining,
  Duration bookRemaining,
  double bookFraction,
});

/// The book's narratable text measured in characters — the unit both the
/// progress fraction and the time estimate are built on. Pure and
/// Flutter-free; the reader builds one from its segmented spine.
class BookLength {
  BookLength(List<List<String>> chapters)
      : _sentenceChars = [
          for (final c in chapters) [for (final s in c) s.length],
        ] {
    var total = 0;
    for (final c in _sentenceChars) {
      _chapterStart.add(total);
      for (final n in c) {
        total += n;
      }
    }
    totalChars = total;
  }

  /// Fallback narration rate at 1x before anything has been measured:
  /// ~60 ms/char matches Piper Amy on device (≈16 chars/s) and is close to
  /// typical system voices.
  static const defaultMsPerChar = 60;

  final List<List<int>> _sentenceChars;
  final List<int> _chapterStart = [];
  late final int totalChars;

  /// Fraction of the book's characters before sentence [sentenceIndex] of
  /// chapter [spineIndex] (0..1; clamped).
  double fractionAt({required int spineIndex, required int sentenceIndex}) {
    if (totalChars == 0) return 0;
    final (ci, si) = _clamp(spineIndex, sentenceIndex);
    var before = _chapterStart[ci];
    final c = _sentenceChars[ci];
    for (var k = 0; k < si; k++) {
      before += c[k];
    }
    return before / totalChars;
  }

  /// Estimate time left from the current sentence (inclusive) at [speed].
  ///
  /// [msPerChar] is a live narration rate measured this session (at 1x); when
  /// absent, [defaultMsPerChar] is used. [chapterTimings] are the current
  /// chapter's measured sentence durations normalised to 1x — used per
  /// sentence only when they cover the **whole** chapter (partial builders
  /// number sentences from wherever playback started, so they can't be
  /// matched to sentence indices), and then also to calibrate the rate.
  ProgressEstimate estimate({
    required int spineIndex,
    required int sentenceIndex,
    required double speed,
    ChapterTimings? chapterTimings,
    double? msPerChar,
  }) {
    if (totalChars == 0) {
      return (
        chapterRemaining: Duration.zero,
        bookRemaining: Duration.zero,
        bookFraction: 0,
      );
    }
    final (ci, si) = _clamp(spineIndex, sentenceIndex);
    final chars = _sentenceChars[ci];
    final whole = chapterTimings != null &&
        chars.isNotEmpty &&
        chapterTimings.sentences.length == chars.length;
    final measured =
        whole ? chapterTimings.sentences : const <SentenceTiming>[];

    var rate = msPerChar ?? defaultMsPerChar.toDouble();
    if (msPerChar == null && whole) {
      final n = chars.fold<int>(0, (a, b) => a + b);
      if (n > 0) rate = chapterTimings.totalMs / n;
    }

    var chapterMs = 0.0;
    for (var k = si; k < chars.length; k++) {
      chapterMs += k < measured.length
          ? measured[k].durationMs
          : chars[k] * rate;
    }
    var laterChars = 0;
    for (var c = ci + 1; c < _sentenceChars.length; c++) {
      for (final n in _sentenceChars[c]) {
        laterChars += n;
      }
    }
    final s = speed <= 0 ? 1.0 : speed;
    return (
      chapterRemaining: Duration(milliseconds: (chapterMs / s).round()),
      bookRemaining: Duration(
          milliseconds: ((chapterMs + laterChars * rate) / s).round()),
      bookFraction: fractionAt(spineIndex: ci, sentenceIndex: si),
    );
  }

  (int, int) _clamp(int spineIndex, int sentenceIndex) {
    final ci = spineIndex.clamp(0, _sentenceChars.length - 1);
    final len = _sentenceChars[ci].length;
    final si = len == 0 ? 0 : sentenceIndex.clamp(0, len - 1);
    return (ci, si);
  }
}

/// "13 min", "3 h 4 min", "<1 min" — compact enough for the transport bar.
String formatDurationShort(Duration d) {
  final totalMin = (d.inSeconds / 60).round();
  if (totalMin < 1) return '<1 min';
  final h = totalMin ~/ 60, m = totalMin % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The same duration worded for screen readers: "3 hours 4 minutes".
String formatDurationSpoken(Duration d) {
  final totalMin = (d.inSeconds / 60).round();
  if (totalMin < 1) return 'less than a minute';
  final h = totalMin ~/ 60, m = totalMin % 60;
  String unit(int n, String w) => '$n $w${n == 1 ? '' : 's'}';
  if (h == 0) return unit(m, 'minute');
  return m == 0 ? unit(h, 'hour') : '${unit(h, 'hour')} ${unit(m, 'minute')}';
}
