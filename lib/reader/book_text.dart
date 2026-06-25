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

/// A chapter resolved for reading: a content-file name fragment (to match
/// against the reader's reading order) and its speakable sentences.
typedef ResolvedChapter = ({String hrefHint, List<String> sentences});

/// Load the EPUB and resolve the chapter to read.
///
/// If [contentFileHint] is given (e.g. the bundled sample's `book-9`), that
/// chapter is used; otherwise the **first substantive chapter** is picked
/// (first content file with > 600 chars of prose, skipping cover/title/nav).
Future<ResolvedChapter> resolveChapter(
  Uint8List epubBytes, {
  String? contentFileHint,
  int? max,
}) async {
  final book = await EpubReader.readBook(epubBytes);
  final files = book.Content?.Html ?? const {};

  String? hint;
  String html = '';

  if (contentFileHint != null) {
    final h = contentFileHint.toLowerCase();
    for (final e in files.entries) {
      if (e.key.toLowerCase().contains(h)) {
        hint = e.key;
        html = e.value.Content ?? '';
        break;
      }
    }
  }

  if (html.isEmpty) {
    for (final e in files.entries) {
      final content = e.value.Content ?? '';
      if (sentencesFromHtml(content).join(' ').length > 600) {
        hint = e.key;
        html = content;
        break;
      }
    }
  }

  // Fall back to the very first content file if nothing substantive was found.
  if (html.isEmpty && files.isNotEmpty) {
    hint = files.keys.first;
    html = files.values.first.Content ?? '';
  }

  final all = sentencesFromHtml(html);
  return (
    hrefHint: hint ?? (contentFileHint ?? ''),
    sentences: max == null ? all : all.take(max).toList(),
  );
}
