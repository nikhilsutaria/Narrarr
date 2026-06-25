import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'book.dart';

/// Persists the user's library. Phase 1 uses a JSON manifest; Phase 1 Task 7
/// swaps in a drift (SQLite) implementation behind this same interface without
/// touching callers.
abstract class LibraryRepository {
  Future<List<Book>> all();
  Future<void> add(Book book);
  Future<void> remove(String id);
  Future<void> updateLocator(String id, String locatorJson);
}

/// JSON-manifest implementation rooted at [dir] (app-support storage in the app;
/// a temp dir in tests).
class JsonLibraryRepository implements LibraryRepository {
  JsonLibraryRepository(this.dir);

  final Directory dir;

  File get _manifest => File(p.join(dir.path, 'library.json'));

  Future<List<Book>> _load() async {
    if (!await _manifest.exists()) return [];
    try {
      final raw = jsonDecode(await _manifest.readAsString()) as List<dynamic>;
      return raw
          .map((e) => Book.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<Book> books) async {
    await dir.create(recursive: true);
    await _manifest
        .writeAsString(jsonEncode(books.map((b) => b.toJson()).toList()));
  }

  @override
  Future<List<Book>> all() async {
    final books = await _load();
    books.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
    return books;
  }

  @override
  Future<void> add(Book book) async {
    final books = await _load();
    books.removeWhere((b) => b.id == book.id); // upsert by id
    books.add(book);
    await _save(books);
  }

  @override
  Future<void> remove(String id) async {
    final books = await _load()
      ..removeWhere((b) => b.id == id);
    await _save(books);
  }

  @override
  Future<void> updateLocator(String id, String locatorJson) async {
    final books = await _load();
    final i = books.indexWhere((b) => b.id == id);
    if (i == -1) return;
    books[i] = books[i].copyWith(lastLocatorJson: locatorJson);
    await _save(books);
  }
}

/// Default app repository rooted at app-support storage.
Future<LibraryRepository> openAppLibrary() async {
  final support = await getApplicationSupportDirectory();
  return JsonLibraryRepository(Directory(p.join(support.path, 'library')));
}
