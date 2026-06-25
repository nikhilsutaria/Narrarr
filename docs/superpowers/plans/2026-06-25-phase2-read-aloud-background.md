# Phase 2 — Offline Read-Aloud with Background Playback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Press play on any chapter → smooth, gapless offline narration that keeps playing with the screen locked, shows lock-screen/Now-Playing controls, and survives a phone call — across the whole book, with pause/resume and skip-sentence.

**Architecture:** Phase 1 already ported the POC narration pipeline (`TtsSynthIsolate` → `NeuralNarrator` (completion-driven, `audioplayers`, 2-player gapless) → `NarrationController`), foreground-only, single-chapter. Phase 2 wraps that pipeline in `audio_service` for a background foreground-service + `MediaSession` (lock-screen controls, media buttons, audio focus, interruptions), decides the player (gate Task 1: keep proven `audioplayers` engine vs. migrate to `just_audio`), extends control from stop-only to pause/resume + skip-sentence, segments the **whole book** (not one chapter) skipping non-narratable content, and introduces a voice-manager seam for download-on-demand. **The existing completion-driven highlight stays as-is** — position-driven sync is Phase 3; do not rip it out, just don't regress it.

**Tech Stack:** Flutter/Dart, `audio_service` (background + MediaSession), `just_audio` (candidate player, gated), existing `audioplayers` (proven fallback), `sherpa_onnx` + Piper (synthesis, unchanged), `flutter_readium` (reader, unchanged), `drift` (unchanged).

## Global Constraints

