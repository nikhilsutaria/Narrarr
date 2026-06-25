# 01 · What Was Built

*Narrarr POC. Last updated 2026-06-24.*

A single-screen Flutter app in [`/poc`](../../poc/) that demonstrates the core Narrarr loop on Android. It is a **throwaway spike** — deliberately narrow, with diagnostic logging left in.

## Scope

**In:**
- Load a bundled EPUB (*The Odyssey*, Book IX — "The Cyclops"), parse and segment it into sentences.
- Display sentences in a scrolling list; **highlight the current one** and auto-scroll to keep it visible.
- **Read aloud** with a runtime-selectable engine:
  - **System** — the OS voice via `flutter_tts`.
  - **Neural** — fully offline sherpa-onnx + Piper.
- Play / Pause, and **tap any line to start (and sync) from there**.

**Out (intentionally):** file picker / library, persistence, pagination, background/lock-screen playback, settings, iOS run, word-level highlighting, polish. These belong to the real app.

## Repo layout

| File | Role |
|---|---|
| [`lib/main.dart`](../../poc/lib/main.dart) | `ReaderPage` UI: engine toggle, the play-loop that drives `speak`/`preloadNext`/`precache`, tap-to-seek (`_startFrom`), scroll sync, Play/Pause. |
| [`lib/tts/tts_engine.dart`](../../poc/lib/tts/tts_engine.dart) | Abstract `TtsEngine` interface + `TtsMode` enum. **The contract: `speak` completes only when the utterance finishes** (or `stop` interrupts) — this is what makes sync engine-agnostic. |
| [`lib/tts/system_tts_engine.dart`](../../poc/lib/tts/system_tts_engine.dart) | `flutter_tts`, `awaitSpeakCompletion(true)`. `precache`/`preloadNext` are no-ops. |
| [`lib/tts/neural_tts_engine.dart`](../../poc/lib/tts/neural_tts_engine.dart) | The neural pipeline: chunking, look-ahead cache, 2-player preload, chunk-streaming, edge-silence trim, WAV encode. (See [02](02-tts-pipeline-findings.md).) |
| [`lib/tts/tts_synth_isolate.dart`](../../poc/lib/tts/tts_synth_isolate.dart) | Persistent background isolate that owns the `OfflineTts` and serves synthesis requests. |
| [`lib/epub_loader.dart`](../../poc/lib/epub_loader.dart) | EPUB read (`epubx`), HTML→speakable-text (verse-aware), sentence split. |

## Key dependencies

`flutter_tts` · `sherpa_onnx` · `audioplayers` · `epubx` · `html` · `scrollable_positioned_list` · `path_provider` · `path` · `archive`. Android `minSdk 24`, `compileSdk 36`, `ndkVersion 27` (required by `flutter_tts` / sherpa-onnx native libs).

## How to run

```
cd poc
flutter run -d <android-device-or-emulator>
```

- Assets bundled: the test EPUB (`assets/the-odyssey-homer.epub`) and the Piper voice as an uncompressed tar (`assets/vits-piper-en_US-amy-low.tar`). The voice is extracted to app-support storage on first run (~80 MB, one-time).
- The test chapter is hard-coded (`contentFileHint: 'book-9'`, capped at 80 sentences) — chosen because Book IX has expressive dialogue and drama, good for judging voice naturalness.
- Default engine is **System**; tap **Neural** to switch (first switch extracts the model + warms it up, a few seconds).

## How the demo behaves

1. App opens on Book IX text. Tap **Play** (or tap any line) → it reads aloud and the spoken sentence highlights, auto-scrolling to follow.
2. Toggle **System ↔ Neural** to compare voices; sync works identically for both.
3. Tap a different line → playback jumps there and continues. This is also the A/B tool for comparing the two engines on the same line.

## Verification done

- Visual sync confirmed via on-device screenshots (highlight tracks the spoken sentence, view auto-scrolls).
- Neural timing confirmed via in-app logging: `synth-wait ≈ 0`, between-sentence gaps 0–19 ms, no clip stalls, correct clip durations. (Details and the debugging journey in [02](02-tts-pipeline-findings.md).)
- **Audio quality and final smoothness were confirmed by ear by the developer** — the agent that built it cannot hear the emulator, so listening was the human's part of the loop.

*Next: [02 · TTS Pipeline Findings](02-tts-pipeline-findings.md) · Back to [index](README.md).*
