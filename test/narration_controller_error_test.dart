import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/narration_controller.dart';

import 'support/fake_tts_engine.dart';

/// A [FakeTtsEngine] whose speak can be told to fail — the dead-synth case of
/// #30, where playback used to either die silently or sprint through chapters.
class ExplodingTtsEngine extends FakeTtsEngine {
  bool explode = false;

  @override
  Future<void> speak(String text) {
    if (explode) return Future.error(StateError('synth died'));
    return super.speak(text);
  }
}

void main() {
  test('an engine failure stops playback and surfaces a consumable error',
      () async {
    final engine = ExplodingTtsEngine()..explode = true;
    final c = NarrationController(engine: engine);
    var fetchedNext = false;
    c.fetchNextChapter = () async {
      fetchedNext = true;
      return const [];
    };
    c.setSentences(const ['One.', 'Two.', 'Three.']);

    await c.play();

    expect(c.isPlaying, isFalse, reason: 'the loop must stop, not spin');
    expect(fetchedNext, isFalse,
        reason: 'a dead engine must not roll into the next chapter (#30 '
            'chapter-skipping)');
    expect(c.takeError(), contains('synth died'));
    expect(c.takeError(), isNull, reason: 'error is consumed on read');
  });

  test('a mid-chapter failure keeps the position and stops there', () async {
    final engine = ExplodingTtsEngine();
    final c = NarrationController(engine: engine);
    c.setSentences(const ['One.', 'Two.', 'Three.']);

    final playing = c.play();
    await pumpEventQueue();
    expect(c.index, 0);

    // First sentence plays fine; the engine dies on the second.
    engine.explode = true;
    engine.finishCurrent();
    await playing;

    expect(c.index, 1, reason: 'stopped on the sentence that failed');
    expect(c.isPlaying, isFalse);
    expect(c.takeError(), isNotNull);
  });

  test('a failure superseded by stop() stays quiet', () async {
    final engine = ExplodingTtsEngine();
    final c = NarrationController(engine: engine);
    c.setSentences(const ['One.', 'Two.']);

    final playing = c.play();
    await pumpEventQueue();
    await c.stop(); // bumps the token; the in-flight speak resolves after
    engine.finishCurrent();
    await playing;

    expect(c.takeError(), isNull);
    expect(c.isPlaying, isFalse);
  });
}
