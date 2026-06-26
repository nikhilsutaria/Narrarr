/// Build human-readable chapter titles for the narratable spine, for the
/// Contents picker (#12). Pure and Flutter-free so it is unit-testable.
///
/// For each chapter (identified by its content-file [hrefHints] entry) it
/// prefers a matching table-of-contents title; falling back to a humanized
/// file name (`book-9.xhtml` → "Book 9"), then a generic "Section N".
List<String> chapterTitles({
  required List<String> hrefHints,
  List<TocEntry> toc = const [],
}) {
  final out = <String>[];
  for (var i = 0; i < hrefHints.length; i++) {
    final fromToc = _tocTitleFor(hrefHints[i], toc);
    final humanized = fromToc ?? _humanize(hrefHints[i]);
    out.add(humanized.isEmpty ? 'Section ${i + 1}' : humanized);
  }
  return out;
}

/// A table-of-contents link: its target [href] and display [title].
typedef TocEntry = ({String href, String title});

String? _tocTitleFor(String hint, List<TocEntry> toc) {
  final base = _basename(hint).toLowerCase();
  if (base.isEmpty) return null;
  for (final e in toc) {
    final title = e.title.trim();
    if (title.isEmpty) continue;
    final hrefBase = _basename(_stripFragment(e.href)).toLowerCase();
    if (hrefBase == base || hrefBase.contains(base) || base.contains(hrefBase)) {
      return title;
    }
  }
  return null;
}

String _basename(String path) {
  final norm = path.replaceAll(r'\', '/');
  final i = norm.lastIndexOf('/');
  return i >= 0 ? norm.substring(i + 1) : norm;
}

String _stripFragment(String s) {
  final i = s.indexOf('#');
  return i >= 0 ? s.substring(0, i) : s;
}

String _humanize(String hint) {
  var s = _basename(hint);
  final dot = s.lastIndexOf('.');
  if (dot > 0) s = s.substring(0, dot);
  s = s.replaceAll(RegExp(r'[_\-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return '';
  return s
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
