import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/narration_controller.dart';

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
}
