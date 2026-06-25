import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/narration_audio_handler.dart';
import 'package:narrarr/sync/narration_controller.dart';

import 'support/fake_tts_engine.dart';

void main() {
  test('playbackState.playing tracks the controller', () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b1', title: 'Book', sentences: ['a', 'b']);

    expect(handler.playbackState.value.playing, false);

    unawaited(handler.play());
    await pumpEventQueue();
    expect(handler.playbackState.value.playing, true);

    await handler.pause();
    expect(handler.playbackState.value.playing, false);
    expect(controller.isPaused, true);

    await handler.stop();
    expect(handler.playbackState.value.playing, false);
  });

  test('controls swap play<->pause with playing state', () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b1', title: 'Book', sentences: ['a']);

    // Idle: a play control is offered.
    expect(handler.playbackState.value.controls, contains(MediaControl.play));
    expect(
        handler.playbackState.value.controls, isNot(contains(MediaControl.pause)));

    unawaited(handler.play());
    await pumpEventQueue();
    // Playing: a pause control is offered instead.
    expect(handler.playbackState.value.controls, contains(MediaControl.pause));
    expect(
        handler.playbackState.value.controls, isNot(contains(MediaControl.play)));

    await handler.stop();
  });

  test('loadChapter publishes the book as the media item', () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(
        bookId: 'b1', title: 'The Odyssey', author: 'Homer', sentences: ['a']);
    expect(handler.mediaItem.value?.title, 'The Odyssey');
    expect(handler.mediaItem.value?.artist, 'Homer');
  });
}
