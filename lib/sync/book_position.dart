import 'sentence_match.dart';

/// One chapter of the narratable spine: a content-file name fragment
/// ([hrefHint]) and its speakable sentences. Mirrors `ResolvedChapter` from
/// `reader/book_text.dart` but kept Flutter-free here so position resolution is
/// pure and unit-testable.
typedef SpineChapter = ({String hrefHint, List<String> sentences});

/// A resolved location for narration: which spine chapter and which sentence
/// within it.
typedef BookPosition = ({int spineIndex, int sentenceIndex});

/// Map a reader location to a narration [BookPosition] — the single
/// "start at position X" primitive reused by resume-on-open (#10) and
/// seek-anywhere (#12).
///
/// Resolution is two steps, both reusing the existing tap-to-seek matching:
///   1. **Chapter:** find the spine entry whose [SpineChapter.hrefHint] is a
///      fragment of [locatorHref] (reading-order hrefs contain the content-file
///      name). Returns `null` when the location's chapter isn't in the
///      narratable spine (e.g. cover/nav/footnotes were filtered out) — the
///      caller should fall back to its default start.
///   2. **Sentence:** match [highlightText] against that chapter's sentences
///      ([resolveSentenceIndex]); if there's no usable text, estimate from
///      [progression] (0..1 across the chapter); otherwise sentence 0.
///
/// Pure and Flutter-free: the reader extracts [locatorHref] / [highlightText] /
/// [progression] from a flutter_readium `Locator` and passes the plain values.
BookPosition? resolveBookPosition({
  required List<SpineChapter> spine,
  String? locatorHref,
  String? highlightText,
  double? progression,
}) {
  if (spine.isEmpty) return null;

  final href = locatorHref?.toLowerCase() ?? '';
  if (href.isEmpty) return null;

  final spineIndex = spine.indexWhere(
    (c) => c.hrefHint.isNotEmpty && href.contains(c.hrefHint.toLowerCase()),
  );
  if (spineIndex < 0) return null;

  final sentences = spine[spineIndex].sentences;
  if (sentences.isEmpty) return (spineIndex: spineIndex, sentenceIndex: 0);

  final text = highlightText?.trim() ?? '';
  if (text.isNotEmpty) {
    final i = resolveSentenceIndex(text, sentences);
    if (i >= 0) return (spineIndex: spineIndex, sentenceIndex: i);
  }

  if (progression != null) {
    return (
      spineIndex: spineIndex,
      sentenceIndex: _sentenceFromProgression(progression, sentences.length),
    );
  }

  return (spineIndex: spineIndex, sentenceIndex: 0);
}

int _sentenceFromProgression(double progression, int count) {
  final p = progression.clamp(0.0, 1.0);
  return (p * count).floor().clamp(0, count - 1);
}
