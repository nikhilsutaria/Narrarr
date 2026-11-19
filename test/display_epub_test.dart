import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/display_epub.dart';

/// A minimal EPUB: mimetype first + stored, one chapter at depth 1 and one at
/// depth 2, plus a non-HTML resource that must pass through untouched.
Uint8List _epub() {
  final a = Archive();
  final mime = utf8.encode('application/epub+zip');
  a.addFile(ArchiveFile('mimetype', mime.length, mime)..compress = false);
  void add(String name, String text) {
    final b = utf8.encode(text);
    a.addFile(ArchiveFile(name, b.length, b));
  }

  add('META-INF/container.xml',
      '<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>');
  add('OEBPS/content.opf',
      '<package><manifest><item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c1"/></spine></package>');
  add('OEBPS/ch1.xhtml',
      '<html><head><title>One</title></head><body><p>Hi.</p></body></html>');
  add('OEBPS/text/ch2.xhtml',
      '<html><HEAD><title>Two</title></HEAD><body><p>Yo.</p></body></html>');
  add('OEBPS/style.css', 'p { color: red; }');
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

final _fonts = {
  'AtkinsonHyperlegible-Regular.ttf': Uint8List.fromList([1, 2, 3]),
  'AtkinsonHyperlegible-Bold.ttf': Uint8List.fromList([4, 5, 6]),
  'AtkinsonHyperlegible-Italic.ttf': Uint8List.fromList([7, 8, 9]),
};

String _text(Archive a, String name) =>
    utf8.decode(a.findFile(name)!.content as List<int>);

void main() {
  test('adds the font files and a @font-face stylesheet (#18)', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));

    for (final f in _fonts.keys) {
      expect(out.findFile('$readerFontDir/$f'), isNotNull, reason: f);
    }
    final css = _text(out, '$readerFontDir/$readerFontCss');
    expect(css, contains("font-family: 'Atkinson Hyperlegible'"));
    expect(css, contains('AtkinsonHyperlegible-Bold.ttf'));
    expect(css, contains('font-weight: bold'));
    expect(css, contains('font-style: italic'));
  });

  test('declares single-name serif/sans aliases backed by system fonts (#18)', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));
    final css = _text(out, '$readerFontDir/$readerFontCss');
    expect(css, contains("font-family: 'Narrarr Serif'; src: local('Noto Serif')"));
    expect(css, contains("font-family: 'Narrarr Sans'; src: local('Roboto')"));
    expect(css, contains("local('Noto Serif Bold Italic')"));
  });

  test('links the stylesheet from every HTML document with a correct relative path', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));

    expect(_text(out, 'OEBPS/ch1.xhtml'),
        contains('href="../$readerFontDir/$readerFontCss"'));
    // Case-insensitive </HEAD>, two levels deep.
    expect(_text(out, 'OEBPS/text/ch2.xhtml'),
        contains('href="../../$readerFontDir/$readerFontCss"'));
    // The link lands inside <head>.
    final ch1 = _text(out, 'OEBPS/ch1.xhtml');
    expect(ch1.indexOf(readerFontCss), lessThan(ch1.indexOf('</head>')));
  });

  test('declares the injected files in the OPF manifest (Readium serves only manifest items)', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));
    final opf = _text(out, 'OEBPS/content.opf');
    expect(opf, contains('href="../$readerFontDir/$readerFontCss" media-type="text/css"'));
    expect(opf, contains('href="../$readerFontDir/AtkinsonHyperlegible-Regular.ttf" media-type="font/ttf"'));
    // Inserted inside <manifest>, existing items kept.
    expect(opf.indexOf('narrarr-font'), lessThan(opf.indexOf('</manifest>')));
    expect(opf, contains('href="ch1.xhtml"'));
    // Idempotent.
    final twice = ZipDecoder().decodeBytes(
        withReaderFonts(withReaderFonts(_epub(), _fonts), _fonts));
    expect(readerFontCss.allMatches(_text(twice, 'OEBPS/content.opf')).length, 1);
  });

  test('leaves non-HTML resources untouched', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));
    expect(_text(out, 'OEBPS/style.css'), 'p { color: red; }');
  });

  test('keeps mimetype first and stored (OCF requirement)', () {
    final out = ZipDecoder().decodeBytes(withReaderFonts(_epub(), _fonts));
    expect(out.files.first.name, 'mimetype');
    expect(out.files.first.compress, isFalse);
    expect(_text(out, 'mimetype'), 'application/epub+zip');
  });

  test('is idempotent: a second pass does not double-inject', () {
    final once = withReaderFonts(_epub(), _fonts);
    final twice = ZipDecoder().decodeBytes(withReaderFonts(once, _fonts));
    final ch1 = _text(twice, 'OEBPS/ch1.xhtml');
    expect(readerFontCss.allMatches(ch1).length, 1);
  });

  test('a document without </head> is left as-is', () {
    final a = ZipDecoder().decodeBytes(_epub());
    final b = utf8.encode('<html><body>No head</body></html>');
    a.addFile(ArchiveFile('OEBPS/nohead.xhtml', b.length, b));
    final out = ZipDecoder().decodeBytes(
        withReaderFonts(Uint8List.fromList(ZipEncoder().encode(a)!), _fonts));
    expect(_text(out, 'OEBPS/nohead.xhtml'), '<html><body>No head</body></html>');
  });
}