- **Android-first; keep the codebase iOS-clean** — no Android-only APIs leaking into shared Dart; iOS `Info.plist`/`AppDelegate` audio-background work is deferred but don't make it harder.
- **Toolchain pins (do not change):** AGP 8.9.1, Kotlin 2.3.21, `desugar_jdk_libs` 2.1.5, NDK 27.0.12077973, compileSdk 36, minSdk 24, JDK 21, `FlutterFragmentActivity`.
- **POC techniques are non-negotiable** (from MVP spec §3): long-sentence chunking ≤120 chars, look-ahead pre-synthesis on the persistent isolate, chunk-streaming long sentences, warm-up synth on init, **all heavy work off the UI isolate** (synth + WAV encoding in the background isolate; only file paths cross the `SendPort`).
- **No highlight changes** — Phase 2 is "read-aloud (no highlight)" per spec §7; the Phase-1 completion-driven highlight remains wired and must not regress. Position-driven sync is Phase 3.
- **No speed-control UI** (fast-follow). The synth isolate already accepts `speed`; leave the seam, don't wire UI.
- **Voice:** keep `vits-piper-en_US-amy-low` bundled as the offline default. Do **not** bundle a larger voice (that's the bloat download-on-demand exists to avoid, and it worsened the Phase-1 cold-start ANR). Build the download-on-demand *foundation* only; full download UX is Phase 4.
- **Every timing/perf claim is emulator-grade until confirmed on a real mid-range Android.** Defer device checks to the end (manual-checks doc), consistent with Phase 1.
- **Each task: `flutter analyze` clean + `flutter test` green before commit.**

---

### Task 1: Playback gate — RESOLVED (keep `audioplayers`, add `audio_service`) ✅

**Resolved 2026-06-25 (user-approved):** keep the proven `audioplayers` 2-player gapless engine; add `audio_service` (player-agnostic) for background + lock-screen. **No `just_audio` spike/migration.** Full reasoning in [docs/poc/05-playback-gate-findings.md](../../poc/05-playback-gate-findings.md). Done: `audio_service: ^0.18.18` added (pulls in `audio_session`, `rxdart`, `wakelock_plus`); resolves cleanly. The original spike steps below are retained struck-through for the record but were not executed.

**Files:**
- Create: `lib/narration/spike/just_audio_gapless_spike.dart` (throwaway harness, deleted at task end)
- Create: `docs/poc/05-playback-gate-findings.md`
- Modify: `pubspec.yaml` (add `just_audio`, `audio_service`)

**Interfaces:**
- Consumes: existing `TtsSynthIsolate.synth()` → `(Float32List, int)`, `NeuralNarrator._wavFromFloat`/`_chunkForSynthesis` logic (copy into the spike, don't refactor yet).
- Produces: a **locked decision** (`just_audio` OR `audioplayers`) recorded in the findings doc, consumed by Tasks 2–4.

- [ ] **Step 1: Add dependencies**

In `pubspec.yaml` under `dependencies:` add (resolve exact compatible versions with `flutter pub add`, do not hand-pin blindly):

```yaml
  just_audio: ^0.9.46
  audio_service: ^0.18.18
```

Run: `flutter pub get`
Expected: resolves with no version conflict against `flutter_readium`/`sherpa_onnx`. If `just_audio` conflicts, note it in findings — a conflict is itself a signal toward the `audioplayers` path.

- [ ] **Step 2: Build the minimal gapless harness**

A bare screen (wired temporarily from `main.dart` behind a debug flag, or run via a standalone widget test driver) that: inits the synth isolate against the bundled amy voice (reuse `NeuralNarrator._ensureModelExtracted` + `init` logic), synthesizes ~6 consecutive sentences from the Odyssey sample into WAV temp files, enqueues them on a `just_audio` `ConcatenatingAudioSource` (start playback after the first 1–2 are ready, append the rest as they synthesize), and plays through.

```dart
// just_audio_gapless_spike.dart — THROWAWAY. Goal: measure inter-clip gap and
// whether append-while-playing keeps a growing queue gapless.
final player = AudioPlayer();
final playlist = ConcatenatingAudioSource(children: []);
await player.setAudioSource(playlist);
// synth sentence -> write WAV -> playlist.add(AudioSource.file(path))
// log player.positionStream / processingStateStream around clip boundaries
```

- [ ] **Step 3: Measure and decide**

Run on the emulator (and a real device if available). Capture: (a) audible gap between clips, (b) gap between sentences when appending mid-playback, (c) whether long sentences (chunk-streamed) stall, (d) startup latency to first audio. Compare against the known-good `audioplayers` ping-pong behavior.

Decision rule:
- `just_audio` gapless **and** append-while-playing works **and** no long-clip stall → **migrate to `just_audio`** (cleaner `audio_service` integration, native gapless).
- Any of those fail, or the version conflict in Step 1 → **keep `audioplayers`** (proven), wrap it in `audio_service` in Task 2. Keep `just_audio` dep only if used; otherwise remove it.

- [ ] **Step 4: Record the decision**

Write `docs/poc/05-playback-gate-findings.md`: the measurements, the chosen player, and the concrete reason. This is the single source of truth Tasks 2–4 read. Mirror the format of `docs/poc/04-reader-spike-findings.md`.

- [ ] **Step 5: Delete the harness, keep deps**

Delete `lib/narration/spike/`. Remove the debug wiring from `main.dart`. Keep whichever audio deps the decision requires.

Run: `flutter analyze lib && flutter test`
Expected: clean; existing 7 tests still pass.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock docs/poc/05-playback-gate-findings.md lib/main.dart
git commit -m "Phase 2 Task 1: playback gate — lock player choice for background audio"
```

---

### Task 2: `audio_service` background scaffold — foreground service + lock-screen MediaSession

**Why:** Retires MVP challenges #3 (background synthesis throttling) and #9 (background playback & audio focus). `audio_service` gives a foreground service + `MediaSession`/Now-Playing notification with transport controls, independent of which player Task 1 chose.

**Files:**
- Create: `lib/narration/narration_audio_handler.dart` (`NarrationAudioHandler extends BaseAudioHandler`)
- Modify: `lib/main.dart` (init `AudioService` before `runApp`)
- Modify: `android/app/src/main/AndroidManifest.xml` (service + receiver + permissions)
- Modify: `lib/reader/reader_screen.dart` (route play/stop through the handler instead of calling the controller directly)
- Test: `test/narration_audio_handler_test.dart`

**Interfaces:**
- Consumes: `NarrationController` (Phase 1) — `play({from})`, `stop()`, `isPlaying`, `index`, `sentenceCount`. The player chosen in Task 1.
- Produces: `NarrationAudioHandler` with `play()`, `pause()`, `stop()`, `skipToNext()`, `skipToPrevious()` (the `BaseAudioHandler` overrides), and a broadcast `playbackState`. Consumed by Tasks 3–4 and the reader UI.

- [ ] **Step 1: Android manifest — declare the service, receiver, and permissions**

In `android/app/src/main/AndroidManifest.xml`, add inside `<manifest>` (above `<application>`):

```xml
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
```

Inside `<application>`, add:

```xml
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
```

- [ ] **Step 2: Write the handler (skeleton + a unit-testable state mapping)**

Create `lib/narration/narration_audio_handler.dart`. The handler owns a `NarrationController` and translates its state into `audio_service`'s `PlaybackState`. Keep the controller injectable so tests can pass a fake.

```dart
import 'package:audio_service/audio_service.dart';
import '../sync/narration_controller.dart';

/// Bridges the sentence-based [NarrationController] to audio_service so playback
/// runs in a foreground service with lock-screen / media-button controls.
class NarrationAudioHandler extends BaseAudioHandler {
  NarrationAudioHandler(this._controller) {
    _controller.addListener(_broadcast);
  }

  final NarrationController _controller;

  @override
  Future<void> play() async {
    _broadcast();
    await _controller.play();
  }

  @override
  Future<void> pause() async => _controller.pauseNarration();

  @override
  Future<void> stop() async {
    await _controller.stop();
    _broadcast();
  }

  @override
  Future<void> skipToNext() => _controller.skipSentence(1);

  @override
  Future<void> skipToPrevious() => _controller.skipSentence(-1);

  void _broadcast() {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (_controller.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      processingState: AudioProcessingState.ready,
      playing: _controller.isPlaying,
    ));
  }

  void disposeHandler() => _controller.removeListener(_broadcast);
}
```

(Note: `pauseNarration` and `skipSentence` are added to `NarrationController` in Task 3; this task may stub them as `=> stop()` / no-op to compile, then Task 3 fills them in. Mark with a `// TODO(Task 3)` only if needed to compile — prefer doing Task 3's controller additions first if convenient.)

- [ ] **Step 3: Write the failing test for state mapping**

```dart
// test/narration_audio_handler_test.dart
import 'package:flutter_test/flutter_test.dart';
// Build a fake TtsEngine (no-op speak/init) + real NarrationController.
// Assert: when controller.isPlaying flips, handler.playbackState.value.playing
// matches, and the controls list swaps play<->pause.
```

Run: `flutter test test/narration_audio_handler_test.dart`
Expected: FAIL (handler/controller members not present yet).

- [ ] **Step 4: Make it pass** — implement the handler + a `FakeTtsEngine` test double; ensure `_broadcast` produces the asserted state.

Run: `flutter test test/narration_audio_handler_test.dart`
Expected: PASS.

- [ ] **Step 5: Init `AudioService` in `main.dart`**

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NarrarrApp());
}
```

The handler is created per-reader-session (a book-scoped session), so call `AudioService.init` lazily when the reader first starts narration (not at app launch — avoids adding to the cold-start path flagged in Phase 1). Wire `AudioService.init(builder: () => NarrationAudioHandler(controller), config: const AudioServiceConfig(androidNotificationChannelId: 'dev.narrarr.audio', androidNotificationChannelName: 'Narration', androidNotificationOngoing: true))` from the reader's first `_togglePlay`.

- [ ] **Step 6: Route the reader's play/stop through the handler**

In `lib/reader/reader_screen.dart`, replace direct `_narration.play()`/`_narration.stop()` calls in `_togglePlay` with the handler's `play()`/`stop()`. Keep the `setMediaItem` populated with the book title/author so the notification shows them.

- [ ] **Step 7: Build & verify it launches and shows a notification**

Run: `flutter analyze lib && flutter build apk --debug`
Expected: builds. (On-device notification check is deferred to manual-checks.)

- [ ] **Step 8: Commit**

```bash
git add lib/narration/narration_audio_handler.dart lib/main.dart android/app/src/main/AndroidManifest.xml lib/reader/reader_screen.dart test/narration_audio_handler_test.dart
git commit -m "Phase 2 Task 2: audio_service background scaffold + lock-screen controls"
```

---

### Task 3: Pause/resume + skip-sentence

**Why:** Phase 1's engine is stop-only. v1 scope requires play/pause and skip-sentence (spec §6). These map to both in-app controls and the media notification actions from Task 2.

**Files:**
- Modify: `lib/sync/narration_controller.dart` (add `pauseNarration`, `resumeNarration`, `skipSentence`)
- Modify: `lib/narration/tts_engine.dart` (add `pause()`/`resume()` to the interface)
- Modify: `lib/narration/neural_narrator.dart` (implement pause/resume on the active player)
- Modify: `lib/reader/reader_screen.dart` (mini-player bar: prev / play-pause / next)
- Test: `test/narration_controller_test.dart`

**Interfaces:**
- Consumes: `NarrationController` from Phase 1, `NarrationAudioHandler` from Task 2.
- Produces:
  - `TtsEngine.pause()`/`resume()` (Future<void>).
  - `NarrationController.pauseNarration()`, `resumeNarration()`, `skipSentence(int delta)` and a `bool get isPaused`.

- [ ] **Step 1: Extend the `TtsEngine` interface**

Add to `lib/narration/tts_engine.dart`:

```dart
  /// Pause the currently-playing utterance, keeping position. No-op if idle.
  Future<void> pause();

  /// Resume a paused utterance.
  Future<void> resume();
