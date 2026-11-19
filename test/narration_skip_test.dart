import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/narration_controller.dart';
import 'package:narrarr/sync/progress_estimate.dart';

import 'support/fake_tts_engine.dart';

/// 100-char sentences: at the default rate each lasts 6 s at 1x.
List<String> _chapter(String tag, int n) =>
    [for (var i = 0; i < n; i++) '$tag$i'.padRight(100, '.')];

const _sentenceMs = 100 * BookLength.defaultMsPerChar; // 6000

void main() {
  late FakeTtsEngine fake;
  late NarrationController c;

  setUp(() {
    fake = FakeTtsEngine();
    c = NarrationController(engine: fake);
  });

  group('skipTime (#45)', () {
    test('forward 30 s moves by ~30 s of estimated audio', () async {
      c.setSentences(_chapter('a', 20));
      await c.skipTime(const Duration(seconds: 30));
      expect(c.index, 30000 ~/ _sentenceMs); // 5
    });

    test('back 30 s from sentence 7 lands on sentence 2', () async {
      c.setSentences(_chapter('a', 20), startIndex: 7);
      await c.skipTime(const Duration(seconds: -30));
      expect(c.index, 2);
    });

    test('scales with narration speed', () async {
      c.speechSpeed = 2.0; // each sentence now plays in 3 s
      c.setSentences(_chapter('a', 20));
      await c.skipTime(const Duration(seconds: 30));
      expect(c.index, 10);
    });

    test('forward past the chapter end continues into the next chapter', () async {
      c.setSentences(_chapter('a', 3)); // 18 s
      final next = _chapter('b', 10);
      c.fetchNextChapter = () async => next;
      await c.skipTime(const Duration(seconds: 30)); // 18 s here + 12 s there
      expect(c.sentenceTextAt(0), next[0]);
      expect(c.index, 2);
    });

    test('forward at the end of the book stops on the last sentence', () async {
      c.setSentences(_chapter('a', 3));
      c.fetchNextChapter = () async => const [];
      await c.skipTime(const Duration(minutes: 5));
      expect(c.index, 2);
    });

    test('back past the chapter start continues into the previous chapter', () async {
      c.setSentences(_chapter('b', 10), startIndex: 1);
      final prev = _chapter('a', 10);
      c.fetchPreviousChapter = () async => prev;
      await c.skipTime(const Duration(seconds: -30)); // 6 s here + 24 s there
      expect(c.sentenceTextAt(0), prev[0]);
      expect(c.index, 6);
    });

    test('while playing, restarts playback from the new sentence', () async {
      final s = _chapter('a', 20);
      c.setSentences(s);
      unawaited(c.play());
      await pumpEventQueue();
      await c.skipTime(const Duration(seconds: 30));
      await pumpEventQueue();
      expect(c.isPlaying, isTrue);
      expect(c.isPaused, isFalse);
      expect(fake.spoken.last, s[5]);
      await c.stop();
    });
  });

  group('skipParagraph (#45)', () {
    test('forward goes to the next paragraph start', () async {
      c.setSentences(_chapter('a', 10), paragraphStarts: const [0, 3, 7]);
      await c.skipParagraph(1);
      expect(c.index, 3);
      await c.skipParagraph(1);
      expect(c.index, 7);
    });

    test('back goes to the current paragraph start, then the previous one', () async {
      c.setSentences(_chapter('a', 10),
          startIndex: 5, paragraphStarts: const [0, 3, 7]);
      await c.skipParagraph(-1);
      expect(c.index, 3);
      await c.skipParagraph(-1);
      expect(c.index, 0);
    });

    test('forward from the last paragraph rolls into the next chapter', () async {
      c.setSentences(_chapter('a', 10),
          startIndex: 8, paragraphStarts: const [0, 7]);
      final next = _chapter('b', 4);
      c.fetchNextChapter = () async {
        c.paragraphStarts = const [0, 2];
        return next;
      };
      await c.skipParagraph(1);
      expect(c.sentenceTextAt(0), next[0]);
      expect(c.index, 0);
    });
  });

  group('skipping while paused (#45)', () {
    test('stays paused at the new position; resume plays from there', () async {
      final s = _chapter('a', 20);
      c.setSentences(s);
      unawaited(c.play());
      await pumpEventQueue();
      await c.pauseNarration();

      await c.skipSentence(3);
      expect(c.index, 3);
      expect(c.isPlaying, isTrue);
      expect(c.isPaused, isTrue);

      await c.resumeNarration();
      await pumpEventQueue();
      expect(c.isPaused, isFalse);
      expect(fake.spoken.last, s[3]);
      await c.stop();
    });
  });

  group('auto-rewind on resume (#45)', () {
    late DateTime now;

    Future<List<String>> playThenPause(int at) async {
      final s = _chapter('a', 20);
      c.clock = () => now;
      c.setSentences(s, startIndex: at, paragraphStarts: const [0, 4, 10]);
      unawaited(c.play());
      await pumpEventQueue();
      await c.pauseNarration();
      return s;
    }

    setUp(() => now = DateTime(2026, 11, 19, 22));

    test('a short pause resumes in place (no restart)', () async {
      await playThenPause(8);
      now = now.add(const Duration(minutes: 2));
      final spokenBefore = fake.spoken.length;
      await c.resumeNarration();
      await pumpEventQueue();
      expect(fake.spoken.length, spokenBefore, reason: 'engine.resume, not a new utterance');
      expect(c.index, 8);
      await c.stop();
    });

    test('over 5 minutes resumes two sentences back', () async {
      final s = await playThenPause(8);
      now = now.add(const Duration(minutes: 10));
      await c.resumeNarration();
      await pumpEventQueue();
      expect(c.index, 6);
      expect(fake.spoken.last, s[6]);
      await c.stop();
    });

    test('over an hour resumes from the start of the paragraph', () async {
      final s = await playThenPause(8);
      now = now.add(const Duration(hours: 2));
      await c.resumeNarration();
      await pumpEventQueue();
      expect(c.index, 4);
      expect(fake.spoken.last, s[4]);
      await c.stop();
    });

    test('can be turned off', () async {
      await playThenPause(8);
      c.autoRewind = false;
      now = now.add(const Duration(hours: 2));
      await c.resumeNarration();
      await pumpEventQueue();
      expect(c.index, 8);
      await c.stop();
    });
  });
}
