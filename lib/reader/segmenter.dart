import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Turns EPUB chapter HTML into clean, speakable sentences (MVP spec §4.4).
///
/// Two jobs the v0.1 regex segmenter couldn't do:
///  1. **Skip non-narratable content** by walking the DOM and dropping whole
///     subtrees — chapter `<header>`, `<nav>`/TOC, footnotes/endnotes,
///     figure captions, tables, page-break markers, and bare page numbers.
///  2. **Abbreviation-aware splitting** — "Dr.", "Mr.", "vol." etc. and single
///     initials ("A.") don't end a sentence.
///
/// Verse handling (#37): `<br/>` ends a line — each verse line is its own
/// utterance with a natural line-end pause instead of gluing a whole stanza
/// into one run-on "sentence" — and block elements end a line so a sentence
/// never runs across a paragraph boundary. Splitting also understands
/// ellipses, closing quotes after terminal punctuation, decimals, and caps
/// pathological unpunctuated run-ons.
class Segmenter {
  const Segmenter();

  static const _skipTags = {
    'header', 'nav', 'figcaption', 'figure', 'table', 'style', 'script',
  };
  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote',
    'section', 'tr', 'article', 'aside',
  };
  // epub:type / role values whose subtree should not be read aloud.
  static const _skipEpubTypes = {
    'footnote', 'endnote', 'rearnote', 'note', 'noteref', 'pagebreak',
    'page-break', 'toc', 'landmarks', 'titlepage', 'cover',
  };
  static const _skipRoles = {
    'doc-footnote', 'doc-endnote', 'doc-pagebreak', 'doc-noteref',
    'navigation', 'doc-toc',
  };
  // Lowercased words that, with a trailing period, are abbreviations — not
  // sentence ends.
  static const _abbreviations = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'rev', 'hon', 'st', 'sr', 'jr',
    'gen', 'col', 'sgt', 'capt', 'lt', 'maj', 'messrs', 'mt',
    'vs', 'etc', 'al', 'cf', 'ed', 'esp', 'ibid', 'op', 'viz',
    'vol', 'no', 'pp', 'pg', 'fig', 'ch', 'sec', 'i.e', 'e.g',
    // #37: common ones the original list missed.
    'inc', 'corp', 'ltd', 'co', 'dept', 'est', 'approx',
    'min', 'max', 'hr', 'hrs', 'oz', 'lb', 'lbs', 'ft',
    'a.m', 'p.m', 'u.s',
  };

  /// A "sentence" longer than this with no terminal punctuation is a run-on
  /// (bad OCR, unpunctuated verse, decorative text); it gets re-split at
  /// clause punctuation so synthesis chunking doesn't operate blind (#37).
  static const int _runOnCap = 400;
  static const int _runOnTarget = 200;

  List<String> sentencesFromHtml(String html) {
    if (html.trim().isEmpty) return const [];
    final doc = html_parser.parse(html);
    final root = doc.body ?? doc.documentElement;
    if (root == null) return const [];

    final buf = StringBuffer();
    _collect(root, buf);

    final text = buf
        .toString()
        // Spaced ellipses (`. . .`) read as three sentence ends; canonicalize
        // before splitting (#37).
        .replaceAll(RegExp(r'\s*\.\s+\.\s+\.'), '...')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), '\n')
        .trim();

    final out = <String>[];
    for (final para in text.split('\n')) {
      if (para.trim().isNotEmpty) out.addAll(_splitParagraph(para.trim()));
    }
    return out;
  }

  /// Depth-first text collection that skips non-narratable subtrees.
  void _collect(dom.Node node, StringBuffer buf) {
    for (final child in node.nodes) {
      if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        if (_skipTags.contains(tag) || _skipByAttribute(child)) continue;
        if (tag == 'br') {
          buf.write('\n'); // verse: a line break ends the utterance (#37)
          continue;
        }
        _collect(child, buf);
        if (_blockTags.contains(tag)) buf.write('\n');
      } else if (child is dom.Text) {
        buf.write(child.text);
      }
    }
  }

  bool _skipByAttribute(dom.Element e) {
    final epubType = _attr(e, 'type'); // matches both `epub:type` and `type`
    for (final t in _skipEpubTypes) {
      if (epubType.contains(t)) return true;
    }
    final role = _attr(e, 'role');
    for (final r in _skipRoles) {
      if (role.contains(r)) return true;
    }
    return false;
  }

  /// Read an attribute whose (possibly namespaced) name ends with [suffix].
  String _attr(dom.Element e, String suffix) {
    for (final entry in e.attributes.entries) {
      if (entry.key.toString().toLowerCase().endsWith(suffix)) {
        return entry.value.toLowerCase();
      }
    }
    return '';
  }

  /// Split one paragraph into sentences, re-merging false breaks after
  /// abbreviations/initials, and dropping bare page numbers.
  List<String> _splitParagraph(String para) {
    final raw = _splitSentences(para);
    final out = <String>[];
    var acc = '';
    for (final piece in raw) {
      acc = acc.isEmpty ? piece : '$acc $piece';
      if (_endsWithAbbreviation(acc)) continue; // not a real sentence end
      out.add(acc.trim());
      acc = '';
    }
    if (acc.trim().isNotEmpty) out.add(acc.trim());
    return [
      for (final s in out)
        if (!_isBarePageNumber(s)) ..._capRunOn(s),
    ];
  }

  /// Sentence-boundary scan (#37): terminal `[.!?]` runs may be followed by
  /// closing quotes/brackets before the whitespace (`said." Yes`), an ellipsis
  /// followed by a lowercase continuation is a pause rather than an end, and a
  /// period between digits (`3. 14` after reflow) never splits.
  List<String> _splitSentences(String para) {
    final boundary = RegExp('([.!?]+)([\'"”’)\\]]*)\\s+');
    final out = <String>[];
    var start = 0;
    for (final m in boundary.allMatches(para)) {
      final punct = m.group(1)!;
      final next = m.end < para.length ? para[m.end] : '';
      if (punct.endsWith('...') && RegExp(r'[a-z]').hasMatch(next)) {
        continue; // trailing-off ellipsis, the sentence carries on
      }
      if (punct == '.' &&
          m.start > 0 &&
          _isDigit(para[m.start - 1]) &&
          _isDigit(next)) {
        continue; // decimal split across a space
      }
      out.add(para.substring(start, m.end).trim());
      start = m.end;
    }
    if (start < para.length) {
      final tail = para.substring(start).trim();
      if (tail.isNotEmpty) out.add(tail);
    }
    return out;
  }

  bool _isDigit(String c) =>
      c.isNotEmpty && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  /// Re-split an unpunctuated run-on at clause punctuation into pieces of
  /// roughly [_runOnTarget] chars.
  List<String> _capRunOn(String s) {
    if (s.length <= _runOnCap) return [s];
    final clauses = RegExp(r'[^,;:—]+[,;:—]*')
        .allMatches(s)
        .map((m) => m.group(0)!.trim())
        .where((c) => c.isNotEmpty);
    final out = <String>[];
    final buf = StringBuffer();
    for (final clause in clauses) {
      if (buf.isNotEmpty && buf.length + 1 + clause.length > _runOnTarget) {
        out.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(clause);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out.isEmpty ? [s] : out;
  }

  bool _endsWithAbbreviation(String s) {
    final t = s.trimRight();
    if (!t.endsWith('.')) return false;
    final m = RegExp(r'([A-Za-z][A-Za-z.]*)\.$').firstMatch(t);
    if (m == null) return false;
    final word = m.group(1)!.toLowerCase();
    if (word.length == 1) return true; // single initial, e.g. "A."
    return _abbreviations.contains(word);
  }

  bool _isBarePageNumber(String s) {
    final t = s.trim();
    if (RegExp(r'^\d+$').hasMatch(t)) return true;
    // Roman numerals of length >= 2 (avoid dropping a lone "I").
    return t.length >= 2 && RegExp(r'^[ivxlcdm]+$', caseSensitive: false).hasMatch(t);
  }
}