```

- [ ] **Step 2: Failing controller test**

```dart
// test/narration_controller_test.dart
test('skipSentence advances index and re-plays from there', () async {
  final c = NarrationController(engine: FakeTtsEngine());
  c.setSentences(['a', 'b', 'c']);
  await c.play();              // settles at end with fake instant speak
  c.skipSentence(-1);          // from end → back one
  expect(c.index, /* expected index */);
});
test('pause then resume keeps the same index', () async { ... });
```

Run: `flutter test test/narration_controller_test.dart`
Expected: FAIL (members missing).

- [ ] **Step 3: Implement pause/resume in `NeuralNarrator`**

Use the active player's native pause/resume (`just_audio` `player.pause()/play()` or `audioplayers` `pause()/resume()` per Task 1's decision). Track a `_paused` flag so the `speak` loop blocks on a resume completer rather than completing.

- [ ] **Step 4: Implement controller methods**

```dart
  bool _paused = false;
  bool get isPaused => _paused;

  Future<void> pauseNarration() async {
    if (!_playing) return;
    _paused = true;
    await engine.pause();
    notifyListeners();
  }

  Future<void> resumeNarration() async {
    if (!_paused) return;
    _paused = false;
    await engine.resume();
    notifyListeners();
  }

  /// Jump [delta] sentences from the current index and continue playing.
  Future<void> skipSentence(int delta) async {
    final target = (_index + delta).clamp(0, _sentences.length - 1);
    await play(from: target); // play() bumps _token, superseding the current loop
  }
