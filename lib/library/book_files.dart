import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Narrarr's own copies of imported EPUBs (#69).
///
/// Adding a book copies the picked file into [appBooksDir]; the reader only
/// ever opens that copy. The user's original (Downloads, Drive, …) is never
/// modified or deleted — Narrarr has no write access to it — so these helpers
/// only ever delete files inside the books folder.

/// Where imported EPUB copies live.
Future<Directory> appBooksDir() async =>
    Directory(p.join((await getApplicationSupportDirectory()).path, 'books'));

/// Copies written this recently are left alone by the orphan sweep: an
/// import may have copied its file before the library lists the book.
const _freshCopyGrace = Duration(minutes: 10);

/// Delete Narrarr's copy of a removed book at [filePath] — only if it lives
/// inside [booksDir] (the bundled sample, or any other path, is kept).
Future<void> deleteBookCopy(String filePath, Directory booksDir) async {
  if (!_isInside(filePath, booksDir)) return;
  try {
    final f = File(filePath);
    if (await f.exists()) await f.delete();
  } catch (e) {
    debugPrint('[library] deleting book copy failed: $e');
  }
}

/// Delete copies in [booksDir] that no library book refers to: books removed
/// before #69, or removed just before the app died inside the Undo window.
/// [keepPaths] are the file paths of the books still in the library.
Future<void> deleteOrphanBookCopies(
    Directory booksDir, Set<String> keepPaths) async {
  try {
    if (!booksDir.existsSync()) return;
    final keep = {for (final k in keepPaths) _key(k)};
    final cutoff = DateTime.now().subtract(_freshCopyGrace);
    for (final f in booksDir.listSync().whereType<File>()) {
      if (keep.contains(_key(f.path))) continue;
      if (f.lastModifiedSync().isAfter(cutoff)) continue;
      await f.delete();
    }
  } catch (e) {
    debugPrint('[library] book copy sweep failed: $e');
  }
}

String _key(String path) => p.canonicalize(path);

bool _isInside(String path, Directory dir) =>
    p.isWithin(_key(dir.path), _key(path));
