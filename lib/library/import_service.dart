import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'book.dart';

/// Outcome of an import attempt.
class ImportResult {
  const ImportResult._({this.book, this.error, this.canceled = false});
  factory ImportResult.success(Book book) => ImportResult._(book: book);
  factory ImportResult.failure(String error) => ImportResult._(error: error);
  factory ImportResult.cancel() => const ImportResult._(canceled: true);

  final Book? book;
  final String? error;
  final bool canceled;
}

/// Picks a DRM-free EPUB and copies it into [booksDir], returning a [Book].
///
/// Rejects, with a clear message (never crashes), files that are DRM-protected
/// or that fail to parse as EPUB — challenge #5 from the MVP spec.
Future<ImportResult> pickAndImportEpub({
  required Directory booksDir,
  required int nowMs,
}) async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['epub'],
    withData: false,
  );
  if (picked == null || picked.files.isEmpty) return ImportResult.cancel();

  final path = picked.files.single.path;
  if (path == null) return ImportResult.failure('Could not read the selected file.');

  final src = File(path);
  final bytes = await src.readAsBytes();

  // DRM guard: a DRM'd EPUB carries META-INF/encryption.xml.
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final hasEncryption = archive.files.any(
      (f) => f.name.toLowerCase().endsWith('meta-inf/encryption.xml'),
    );
    if (hasEncryption) {
      return ImportResult.failure(
        'This book is DRM-protected. Narrarr only opens DRM-free EPUBs you own.',
      );
    }
  } catch (_) {
    return ImportResult.failure('This file is not a valid EPUB.');
  }

  // Parse for metadata; failure means it isn't a usable EPUB.
  final EpubBook epub;
  try {
    epub = await EpubReader.readBook(bytes);
  } catch (_) {
    return ImportResult.failure('Could not open this EPUB — it may be corrupt.');
  }

  final title = (epub.Title?.trim().isNotEmpty ?? false)
      ? epub.Title!.trim()
      : p.basenameWithoutExtension(path);
  final author = epub.Author?.trim();

  // Copy into the sandbox with a collision-resistant id.
  await booksDir.create(recursive: true);
  final id = '${_slug(p.basenameWithoutExtension(path))}-$nowMs';
  final destPath = p.join(booksDir.path, '$id.epub');
  await src.copy(destPath);

  return ImportResult.success(Book(
    id: id,
    title: title,
    author: (author?.isEmpty ?? true) ? null : author,
    filePath: destPath,
    addedAtMs: nowMs,
  ));
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '')
    .padRight(1, 'book');
