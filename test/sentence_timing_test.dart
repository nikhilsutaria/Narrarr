import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/sentence_timing.dart';

void main() {
  ChapterTimings sample() {
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy');
    b.add(1000); // s0: 0..1000
    b.add(2000); // s1: 1000..3000
    b.add(500); // s2: 3000..3500
    return b.build();
  }

  test('builder assigns cumulative offsets', () {
    final t = sample();
    expect(t.sentences.map((s) => s.startMs), [0, 1000, 3000]);
    expect(t.sentences.map((s) => s.endMs), [1000, 3000, 3500]);
    expect(t.totalMs, 3500);
  });

  test('startMsOf returns a sentence start', () {
    expect(sample().startMsOf(1), 1000);
  });

  test('indexAt maps a position to the playing sentence', () {
    final t = sample();
    expect(t.indexAt(0), 0);
    expect(t.indexAt(999), 0);
    expect(t.indexAt(1000), 1); // boundary belongs to the next sentence
    expect(t.indexAt(2999), 1);
    expect(t.indexAt(3499), 2);
  });

  test('indexAt clamps out-of-range positions', () {
    final t = sample();
    expect(t.indexAt(-100), 0);
    expect(t.indexAt(99999), 2);
  });

  test('timings are monotonic and gap-free', () {
    final t = sample();
    for (var i = 1; i < t.sentences.length; i++) {
      expect(t.sentences[i].startMs, t.sentences[i - 1].endMs);
    }
  });

  test('empty chapter is well-formed', () {
    final t = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy').build();
    expect(t.totalMs, 0);
    expect(t.sentences, isEmpty);
    expect(t.indexAt(10), 0);
  });
}
