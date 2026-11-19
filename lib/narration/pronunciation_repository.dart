import 'package:drift/drift.dart';

import '../library/drift/library_database.dart';
import 'pronunciation.dart';

/// Pronunciation fixes (#47), stored in the shared library database.
class PronunciationRepository {
  PronunciationRepository(this.db);

  final LibraryDatabase db;

  /// Every entry (global and per-book), global first, then by word.
  Future<List<PronunciationEntry>> all() async {
    final rows = await (db.select(db.pronunciations)
          ..orderBy([
            (t) => OrderingTerm.asc(t.bookId, nulls: NullsOrder.first),
            (t) => OrderingTerm.asc(t.word),
          ]))
        .get();
    return rows.map(_toEntry).toList();
  }

  /// The entries that apply when reading [bookId]: global plus that book's.
  Future<List<PronunciationEntry>> forBook(String bookId) async {
    final rows = await (db.select(db.pronunciations)
          ..where((t) => t.bookId.isNull() | t.bookId.equals(bookId)))
        .get();
    return rows.map(_toEntry).toList();
  }

  /// Add a fix, or update the existing one for the same word in the same
  /// scope (so re-fixing a word replaces rather than duplicates it).
  Future<void> save({
    required String word,
    required String replacement,
    required bool caseSensitive,
    String? bookId,
    int? id,
    required int nowMs,
  }) async {
    final w = word.trim();
    final r = replacement.trim();
    if (w.isEmpty || r.isEmpty) return;
    var targetId = id;
    if (targetId == null) {
      final same = await (db.select(db.pronunciations)
            ..where((t) =>
                t.word.lower().equals(w.toLowerCase()) &
                (bookId == null ? t.bookId.isNull() : t.bookId.equals(bookId))))
          .getSingleOrNull();
      targetId = same?.id;
    }
    final row = PronunciationsCompanion(
      bookId: Value(bookId),
      word: Value(w),
      replacement: Value(r),
      caseSensitive: Value(caseSensitive),
      createdAtMs: Value(nowMs),
    );
    if (targetId == null) {
      await db.into(db.pronunciations).insert(row);
    } else {
      await (db.update(db.pronunciations)..where((t) => t.id.equals(targetId!)))
          .write(row);
    }
  }

  Future<void> delete(int id) =>
      (db.delete(db.pronunciations)..where((t) => t.id.equals(id))).go();

  Future<void> deleteForBook(String bookId) =>
      (db.delete(db.pronunciations)..where((t) => t.bookId.equals(bookId)))
          .go();

  PronunciationEntry _toEntry(PronunciationRow r) => (
        id: r.id,
        bookId: r.bookId,
        word: r.word,
        replacement: r.replacement,
        caseSensitive: r.caseSensitive,
      );
}
