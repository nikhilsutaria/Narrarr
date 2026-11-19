import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/progress_estimate.dart';
import 'package:narrarr/sync/sentence_timing.dart';

ChapterTimings _timings(List<int> durations) {
  final b = ChapterTimings.builder(chapterHref: 'c', voiceId: 'v');
  for (final d in durations) {
    b.add(d);
  }
  return b.build();
}

void main() {
  // Three chapters: 10 + 20 + 70 = 100 characters in total.
  final book = BookLength([
    ['aaaaa', 'bbbbb'], // 10
    ['cccccccccc', 'dddddddddd'], // 20
    ['e' * 30, 'f' * 40], // 70
  ]);

  test('fraction is characters before the current sentence over the book', () {
    expect(book.fractionAt(spineIndex: 0, sentenceIndex: 0), 0);
    expect(book.fractionAt(spineIndex: 1, sentenceIndex: 1), closeTo(0.20, 1e-9));
    expect(book.fractionAt(spineIndex: 2, sentenceIndex: 1), closeTo(0.60, 1e-9));
  });

  test('without timings, falls back to the default per-character rate', () {
    final e = book.estimate(spineIndex: 1, sentenceIndex: 0, speed: 1.0);
    expect(e.chapterRemaining.inMilliseconds, 20 * BookLength.defaultMsPerChar);
    expect(e.bookRemaining.inMilliseconds, 90 * BookLength.defaultMsPerChar);
    expect(e.bookFraction, closeTo(0.10, 1e-9));
  });

  test('measured sentences are used as-is and calibrate the rest of the book', () {
    // Chapter 1 fully measured at 1x: 20 chars took 2000 ms → 100 ms/char.
    final e = book.estimate(
      spineIndex: 1,
      sentenceIndex: 1,
      speed: 1.0,
      chapterTimings: _timings([1000, 1000]),
    );
    expect(e.chapterRemaining.inMilliseconds, 1000); // measured sentence 1
    expect(e.bookRemaining.inMilliseconds, 1000 + 70 * 100); // + calibrated ch 2
  });

  test('partial chapter timings are ignored (their indices may not start at 0)', () {
    final e = book.estimate(
      spineIndex: 1,
      sentenceIndex: 0,
      speed: 1.0,
      chapterTimings: _timings([5000]), // only one of two sentences
    );
    expect(e.chapterRemaining.inMilliseconds, 20 * BookLength.defaultMsPerChar);
  });

  test('a live measured rate overrides the default for unmeasured text', () {
    final e = book.estimate(
        spineIndex: 1, sentenceIndex: 0, speed: 1.0, msPerChar: 80);
    expect(e.chapterRemaining.inMilliseconds, 20 * 80);
    expect(e.bookRemaining.inMilliseconds, 90 * 80);
  });

  test('time left scales with narration speed', () {
    final one = book.estimate(spineIndex: 0, sentenceIndex: 0, speed: 1.0);
    final two = book.estimate(spineIndex: 0, sentenceIndex: 0, speed: 2.0);
    expect(two.bookRemaining.inMilliseconds,
        closeTo(one.bookRemaining.inMilliseconds / 2, 1));
  });

  test('out-of-range positions are clamped, never throw', () {
    final e = book.estimate(spineIndex: 9, sentenceIndex: 99, speed: 1.0);
    expect(e.bookRemaining.inMilliseconds, greaterThanOrEqualTo(0));
    expect(BookLength(const []).estimate(spineIndex: 0, sentenceIndex: 0, speed: 1).bookFraction, 0);
  });

  group('formatDurationShort', () {
    test('rounds to minutes and hours', () {
      expect(formatDurationShort(const Duration(seconds: 20)), '<1 min');
      expect(formatDurationShort(const Duration(minutes: 12, seconds: 31)), '13 min');
      expect(formatDurationShort(const Duration(hours: 3, minutes: 4)), '3 h 4 min');
      expect(formatDurationShort(const Duration(hours: 2)), '2 h');
    });

    test('spoken form for screen readers', () {
      expect(formatDurationSpoken(const Duration(seconds: 10)), 'less than a minute');
      expect(formatDurationSpoken(const Duration(minutes: 1)), '1 minute');
      expect(formatDurationSpoken(const Duration(hours: 1, minutes: 2)), '1 hour 2 minutes');
    });
  });
}
