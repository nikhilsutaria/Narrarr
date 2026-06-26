import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/import_service.dart';
import 'package:path/path.dart' as p;

/// Exercises the DRM/validation/copy core of the importer ([importEpubFromFile])
/// without the platform file picker. The "never crashes, clear message" promise
/// (spec challenge #5) is the thing under test.
void main() {
  late Directory tmp;
  late Directory booksDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('narrarr_import_test');
    booksDir = Directory(p.join(tmp.path, 'books'));
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final f = File(p.join(tmp.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  List<int> zipWith(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      final data = content.codeUnits;
      archive.addFile(ArchiveFile(name, data.length, data));
    });
    return ZipEncoder().encode(archive)!;
  }

  test('rejects a DRM-protected EPUB (encryption.xml) with a clear message',
      () async {
    final src = await writeFile(
      'drm.epub',
      zipWith({
        'META-INF/encryption.xml': '<encryption/>',
        'mimetype': 'application/epub+zip',
      }),
    );

    final r = await importEpubFromFile(src: src, booksDir: booksDir, nowMs: 1);

    expect(r.book, isNull);
    expect(r.error, contains('DRM-protected'));
    // Nothing copied into the library on rejection.
    expect(await booksDir.exists(), isFalse);
  });

  test('rejects a non-zip file as not a valid EPUB', () async {
    final src = await writeFile('garbage.epub', 'this is not a zip'.codeUnits);

    final r = await importEpubFromFile(src: src, booksDir: booksDir, nowMs: 1);

    expect(r.book, isNull);
    expect(r.error, contains('not a valid EPUB'));
  });

  test('rejects a valid zip that is not a parseable EPUB as corrupt', () async {
    final src = await writeFile('notepub.epub', zipWith({'hello.txt': 'hi'}));

    final r = await importEpubFromFile(src: src, booksDir: booksDir, nowMs: 1);

    expect(r.book, isNull);
    expect(r.error, contains('corrupt'));
  });

  test('imports a real EPUB: copies it in and reads its metadata', () async {
    final src = File('assets/the-odyssey-homer.epub');
    expect(await src.exists(), isTrue,
        reason: 'bundled sample asset should be present in the repo');

    final r = await importEpubFromFile(src: src, booksDir: booksDir, nowMs: 4242);

    expect(r.error, isNull);
    final book = r.book!;
    expect(book.title.toLowerCase(), contains('odyssey'));
    expect(book.addedAtMs, 4242);
    expect(book.id, endsWith('-4242'));
    // The file was copied into the sandbox and exists there.
    expect(book.filePath, startsWith(booksDir.path));
    expect(await File(book.filePath).exists(), isTrue);
  });
}