```

- [ ] **Step 5: Run tests**

Run: `flutter test`
Expected: PASS (existing + new).

- [ ] **Step 6: Reader mini-player bar**

In `lib/reader/reader_screen.dart`, replace the single Listen FAB with a bottom mini-player (prev-sentence, play/pause, next-sentence) when narration is active; keep the Listen FAB as the entry point when idle. Each control routes through the Task-2 handler so the notification and UI stay in sync. Touch targets ≥48dp, labeled for TalkBack (ui-ux-pro-max: `touch-target-size`, `aria-labels`, `primary-action`).

- [ ] **Step 7: Build & verify**

Run: `flutter analyze lib && flutter build apk --debug`
Expected: builds.

- [ ] **Step 8: Commit**

```bash
git add lib/sync/narration_controller.dart lib/narration/tts_engine.dart lib/narration/neural_narrator.dart lib/reader/reader_screen.dart test/narration_controller_test.dart
git commit -m "Phase 2 Task 3: pause/resume + skip-sentence with in-app + notification controls"
```

---

### Task 4: Audio focus & interruption handling

**Why:** Completes #9. The "pocket it and listen" promise breaks if a phone call, another app's audio, a headset unplug, or a Bluetooth disconnect leaves narration playing over the top or dead after the interruption.

**Files:**
- Modify: `lib/narration/narration_audio_handler.dart` (subscribe to `AudioSession` events)
- Modify: `pubspec.yaml` (`audio_session` is a transitive dep of both players; add explicitly)
- Test: `test/audio_interruption_test.dart` (logic-level: a fake session event → handler pauses/resumes)

**Interfaces:**
- Consumes: `audio_session` `AudioSession.instance`, the Task-2 handler.
- Produces: interruption-aware pause/duck/resume behavior; no new public API.

- [ ] **Step 1: Configure the audio session**

In the handler's init, configure for speech playback and subscribe:

```dart
final session = await AudioSession.instance;
await session.configure(const AudioSessionConfiguration.speech());
session.interruptionEventStream.listen((event) {
  if (event.begin) {
    if (event.type == AudioInterruptionType.duck) { /* lower volume */ }
    else { _wasPlayingBeforeInterruption = _controller.isPlaying; pause(); }
  } else {
    if (event.type == AudioInterruptionType.duck) { /* restore volume */ }
    else if (_wasPlayingBeforeInterruption) { play(); }
  }
});
session.becomingNoisyEventStream.listen((_) => pause()); // headset unplugged
```

- [ ] **Step 2: Failing logic test**

Drive the handler with a fake interruption (begin → pause, end → resume only if it was playing). Assert state transitions. (Mock the session boundary; don't require a real audio device.)

Run: `flutter test test/audio_interruption_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement** the `_wasPlayingBeforeInterruption` gate and wire the streams.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 4: Build & verify**

