import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/narration_audio_handler.dart';
import 'package:narrarr/narration/voice_settings.dart';
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

  test('rewind / fast-forward skip by the configured interval (#45)', () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller)
      ..skipInterval = const Duration(seconds: 12);
    // 100-char sentences last ~6 s each at the default rate.
    handler.loadChapter(
        bookId: 'b1',
        title: 'Book',
        sentences: [for (var i = 0; i < 10; i++) '$i'.padRight(100, '.')],
        startSentence: 5);

    await handler.fastForward();
    expect(controller.index, 7);
    await handler.rewind();
    expect(controller.index, 5);

    final state = handler.playbackState.value;
    expect(state.controls, [
      MediaControl.rewind,
      MediaControl.play,
      MediaControl.fastForward,
      MediaControl.stop,
    ]);
    expect(state.androidCompactActionIndices, [0, 1, 2]);
    expect(state.systemActions,
        containsAll([MediaAction.rewind, MediaAction.fastForward]));
  });

  test('handler.stop ends the session and turns off the sleep timer (#44)',
      () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b', title: 'B', sentences: ['a', 'b']);
    unawaited(handler.play());
    await pumpEventQueue();
    handler.sleepTimer.start(const Duration(minutes: 10));
    await handler.stop();
    expect(handler.sleepTimer.isActive, isFalse);
    handler.sleepTimer.dispose();
  });

  test('sleep-timer fade and audio ducking combine instead of overriding',
      () async {
    final fake = FakeTtsEngine();
    final handler = NarrationAudioHandler(NarrationController(engine: fake));
    await handler.onInterruption(
        AudioInterruptionEvent(true, AudioInterruptionType.duck));
    expect(fake.volume, closeTo(0.3, 1e-9));
    handler.sleepTimer.start(const Duration(minutes: 1));
    handler.sleepTimer.cancel(); // no fade yet: volume untouched
    await handler.onInterruption(
        AudioInterruptionEvent(false, AudioInterruptionType.duck));
    expect(fake.volume, 1.0);
    handler.sleepTimer.dispose();
  });

  test('loadChapter passes paragraph starts to the controller (#45)', () {
    final controller = NarrationController(engine: FakeTtsEngine());
    NarrationAudioHandler(controller).loadChapter(
        bookId: 'b1',
        title: 'Book',
        sentences: ['a', 'b', 'c'],
        paragraphStarts: const [0, 2]);
    expect(controller.paragraphStarts, [0, 2]);
  });

  VoiceSettingsStore tempStore(String json) {
    final dir = Directory.systemTemp.createTempSync('vs');
    addTearDown(() => dir.deleteSync(recursive: true));
    return VoiceSettingsStore(
        file: File('${dir.path}/voice_settings.json')..writeAsStringSync(json));
  }

  test('applyVoiceSettings applies speed and listening prefs (#45, #34)',
      () async {
    final fake = FakeTtsEngine();
    final controller = NarrationController(engine: fake);
    final handler = NarrationAudioHandler(controller);
    final vs = await handler.applyVoiceSettings(
        store: tempStore('{"speechSpeed": 1.5, "skipSeconds": 15, '
            '"autoRewind": false}'));
    expect(vs.speechSpeed, 1.5);
    expect(fake.speed, 1.5);
    expect(controller.speechSpeed, 1.5);
    expect(handler.skipInterval, const Duration(seconds: 15));
    expect(controller.autoRewind, isFalse);
  });

  test('previewSpeech stops narration, then speaks the normalized text (#47)',
      () async {
    final fake = FakeTtsEngine();
    final controller = NarrationController(engine: fake);
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b', title: 'B', sentences: ['one', 'two']);
    unawaited(handler.play());
    await pumpEventQueue();
    expect(controller.isPlaying, isTrue);

    unawaited(handler.previewSpeech('her-MY-oh-nee costs \$5',
        store: tempStore('{}')));
    // Settings load is real file IO, not just microtasks.
    for (var i = 0; i < 50 && fake.spoken.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(controller.isPlaying, isFalse);
    expect(fake.spoken.last, 'her-MY-oh-nee costs five dollars');
    fake.finishCurrent();
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

  test('seekToSentence plays from the tapped index', () async {
    final controller = NarrationController(engine: FakeTtsEngine());
    final handler = NarrationAudioHandler(controller);
    handler.loadChapter(bookId: 'b1', title: 'Book', sentences: ['a', 'b', 'c']);

    unawaited(handler.seekToSentence(2)); // blocks on the pending speak
    await pumpEventQueue();
    expect(controller.index, 2);

    await controller.stop();
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
