import 'dart:typed_data';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;

/// Turns EPUB chapter HTML into clean, speakable sentences.
///
/// Verse-aware (validated in the POC + reader spike): drops the chapter
/// `<header>`, converts `<br/>` to a space so verse lines don't glue together,
/// treats block-closers as line breaks, then splits on sentence-final
/// punctuation.
///
/// NOTE: this is the v0.1 segmenter. The MVP segmenter ([Phase 1/2]) must skip
/// non-narratable content (footnotes, captions, tables, page numbers) and use
/// an abbreviation-aware tokenizer (ICU BreakIterator). See the MVP spec §4.4.
List<String> sentencesFromHtml(String html) {
  if (html.isEmpty) return const [];
  final pre = html
      .replaceAll(RegExp(r'<header[\s\S]*?</header>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>', caseSensitive: false),
        '\n',
      );
  final doc = html_parser.parse(pre);
  final text = (doc.body?.text ?? doc.documentElement?.text ?? '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();
  return text
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Load the EPUB and return the sentences of the chapter whose content-file
/// name contains [contentFileHint].
Future<List<String>> chapterSentences(
  Uint8List epubBytes, {
  required String contentFileHint,
  int? max,
}) async {
  final book = await EpubReader.readBook(epubBytes);
  final files = book.Content?.Html ?? const {};
  final hint = contentFileHint.toLowerCase();
  String html = '';
  for (final e in files.entries) {
    if (e.key.toLowerCase().contains(hint)) {
      html = e.value.Content ?? '';
      break;
    }
  }
  final all = sentencesFromHtml(html);
  return max == null ? all : all.take(max).toList();
}
