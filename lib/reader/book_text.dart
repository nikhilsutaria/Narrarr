import 'dart:typed_data';
import 'package:epubx/epubx.dart';

import 'segmenter.dart';

/// Turns EPUB chapter HTML into clean, speakable sentences.
///
/// Thin back-compat wrapper over [Segmenter] (the MVP segmenter: skips
/// non-narratable content, abbreviation-aware). Kept so existing callers/tests
/// keep working.
List<String> sentencesFromHtml(String html) =>
    const Segmenter().sentencesFromHtml(html);

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

/// Resolve the whole book for narration: every **substantive** content document
/// (> 600 chars of narratable prose, skipping cover/title/nav/colophon), in
/// reading order, each already segmented into speakable sentences. Used for
/// cross-chapter, whole-book playback (#6).
Future<List<ResolvedChapter>> resolveSpine(Uint8List epubBytes) async {
  const segmenter = Segmenter();
  final book = await EpubReader.readBook(epubBytes);
  final files = book.Content?.Html ?? const {};

  final out = <ResolvedChapter>[];
  for (final e in files.entries) {
    final sentences = segmenter.sentencesFromHtml(e.value.Content ?? '');
    if (sentences.join(' ').length <= 600) continue; // skip front/back matter
    out.add((hrefHint: e.key, sentences: sentences));
  }

  // Never return empty for a non-empty book: fall back to the first content doc.
  if (out.isEmpty && files.isNotEmpty) {
    final first = files.entries.first;
    out.add((
      hrefHint: first.key,
      sentences: segmenter.sentencesFromHtml(first.value.Content ?? ''),
    ));
  }
  return out;
}
