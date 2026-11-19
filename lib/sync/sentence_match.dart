/// Resolve a reader text selection to the chapter sentence it belongs to, for
/// tap-to-seek. Pure and Flutter-free so it is unit-testable.
///
/// Matching is whitespace-normalized and case-insensitive. A selection that is
/// contained in a sentence (the common case: the user selects part of a line)
/// or that contains a sentence both count as a hit; the first match wins.
/// Returns -1 when nothing matches (caller should no-op).
int resolveSentenceIndex(String selectedText, List<String> sentences) {
  final sel = _normalize(selectedText);
  if (sel.isEmpty) return -1;
  for (var i = 0; i < sentences.length; i++) {
    final s = _normalize(sentences[i]);
    if (s.isEmpty) continue;
    if (s.contains(sel) || sel.contains(s)) return i;
  }
  return -1;
}

/// Resolve the text at the top of a reader page (a page anchor's match
/// text, #63) to the sentence it starts at. Unlike a selection, the anchor
/// runs on past its first sentence, so:
///  - first choice: sentences aligned with the anchor's start — the anchor
///    begins with the whole sentence, or is the start of a longer one;
///  - otherwise: a sentence containing the anchor's opening words (the page
///    begins mid-sentence).
/// A sentence merely contained somewhere in the anchor never counts. Repeated
/// lines (Homer repeats whole verses) are told apart by [near], the page's
/// rough position in the chapter (0..1); without it the first wins.
/// Returns -1 when nothing matches.
int resolveAnchorIndex(String anchorText, List<String> sentences,
    {double? near}) {
  final a = _normalize(anchorText);
  if (a.isEmpty) return -1;
  final head = a.length > 40 ? a.substring(0, 40) : a;
  final aligned = <int>[];
  final containing = <int>[];
  for (var i = 0; i < sentences.length; i++) {
    final s = _normalize(sentences[i]);
    if (s.isEmpty) continue;
    if (a.startsWith(s) || s.startsWith(a)) {
      aligned.add(i);
    } else if (s.contains(head)) {
      containing.add(i);
    }
  }
  final pool = aligned.isNotEmpty ? aligned : containing;
  if (pool.isEmpty) return -1;
  if (near == null) return pool.first;
  final target = near.clamp(0.0, 1.0) * sentences.length;
  return pool.reduce(
      (best, i) => (i - target).abs() < (best - target).abs() ? i : best);
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
