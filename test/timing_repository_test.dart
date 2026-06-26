import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/drift/library_database.dart';
import 'package:narrarr/sync/sentence_timing.dart';
import 'package:narrarr/sync/timing_repository.dart';

void main() {
  late LibraryDatabase db;
  late TimingRepository repo;

  setUp(() {
    db = LibraryDatabase(NativeDatabase.memory());
    repo = TimingRepository(db);
  });
  tearDown(() => db.close());

  ChapterTimings sample(String voice) {
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: voice);
    b.add(1000);
    b.add(2000);
    return b.build();
  }

  test('save then load round-trips the timings', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got =
        await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy');
    expect(got, isNotNull);
    expect(got!.sentences.map((s) => s.startMs), [0, 1000]);
    expect(got.sentences.map((s) => s.durationMs), [1000, 2000]);
    expect(got.voiceId, 'amy');
  });

  test('load misses on a different voice', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got =
        await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'ryan');
    expect(got, isNull);
  });

  test('save is idempotent (upsert)', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got =
        await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy');
    expect(got!.sentences.length, 2);
  });

  test('evictVoice removes only that voice', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    await repo.save(bookId: 'b1', timings: sample('ryan'));
    await repo.evictVoice('amy');
    expect(await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy'),
        isNull);
    expect(await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'ryan'),
        isNotNull);
  });
}
