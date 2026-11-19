import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/narration_controller.dart';
import 'package:narrarr/sync/sleep_timer.dart';

import 'support/fake_tts_engine.dart';

void main() {
  late FakeTtsEngine fake;
  late NarrationController c;
  late SleepTimer timer;

  void startPlaying(FakeAsync async, {int sentences = 50}) {
    c.setSentences([for (var i = 0; i < sentences; i++) 's$i']);
    unawaited(c.play());
    async.flushMicrotasks();
  }

  setUp(() {
    fake = FakeTtsEngine();
    c = NarrationController(engine: fake);
    timer = SleepTimer(c);
  });

  test('pauses narration (not stops) when the time is up (#44)', () {
    fakeAsync((async) {
      startPlaying(async);
      timer.start(const Duration(minutes: 5));
      expect(timer.isActive, isTrue);

      async.elapse(const Duration(minutes: 4, seconds: 59));
      expect(c.isPaused, isFalse);

      async.elapse(const Duration(seconds: 2));
      expect(c.isPlaying, isTrue, reason: 'session kept so position is kept');
      expect(c.isPaused, isTrue);
      expect(timer.isActive, isFalse);
      expect(fake.volume, 1.0, reason: 'volume restored after the fade');
    });
  });

  test('fades the volume out over the last seconds', () {
    fakeAsync((async) {
      startPlaying(async);
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 45));
      expect(fake.volume, 1.0);
      async.elapse(const Duration(seconds: 10)); // 5 s left of a 10 s fade
      expect(fake.volume, lessThan(0.6));
      expect(fake.volume, greaterThan(0.0));
    });
  });

  test('counts only while narration is audible', () {
    fakeAsync((async) {
      startPlaying(async);
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 30));
      c.pauseNarration();
      async.elapse(const Duration(minutes: 10));
      expect(timer.remaining, const Duration(seconds: 30));
      c.resumeNarration();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 31));
      expect(c.isPaused, isTrue);
    });
  });

  test('extend adds the last-used duration and undoes a fade', () {
    fakeAsync((async) {
      startPlaying(async);
      timer.start(const Duration(minutes: 1));
      async.elapse(const Duration(seconds: 55));
      expect(fake.volume, lessThan(1.0));
      timer.extend();
      expect(timer.remaining, const Duration(minutes: 1, seconds: 5));
      expect(fake.volume, 1.0);
    });
  });

  test('stopping narration cancels the timer', () {
    fakeAsync((async) {
      startPlaying(async);
      timer.start(const Duration(minutes: 5));
      c.stop();
      async.flushMicrotasks();
      expect(timer.isActive, isFalse);
    });
  });

  test('end of chapter pauses at the boundary instead of rolling over', () {
    fakeAsync((async) {
      final next = ['n0', 'n1'];
      c.fetchNextChapter = () async => next;
      startPlaying(async, sentences: 2);
      timer.startEndOfChapter();
      expect(timer.endOfChapter, isTrue);

      fake.finishCurrent();
      async.flushMicrotasks();
      fake.finishCurrent(); // last sentence of the chapter
      async.flushMicrotasks();

      expect(c.isPaused, isTrue);
      expect(c.sentenceTextAt(0), 'n0', reason: 'positioned at the next chapter');
      expect(c.index, 0);
      expect(fake.spoken, isNot(contains('n0')), reason: 'did not read on');
      expect(timer.isActive, isFalse);

      c.resumeNarration();
      async.flushMicrotasks();
      expect(fake.spoken.last, 'n0');
      c.stop();
    });
  });

  test('cancel clears end-of-chapter so playback rolls over normally', () {
    fakeAsync((async) {
      c.fetchNextChapter = () async => ['n0'];
      startPlaying(async, sentences: 1);
      timer.startEndOfChapter();
      timer.cancel();
      fake.finishCurrent();
      async.flushMicrotasks();
      expect(fake.spoken.last, 'n0');
      expect(c.isPaused, isFalse);
      c.stop();
    });
  });
}
