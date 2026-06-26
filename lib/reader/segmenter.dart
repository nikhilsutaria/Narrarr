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
/// Verse handling is carried from the POC: `<br/>` becomes a space so verse
/// lines don't glue together, and block elements end a line so a sentence never
/// runs across a paragraph boundary.
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
  };

  List<String> sentencesFromHtml(String html) {
    if (html.trim().isEmpty) return const [];
    final doc = html_parser.parse(html);
    final root = doc.body ?? doc.documentElement;
    if (root == null) return const [];

    final buf = StringBuffer();
    _collect(root, buf);

    final text = buf
        .toString()
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
          buf.write(' ');
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
    final raw = para.split(RegExp(r'(?<=[.!?])\s+'));
    final out = <String>[];
    var acc = '';
    for (final piece in raw) {
      acc = acc.isEmpty ? piece : '$acc $piece';
      if (_endsWithAbbreviation(acc)) continue; // not a real sentence end
      out.add(acc.trim());
      acc = '';
    }
    if (acc.trim().isNotEmpty) out.add(acc.trim());
    return out.where((s) => !_isBarePageNumber(s)).toList();
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
