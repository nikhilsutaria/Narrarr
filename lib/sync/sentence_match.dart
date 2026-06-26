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

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
