import 'package:drift/drift.dart';

import '../library/drift/library_database.dart';
import 'sentence_timing.dart';

/// Caches measured [ChapterTimings] in drift so re-listening a chapter does not
/// re-measure. Keyed by (bookId, chapterHref, voiceId).
class TimingRepository {
  TimingRepository(this.db);

  final LibraryDatabase db;

  Future<ChapterTimings?> load({
    required String bookId,
    required String chapterHref,
    required String voiceId,
  }) async {
    final rows = await (db.select(db.sentenceTimings)
          ..where((t) =>
              t.bookId.equals(bookId) &
              t.chapterHref.equals(chapterHref) &
              t.voiceId.equals(voiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sentenceIndex)]))
        .get();
    if (rows.isEmpty) return null;
    return ChapterTimings(
      chapterHref: chapterHref,
      voiceId: voiceId,
      sentences: [
        for (final r in rows)
          SentenceTiming(
            index: r.sentenceIndex,
            startMs: r.startMs,
            durationMs: r.durationMs,
          ),
      ],
    );
  }

  Future<void> save({
    required String bookId,
    required ChapterTimings timings,
  }) async {
    await db.batch((b) {
      b.insertAllOnConflictUpdate(
        db.sentenceTimings,
        [
          for (final s in timings.sentences)
            SentenceTimingsCompanion.insert(
              bookId: bookId,
              chapterHref: timings.chapterHref,
              voiceId: timings.voiceId,
              sentenceIndex: s.index,
              startMs: s.startMs,
              durationMs: s.durationMs,
            ),
        ],
      );
    });
  }

  Future<void> evictVoice(String voiceId) =>
      (db.delete(db.sentenceTimings)..where((t) => t.voiceId.equals(voiceId)))
          .go();
}
