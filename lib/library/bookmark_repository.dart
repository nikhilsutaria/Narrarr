import 'package:drift/drift.dart';

import 'drift/library_database.dart';

/// A saved place in a book (#48).
typedef Bookmark = ({
  int id,
  String bookId,
  String chapterHref,
  int sentenceIndex,
  String snippet,
  int createdAtMs,
});

/// Bookmarks, stored in the shared library database.
class BookmarkRepository {
  BookmarkRepository(this.db);

  final LibraryDatabase db;

  /// Longest snippet kept for the list.
  static const snippetMax = 160;

  Future<int> add({
    required String bookId,
    required String chapterHref,
    required int sentenceIndex,
    required String snippet,
    required int createdAtMs,
  }) {
    final s = snippet.trim();
    return db.into(db.bookmarks).insert(BookmarksCompanion.insert(
          bookId: bookId,
          chapterHref: chapterHref,
          sentenceIndex: sentenceIndex,
          snippet: s.length <= snippetMax ? s : '${s.substring(0, snippetMax - 1)}…',
          createdAtMs: createdAtMs,
        ));
  }

  /// A book's bookmarks, newest first.
  Future<List<Bookmark>> forBook(String bookId) async {
    final rows = await (db.select(db.bookmarks)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAtMs)]))
        .get();
    return [
      for (final r in rows)
        (
          id: r.id,
          bookId: r.bookId,
          chapterHref: r.chapterHref,
          sentenceIndex: r.sentenceIndex,
          snippet: r.snippet,
          createdAtMs: r.createdAtMs,
        ),
    ];
  }

  Future<void> delete(int id) =>
      (db.delete(db.bookmarks)..where((t) => t.id.equals(id))).go();

  /// Remove bookmarks of books no longer in the library.
  Future<void> deleteOrphans(Set<String> keepBookIds) =>
      (db.delete(db.bookmarks)..where((t) => t.bookId.isNotIn(keepBookIds)))
          .go();

  Future<void> deleteForBook(String bookId) =>
      (db.delete(db.bookmarks)..where((t) => t.bookId.equals(bookId))).go();
}
