import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/narration_controller.dart';
import 'package:narrarr/sync/sentence_timing.dart';

import 'support/fake_tts_engine.dart';

void main() {
  test('skipSentence while idle just moves the index', () async {
    final c = NarrationController(engine: FakeTtsEngine());
    c.setSentences(['a', 'b', 'c']);
    await c.skipSentence(2);
    expect(c.index, 2);
    expect(c.isPlaying, false);
  });

  test('skipSentence is clamped to the sentence range', () async {
    final c = NarrationController(engine: FakeTtsEngine());
    c.setSentences(['a', 'b', 'c']);
    await c.skipSentence(-5);
    expect(c.index, 0);
    await c.skipSentence(99);
    expect(c.index, 2);
  });

  test('skipSentence while playing advances and keeps playing', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['a', 'b', 'c']);
    unawaited(c.play()); // blocks on the pending speak('a')
    await pumpEventQueue();
    expect(c.index, 0);
    expect(c.isPlaying, true);

    await c.skipSentence(1);
    await pumpEventQueue();
    expect(c.index, 1);
    expect(c.isPlaying, true);
    expect(fake.spoken.last, 'b');

    await c.stop();
  });

  test('pause sets isPaused; resume clears it, session stays playing', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['a', 'b']);
    unawaited(c.play());
    await pumpEventQueue();

    await c.pauseNarration();
    expect(c.isPaused, true);
    expect(c.isPlaying, true);
    expect(fake.paused, true);

    await c.resumeNarration();
    expect(c.isPaused, false);
    expect(fake.paused, false);

    await c.stop();
  });

  test('fetchNextChapter rolls into the next chapter, then ends the book',
      () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    final chapters = [
      ['c2-a'],
      <String>[], // end of book
    ];
    c.fetchNextChapter = () async =>
        chapters.isEmpty ? const [] : chapters.removeAt(0);
    c.setSentences(['c1-a', 'c1-b']);

    unawaited(c.play());
    // Drain: each pending speak resolves on demand, so step through every
    // sentence in chapter 1 and chapter 2 until the book ends.
    for (var i = 0; i < 10 && c.isPlaying; i++) {
      await pumpEventQueue();
      fake.finishCurrent();
    }
    await pumpEventQueue();

    expect(fake.spoken, ['c1-a', 'c1-b', 'c2-a']);
    expect(c.isPlaying, false);
  });

  test('captures cumulative timings as sentences finish', () async {
    final fake = FakeTtsEngine();
    fake.durations.addAll([1000, 2000]);
    final c = NarrationController(engine: fake)
      ..voiceId = 'amy'
      ..chapterHref = 'ch1';
    c.setSentences(['a', 'b']);

    unawaited(c.play());
    await pumpEventQueue();
    fake.finishCurrent(); // 'a' = 1000ms
    await pumpEventQueue();
    fake.finishCurrent(); // 'b' = 2000ms
    await pumpEventQueue();

    final t = c.currentTimings!;
    expect(t.voiceId, 'amy');
    expect(t.chapterHref, 'ch1');
    expect(t.sentences.map((s) => s.startMs), [0, 1000]);
    expect(t.sentences.map((s) => s.durationMs), [1000, 2000]);

    await c.stop();
  });

  test('finalizes timings on chapter roll-over via onChapterTimed', () async {
    final fake = FakeTtsEngine();
    final finished = <ChapterTimings>[];
    final chapters = [
      ['c2-a'],
      <String>[],
    ];
    final c = NarrationController(engine: fake)
      ..voiceId = 'amy'
      ..chapterHref = 'ch1'
      ..onChapterTimed = finished.add
      ..fetchNextChapter = () async =>
          chapters.isEmpty ? const [] : chapters.removeAt(0);
    c.setSentences(['c1-a']);

    unawaited(c.play());
    for (var i = 0; i < 6 && c.isPlaying; i++) {
      await pumpEventQueue();
      fake.finishCurrent();
    }
    await pumpEventQueue();

    expect(finished.first.chapterHref, 'ch1');
    expect(finished.first.sentences.length, 1);
  });

  test('primeTimings seeds currentTimings before playback', () {
    final c = NarrationController(engine: FakeTtsEngine())
      ..voiceId = 'amy'
      ..chapterHref = 'ch1';
    c.setSentences(['a', 'b']);
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy')
      ..add(1000)
      ..add(2000);
    c.primeTimings(b.build());
    expect(c.currentTimings!.indexAt(1500), 1);
  });

  test('setSentences startIndex positions the highlight without playing', () {
    final c = NarrationController(engine: FakeTtsEngine());
    c.setSentences(['a', 'b', 'c'], startIndex: 2);
    expect(c.index, 2);
    expect(c.isPlaying, false);
  });

  test('setSentences startIndex is clamped to the sentence range', () {
    final c = NarrationController(engine: FakeTtsEngine());
    c.setSentences(['a', 'b'], startIndex: 99);
    expect(c.index, 1);
  });

  test('play after a startIndex begins from that sentence', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['a', 'b', 'c'], startIndex: 1);
    unawaited(c.play());
    await pumpEventQueue();
    expect(fake.spoken.first, 'b');
    await c.stop();
  });

  test('stop clears playing and paused', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['a']);
    unawaited(c.play());
    await pumpEventQueue();
    await c.pauseNarration();
    await c.stop();
    expect(c.isPlaying, false);
    expect(c.isPaused, false);
  });

  test('sentences are normalized at the engine boundary only (#36)', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['He owned 3 ships.']);
    unawaited(c.play());
    await pumpEventQueue();
    expect(fake.spoken, ['He owned three ships.'],
        reason: 'the engine hears spoken-form text');
    expect(c.sentenceTextAt(0), 'He owned 3 ships.',
        reason: 'the reader/highlight side keeps the original text');
    await c.stop();
  });

  test('precache and speak see the same normalized text (cache keys align)',
      () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.setSentences(['First one.', 'He owned 3 ships.']);
    unawaited(c.play());
    await pumpEventQueue();
    expect(fake.precached, contains('He owned three ships.'));
    fake.finishCurrent();
    await pumpEventQueue();
    expect(fake.spoken.last, 'He owned three ships.');
    await c.stop();
  });

  test('nearing the chapter tail precaches the next chapter\'s opening (#35)',
      () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.peekNextChapter = () async => ['n1', 'n2', 'n3'];
    c.fetchNextChapter = () async => const [];
    c.setSentences(['a', 'b', 'c']);

    unawaited(c.play());
    await pumpEventQueue();
    // Playing 'a' (index 0 of 3): not near the tail yet.
    expect(fake.precached, isNot(contains('n1')));

    fake.finishCurrent(); // 'a' done → 'b' (i+2 == length: tail)
    await pumpEventQueue();
    expect(fake.precached, contains('n1'),
        reason: 'next chapter\'s opening warms while the tail plays');
    expect(fake.precached, contains('n2'));
    expect(fake.precached, isNot(contains('n3')),
        reason: 'only the opening two sentences are warmed');

    await c.stop();
  });

  test('a failing peek never breaks playback (#35)', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    c.peekNextChapter = () async => throw StateError('peek boom');
    c.fetchNextChapter = () async => const [];
    c.setSentences(['a', 'b']);

    unawaited(c.play());
    for (var i = 0; i < 6 && c.isPlaying; i++) {
      await pumpEventQueue();
      fake.finishCurrent();
    }
    await pumpEventQueue();
    expect(fake.spoken, ['a', 'b'], reason: 'the peek is only a hint');
    expect(c.isPlaying, false);
  });

  test('engine buffering signal surfaces as isBuffering (#40)', () async {
    final fake = FakeTtsEngine();
    final c = NarrationController(engine: fake);
    expect(c.isBuffering, isFalse);
    fake.onBuffering!(true);
    expect(c.isBuffering, isTrue);
    fake.onBuffering!(false);
    expect(c.isBuffering, isFalse);
  });
}
