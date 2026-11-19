import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'segmenter.dart';

/// The text at the top of a reader page, found from the `cssSelector` that
/// Readium puts in its page locators (#63).
///
/// A page locator (saved when the page turns, by hand or by narration) carries
/// no text, only a layout-dependent `progression` and the selector of the
/// first visible element. The selector is the precise part: resolving it
/// against the chapter's HTML gives the words on screen, so narration can
/// start there and the reader can reopen on them.
class PageAnchor {
  const PageAnchor({
    required this.matchText,
    required this.highlight,
    required this.cssSelector,
  });

  /// Narratable text from the anchor onward, whitespace-collapsed — for
  /// matching against the chapter's sentences.
  final String matchText;

  /// The first text node's raw text, as it appears in the DOM — for a Readium
  /// text locator (Readium searches the live document for it).
  final String highlight;

  /// `:root > :nth-child(..)` path to the element holding [highlight]; the
  /// root Readium searches within.
  final String cssSelector;

  static const maxMatchChars = 160;
  static const maxHighlightChars = 120;
}

const _segmenter = Segmenter();

const _voidTags = {
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'param', 'source', 'track', 'wbr',
};

final _selfClosing = RegExp(r'<([A-Za-z][\w:.-]*)((?:\s[^<>]*?)?)\s*/>');
final _nthChild = RegExp(r'^:nth-child\((\d+)\)$');

/// Resolve Readium's [cssSelector] in a chapter's [html] to the narratable
/// text it marks. An element with no narratable text of its own (a `<br>`, a
/// page marker, the chapter header) anchors on the text that follows it.
/// Returns null when the selector doesn't resolve or no text follows.
PageAnchor? pageAnchorAt(String html, String cssSelector) {
  if (html.trim().isEmpty || cssSelector.trim().isEmpty) return null;
  try {
    final doc = html_parser.parse(_expandSelfClosing(html));
    final start = _select(doc, cssSelector.trim());
    if (start == null) return null;

    dom.Text? first;
    final buf = StringBuffer();
    var node = _enter(start);
    while (node != null && buf.length < PageAnchor.maxMatchChars) {
      if (node is dom.Element && _skipped(node)) {
        node = _next(node, skipChildren: true);
        continue;
      }
      if (node is dom.Element && node.localName == 'br') {
        if (first != null) buf.write(' ');
      } else if (node is dom.Text) {
        if (first == null && node.text.trim().isNotEmpty) first = node;
        if (first != null) buf.write(node.text);
      }
      node = _next(node);
    }
    final text = first;
    final holder = text?.parent;
    if (text == null || holder == null) return null;

    var match = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (match.length > PageAnchor.maxMatchChars) {
      match = match.substring(0, PageAnchor.maxMatchChars);
    }
    var highlight = text.text.trim();
    if (highlight.length > PageAnchor.maxHighlightChars) {
      highlight = highlight.substring(0, PageAnchor.maxHighlightChars);
    }
    return PageAnchor(
      matchText: match,
      highlight: highlight,
      cssSelector: _pathOf(holder),
    );
  } catch (_) {
    return null;
  }
}

/// The WebView parses EPUB content as XHTML, where `<span/>` is empty; an
/// HTML parser would open it and swallow its siblings, shifting every
/// nth-child count. Expand self-closing non-void elements first.
String _expandSelfClosing(String html) => html.replaceAllMapped(_selfClosing,
    (m) {
      final tag = m[1]!;
      if (_voidTags.contains(tag.toLowerCase())) return m[0]!;
      return '<$tag${m[2]}></$tag>';
    });

/// Readium writes `:root > :nth-child(i) > ...`; walk that by hand (the html
/// package's `:nth-child` doesn't count reliably). Anything else is tried as a
/// plain selector, e.g. an `#id`.
dom.Element? _select(dom.Document doc, String selector) {
  final parts = selector.split('>').map((s) => s.trim()).toList();
  final root = doc.documentElement;
  if (root != null && (parts.first == ':root' || parts.first == 'html')) {
    dom.Element el = root;
    for (final part in parts.skip(1)) {
      final m = _nthChild.firstMatch(part);
      if (m == null) return null;
      final n = int.parse(m[1]!);
      if (n < 1 || n > el.children.length) return null;
      el = el.children[n - 1];
    }
    return el;
  }
  if (selector.contains(':nth-child')) return null;
  return doc.querySelector(selector);
}

/// Start the walk at [start], or past the skipped subtree it sits in.
dom.Node? _enter(dom.Element start) {
  dom.Element? skippedRoot;
  for (dom.Element? e = start; e != null; e = e.parent) {
    if (_skipped(e)) skippedRoot = e;
  }
  return skippedRoot == null ? start : _next(skippedRoot, skipChildren: true);
}

bool _skipped(dom.Element e) => _segmenter.skips(e);

/// The node after [n] in document order.
dom.Node? _next(dom.Node n, {bool skipChildren = false}) {
  if (!skipChildren && n.nodes.isNotEmpty) return n.nodes.first;
  dom.Node? cur = n;
  while (cur != null) {
    final parent = cur.parentNode;
    if (parent == null) return null;
    final i = parent.nodes.indexOf(cur);
    if (i + 1 < parent.nodes.length) return parent.nodes[i + 1];
    cur = parent;
  }
  return null;
}

/// `:root > :nth-child(..)` path from the document element to [e].
String _pathOf(dom.Element e) {
  final steps = <String>[];
  dom.Element? cur = e;
  while (cur != null && cur.parent != null) {
    final i = cur.parent!.children.indexOf(cur) + 1;
    steps.add(':nth-child($i)');
    cur = cur.parent;
  }
  return [':root', ...steps.reversed].join(' > ');
}
