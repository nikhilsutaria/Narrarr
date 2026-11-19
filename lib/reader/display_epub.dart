import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Why this exists (#18): Atkinson Hyperlegible is bundled as a *Flutter* font,
/// which the Readium reader's webview can't see — so selecting it (the
/// accessibility default!) silently fell back to a generic font. flutter_readium
/// exposes no hook to register web fonts or inject CSS, so instead the reader
/// opens a **display copy** of the EPUB that carries the font files plus a
/// `@font-face` stylesheet linked from every document. The user's imported
/// file is never modified; hrefs are unchanged, so saved locators still match.

/// Folder (at the EPUB root) holding the injected fonts + stylesheet.
const readerFontDir = 'narrarr-fonts';

/// The injected stylesheet's file name inside [readerFontDir].
const readerFontCss = 'narrarr-fonts.css';

/// Bump when the transform changes so stale display copies are rebuilt.
const _displayCopyVersion = 3;

const _fontAssets = <String>[
  'AtkinsonHyperlegible-Regular.ttf',
  'AtkinsonHyperlegible-Bold.ttf',
  'AtkinsonHyperlegible-Italic.ttf',
];

/// `@font-face` rules for the bundled Atkinson files, plus single-name aliases
/// for the Serif / Sans-serif options that resolve to the device's own fonts
/// via `local()` (Android: Noto Serif / Roboto; iOS: Georgia / Helvetica).
final String _css = [
  _face(
    'Atkinson Hyperlegible',
    "url('AtkinsonHyperlegible-Regular.ttf') format('truetype')",
    'normal',
    'normal',
  ),
  _face(
    'Atkinson Hyperlegible',
    "url('AtkinsonHyperlegible-Bold.ttf') format('truetype')",
    'bold',
    'normal',
  ),
  _face(
    'Atkinson Hyperlegible',
    "url('AtkinsonHyperlegible-Italic.ttf') format('truetype')",
    'normal',
    'italic',
  ),
  _face(
    'Atkinson Hyperlegible',
    "url('AtkinsonHyperlegible-Bold.ttf') format('truetype')",
    'bold',
    'italic',
  ),
  for (final (weight, style, suffix, ps) in _styles) ...[
    _face(
      'Narrarr Serif',
      _locals([
        'Noto Serif$suffix',
        'NotoSerif$ps',
        'Droid Serif$suffix',
        'Georgia$suffix',
        'Times New Roman$suffix',
      ]),
      weight,
      style,
    ),
    _face(
      'Narrarr Sans',
      _locals([
        'Roboto$suffix',
        'Roboto$ps',
        'Noto Sans$suffix',
        'Helvetica Neue$suffix',
        'Arial$suffix',
      ]),
      weight,
      style,
    ),
  ],
].join('\n');

/// (weight, style, full-name suffix, PostScript suffix)
const _styles = [
  ('normal', 'normal', '', '-Regular'),
  ('bold', 'normal', ' Bold', '-Bold'),
  ('normal', 'italic', ' Italic', '-Italic'),
  ('bold', 'italic', ' Bold Italic', '-BoldItalic'),
];

String _locals(List<String> names) =>
    names.map((n) => "local('$n')").join(', ');

String _face(String family, String src, String weight, String style) =>
    "@font-face { font-family: '$family'; src: $src; "
    'font-weight: $weight; font-style: $style; }';

final _headClose = RegExp('</head>', caseSensitive: false);

/// Return a copy of [epub] with [fonts] (file name → bytes) and a `@font-face`
/// stylesheet added under [readerFontDir], linked from every (X)HTML document.
/// Pure and idempotent; documents without a `</head>` are left untouched.
Uint8List withReaderFonts(Uint8List epub, Map<String, Uint8List> fonts) {
  final src = ZipDecoder().decodeBytes(epub);
  final out = Archive();
  final cssPath = '$readerFontDir/$readerFontCss';
  final opfPath = _opfPath(src);

  for (final f in src.files) {
    if (!f.isFile) continue;
    if (f.name.startsWith('$readerFontDir/')) continue; // re-added below
    final bytes = f.content as List<int>;
    var data = bytes;
    final lower = f.name.toLowerCase();
    if (lower.endsWith('.xhtml') ||
        lower.endsWith('.html') ||
        lower.endsWith('.htm')) {
      data = _linkStylesheet(f.name, bytes, cssPath);
    } else if (f.name == opfPath) {
      data = _declareInManifest(opfPath!, bytes, [
        for (final name in fonts.keys) ('$readerFontDir/$name', 'font/ttf'),
        (cssPath, 'text/css'),
      ]);
    }
    final copy = ArchiveFile(f.name, data.length, data);
    // OCF: `mimetype` must stay uncompressed (and first — insertion order).
    copy.compress = f.name != 'mimetype';
    out.addFile(copy);
  }

  for (final e in fonts.entries) {
    out.addFile(
      ArchiveFile('$readerFontDir/${e.key}', e.value.length, e.value),
    );
  }
  final css = utf8.encode(_css);
  out.addFile(ArchiveFile(cssPath, css.length, css));

  return Uint8List.fromList(ZipEncoder().encode(out)!);
}

/// The package document's path, from `META-INF/container.xml`.
String? _opfPath(Archive a) {
  final container = a.findFile('META-INF/container.xml');
  if (container == null) return null;
  final xml = utf8.decode(container.content as List<int>, allowMalformed: true);
  return RegExp(r'full-path\s*=\s*"([^"]+)"').firstMatch(xml)?.group(1);
}

/// Readium only serves resources declared in the OPF manifest (anything else
/// gets a placeholder page), so the injected files must be listed there.
List<int> _declareInManifest(
  String opfPath,
  List<int> bytes,
  List<(String, String)> files,
) {
  final opf = utf8.decode(bytes, allowMalformed: true);
  if (opf.contains(readerFontCss)) return bytes; // already declared
  final m = RegExp(r'</(\w+:)?manifest>', caseSensitive: false).firstMatch(opf);
  if (m == null) return bytes;
  final prefix = m.group(1) ?? '';
  final up = _relativeUp(opfPath);
  var n = 0;
  final items = files
      .map(
        (f) =>
            '<${prefix}item id="narrarr-font-${n++}" '
            'href="$up${f.$1}" media-type="${f.$2}"/>',
      )
      .join();
  return utf8.encode(opf.replaceRange(m.start, m.start, items));
}

/// `../` repeated once per directory level of [path] inside the container.
String _relativeUp(String path) =>
    '../' * p.posix.split(p.posix.dirname(path)).where((s) => s != '.').length;

List<int> _linkStylesheet(String name, List<int> bytes, String cssPath) {
  final String html;
  try {
    html = utf8.decode(bytes);
  } on FormatException {
    return bytes; // not UTF-8 — leave it alone rather than corrupt it
  }
  if (html.contains(readerFontCss)) return bytes; // already linked
  final m = _headClose.firstMatch(html);
  if (m == null) return bytes;

  final href = '${_relativeUp(name)}$cssPath';
  final link = '<link rel="stylesheet" type="text/css" href="$href"/>';
  return utf8.encode(html.replaceRange(m.start, m.start, link));
}

/// Path of the display copy for [bookId]'s file at [sourcePath], building it
/// (off the UI isolate) if it's missing or stale. Falls back to [sourcePath]
/// if anything goes wrong — a missing font must never stop a book opening.
Future<String> ensureDisplayCopy({
  required String bookId,
  required String sourcePath,
}) async {
  try {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'display'),
    );
    final target = File(p.join(dir.path, '$bookId.v$_displayCopyVersion.epub'));
    final source = File(sourcePath);
    if (target.existsSync() &&
        !target.lastModifiedSync().isBefore(source.lastModifiedSync())) {
      return target.path;
    }
    final fonts = <String, Uint8List>{
      for (final f in _fontAssets)
        f: (await rootBundle.load('assets/fonts/$f')).buffer.asUint8List(),
    };
    final bytes = await source.readAsBytes();
    final out = await compute(_transform, (bytes, fonts));
    await dir.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(out, flush: true);
    await tmp.rename(target.path);
    return target.path;
  } catch (e) {
    debugPrint('[reader] display copy failed, opening original: $e');
    return sourcePath;
  }
}

Uint8List _transform((Uint8List, Map<String, Uint8List>) args) =>
    withReaderFonts(args.$1, args.$2);

/// Delete every display copy for [bookId] (call when a book is removed).
Future<void> deleteDisplayCopies(String bookId) async {
  try {
    final dir = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'display'),
    );
    if (!dir.existsSync()) return;
    for (final f in dir.listSync().whereType<File>()) {
      if (p.basename(f.path).startsWith('$bookId.v')) await f.delete();
    }
  } catch (e) {
    debugPrint('[reader] display copy cleanup failed: $e');
  }
}