Run: `flutter analyze lib && flutter build apk --debug`
Expected: builds.

- [ ] **Step 5: Commit**

```bash
git add lib/narration/narration_audio_handler.dart pubspec.yaml pubspec.lock test/audio_interruption_test.dart
git commit -m "Phase 2 Task 4: audio focus + interruption handling (calls, ducking, headset)"
```

---

### Task 5: Whole-book segmentation (skip non-narratable content)

**Why:** Completes #4 and #6. Phase 1's `resolveChapter` picks **one** chapter and segments only it. v1 narrates whole books across the multi-file spine and must skip footnotes, captions, nav/TOC, page numbers, headers, and table content rather than read them aloud. Abbreviation-aware splitting prevents "Dr." / "Mr." / "vol. 2" from ending a sentence.

**Files:**
- Create: `lib/reader/segmenter.dart` (`Segmenter` — HTML → narratable sentences, skip rules + abbreviation guard)
- Modify: `lib/reader/book_text.dart` (route through `Segmenter`; add whole-spine traversal helper)
- Modify: `lib/reader/reader_screen.dart` (advance to the next spine item when the current chapter's sentences are exhausted)
- Test: `test/segmenter_test.dart`

**Interfaces:**
- Consumes: `flutter_readium` reading-order / spine, existing `sentencesFromHtml` (verse-aware) as a starting point.
- Produces:
  - `class Segmenter { List<String> sentencesFromHtml(String html); }` — abbreviation-aware, skips non-narratable nodes.
  - `book_text.dart`: `Future<List<ResolvedChapter>> resolveSpine(bytes)` returning ordered chapters.

- [ ] **Step 1: Failing segmenter tests (table-driven, real edge cases)**

```dart
// test/segmenter_test.dart
final seg = Segmenter();
test('does not split on common abbreviations', () {
  expect(seg.sentencesFromHtml('<p>Dr. Smith met Mr. Jones. They talked.</p>'),
      ['Dr. Smith met Mr. Jones.', 'They talked.']);
});
test('skips footnote and figure-caption nodes', () {
  expect(seg.sentencesFromHtml(
      '<p>Real text.</p><aside epub:type="footnote">Note.</aside>'
      '<figcaption>Caption.</figcaption>'),
      ['Real text.']);
});
test('skips nav/toc and bare page-number nodes', () { ... });
test('joins verse lines (carried from Phase 1)', () { ... });
```

Run: `flutter test test/segmenter_test.dart`
Expected: FAIL.

- [ ] **Step 2: Implement `Segmenter`**

Skip elements by tag/role: `<header>`, `<nav>`, `epub:type` in {`footnote`, `endnote`, `noteref`, `pagebreak`, `toc`}, `<figcaption>`, `<table>` (read a placeholder or skip per spec — skip for v1), nodes that are only digits/roman numerals (page numbers). Use an abbreviation set (`Dr`, `Mr`, `Mrs`, `Ms`, `St`, `vs`, `etc`, `vol`, `no`, `pp`, `Jr`, `Sr`, initials `A.`) to suppress sentence breaks. Reuse the verse-join logic from `sentencesFromHtml`.

Run: `flutter test test/segmenter_test.dart`
Expected: PASS.

- [ ] **Step 3: Whole-spine traversal**

Add `resolveSpine` to `book_text.dart` that walks the reading order and segments each content document, preserving order and the per-chapter `hrefHint`. Keep memory bounded — segment lazily per chapter, not the whole book into one giant list (large-book memory, #6).

- [ ] **Step 4: Cross-chapter advance in the reader**

When `NarrationController` exhausts the current chapter's sentences, load and segment the next spine item and continue. (Highlight + page navigation across spine items reuses the existing `goToLocator`; do not build position-driven sync — Phase 3.)

- [ ] **Step 5: Run all tests + build**

Run: `flutter test && flutter analyze lib && flutter build apk --debug`
Expected: PASS / clean / builds.

- [ ] **Step 6: Commit**

```bash
git add lib/reader/segmenter.dart lib/reader/book_text.dart lib/reader/reader_screen.dart test/segmenter_test.dart
git commit -m "Phase 2 Task 5: whole-book segmentation, skip non-narratable content, abbrev-aware"
```

---

### Task 6: Voice-manager seam (download-on-demand foundation)

**Why:** Begins #11. Phase 1 bundles the amy voice as a tar asset and extracts it inline in `NeuralNarrator`. Phase 4 needs download/verify/evict; this task extracts the seam now (without the bloat of bundling a bigger voice) so Phase 4 is an extension, not a refactor.

**Files:**
- Create: `lib/narration/voice_manager.dart` (`VoiceManager` — resolve/ensure a voice's extracted model dir)
- Modify: `lib/narration/neural_narrator.dart` (take the model dir from `VoiceManager` instead of extracting inline)
- Test: `test/voice_manager_test.dart`

**Interfaces:**
- Consumes: existing `VoiceConfig`, the bundled tar asset, `archive` `TarDecoder`.
- Produces:
  - `abstract class VoiceManager { Future<String> ensureAvailable(VoiceConfig v); List<VoiceConfig> get installed; }`
  - `class BundledVoiceManager implements VoiceManager` (extracts the bundled tar — the Phase-1 logic, moved). A `DownloadingVoiceManager` is explicitly out of scope (Phase 4) but the interface accommodates it.

- [ ] **Step 1: Failing test**

```dart
// test/voice_manager_test.dart
test('ensureAvailable returns a dir containing the model file', () async {
  // Use a temp dir + a fixture tar; assert the .onnx is present after.
});
test('second call is idempotent (no re-extract)', () async { ... });
```

Run: `flutter test test/voice_manager_test.dart`
Expected: FAIL.

- [ ] **Step 2: Implement `BundledVoiceManager`** by moving `_ensureModelExtracted` out of `NeuralNarrator` into the manager (parameterized by a base dir for testability).

- [ ] **Step 3: Wire `NeuralNarrator` to take a `VoiceManager`** (default `BundledVoiceManager()`); `init` calls `manager.ensureAvailable(voice)`.

Run: `flutter test`
Expected: PASS.

- [ ] **Step 4: Build & verify**

Run: `flutter analyze lib && flutter build apk --debug`
Expected: builds; narration still works (the extraction path is unchanged, just relocated).

- [ ] **Step 5: Commit**

```bash
git add lib/narration/voice_manager.dart lib/narration/neural_narrator.dart test/voice_manager_test.dart
git commit -m "Phase 2 Task 6: voice-manager seam for download-on-demand foundation"
```

---

## Phase 2 Definition of Done

- [ ] Press play on a chapter → gapless narration (player per Task-1 gate).
- [ ] Narration continues with the **screen locked**; lock-screen / Now-Playing shows title + transport controls that work.
- [ ] **Pause/resume** and **skip-sentence** work from both the in-app bar and the notification.
- [ ] A phone call / other audio **pauses** narration and it **resumes** afterward; headset unplug pauses.
- [ ] Narration crosses **chapter boundaries** and reads the **whole book**, skipping footnotes/captions/nav/page-numbers; no mid-name false sentence breaks.
- [ ] Voice loading routes through `VoiceManager`; amy stays the bundled offline default.
- [ ] `flutter analyze` clean; all unit tests green; debug APK builds.
- [ ] Existing Phase-1 completion-driven highlight still works (not regressed).

## Manual checks (deferred to end, per established pattern)

Real-device only — added to a `docs/superpowers/plans/phase2-manual-checks.md` at phase end: lock-screen controls, phone-call interruption + resume, Bluetooth connect/disconnect, headset unplug, background CPU/Doze does not starve look-ahead during a long locked session, whole-book traversal on a messy real EPUB, Piper RTF/thermals over a long session (carryover from spike findings), airplane-mode offline narration.
```
