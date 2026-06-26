import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/narration_audio_handler.dart';
import 'package:narrarr/sync/narration_controller.dart';

import 'support/fake_tts_engine.dart';

void main() {
  Future<(NarrationAudioHandler, NarrationController, FakeTtsEngine)>
      playing() async {
    final fake = FakeTtsEngine();
    final controller = NarrationController(engine: fake);
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b', title: 'B', sentences: ['a', 'b', 'c']);
    unawaited(handler.play());
    await pumpEventQueue();
    return (handler, controller, fake);
  }

  test('call interruption pauses, and resumes when it ends', () async {
    final (handler, controller, _) = await playing();
    expect(controller.isPlaying && !controller.isPaused, true);

    await handler.onInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause));
    expect(controller.isPaused, true);

    await handler.onInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause));
    expect(controller.isPaused, false);

    await handler.stop();
  });

  test('does not auto-resume if it was not playing before the interruption',
      () async {
    final fake = FakeTtsEngine();
    final controller = NarrationController(engine: fake);
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b', title: 'B', sentences: ['a']);
    // Never started playing.
    await handler.onInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.pause));
    await handler.onInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.pause));
    expect(controller.isPlaying, false);
  });

  test('duck lowers volume on begin and restores on end', () async {
    final (handler, _, fake) = await playing();

    await handler.onInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck));
    expect(fake.volume, lessThan(1.0));

    await handler.onInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck));
    expect(fake.volume, 1.0);

    await handler.stop();
  });

  test('becoming noisy pauses playback', () async {
    final (handler, controller, _) = await playing();
    await handler.onBecomingNoisy();
    expect(controller.isPaused, true);
    await handler.stop();
  });
}
