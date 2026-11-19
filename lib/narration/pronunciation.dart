/// A user pronunciation fix (#47): speak [word] as [replacement]. A null
/// [bookId] applies to every book; a book entry overrides a global one for the
/// same word.
typedef PronunciationEntry = ({
  int id,
  String? bookId,
  String word,
  String replacement,
  bool caseSensitive,
});

/// Applies pronunciation fixes to a sentence at the engine boundary — the
/// highlighted on-screen text is never changed. Pure and Flutter-free.
///
/// Matching is whole-word (letters/digits on either side block a match),
/// longest phrase first, in a single pass so a replacement is never itself
/// re-processed by another entry.
class PronunciationDictionary {
  PronunciationDictionary(Iterable<PronunciationEntry> entries) {
    // A book entry overrides a global one for the same (case-folded) word.
    final byKey = <String, PronunciationEntry>{};
    for (final e in entries) {
      final word = e.word.trim();
      if (word.isEmpty) continue;
      final key = word.toLowerCase();
      final existing = byKey[key];
      if (existing == null || (existing.bookId == null && e.bookId != null)) {
        byKey[key] = e;
      }
    }
    _entries = byKey.values.toList()
      ..sort((a, b) => b.word.trim().length.compareTo(a.word.trim().length));
    if (_entries.isEmpty) return;
    final alternation =
        _entries.map((e) => RegExp.escape(e.word.trim())).join('|');
    _pattern = RegExp(
      '(?<![\\p{L}\\p{N}])(?:$alternation)(?![\\p{L}\\p{N}])',
      caseSensitive: false,
      unicode: true,
    );
  }

  late final List<PronunciationEntry> _entries;
  RegExp? _pattern;

  bool get isEmpty => _entries.isEmpty;

  String apply(String text) {
    final pattern = _pattern;
    if (pattern == null) return text;
    return text.replaceAllMapped(pattern, (m) {
      final found = m[0]!;
      for (final e in _entries) {
        final word = e.word.trim();
        final hit = e.caseSensitive
            ? found == word
            : found.toLowerCase() == word.toLowerCase();
        if (hit) return e.replacement;
      }
      return found; // e.g. a case-sensitive entry matched the wrong case
    });
  }
}
