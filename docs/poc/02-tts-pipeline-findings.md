# 02 · TTS Pipeline Findings

*Narrarr POC. Last updated 2026-06-24.*

This is the **most valuable output of the POC**: what it actually takes to make on-device neural TTS play *smoothly* in sync with highlighted text. Each finding below cost real debugging; the real app should treat these as known constraints, not re-learn them.

All numbers were measured on an **x86 Android emulator** (gphone64, API 32) — see [§6](#6-the-emulator-caveat-critical) before trusting any timing.

---

## 1. The synthesis → playback pipeline

System TTS (`flutter_tts`) is a **continuous engine** — you hand it a sentence and it speaks, back-to-back, with no per-utterance startup cost. Neural TTS is fundamentally different and that difference is the source of *every* hard problem below:

**Neural is clip-based.** For each sentence you must: synthesize PCM (a blocking, CPU-bound FFI call) → encode a WAV → hand the file to an audio player → play it. Each of those steps has latency, and none of it overlaps for free.

The POC's neural pipeline (in [`neural_tts_engine.dart`](../../poc/lib/tts/neural_tts_engine.dart) + [`tts_synth_isolate.dart`](../../poc/lib/tts/tts_synth_isolate.dart)):

```
sentence text
  → [background isolate] sherpa-onnx OfflineTts.generate() → Float32 PCM
  → trim edge silence → encode 16-bit WAV → write temp file
  → [main isolate] AudioPlayer.setSource(file) → resume() → onPlayerComplete
```

Synthesis runs on a **persistent background isolate**. This is mandatory, not an optimization: `OfflineTts.generate()` blocks, so on the UI isolate it freezes scrolling and buttons. Note that **native pointers can't cross a `SendPort`**, so the `OfflineTts` object is built *inside* the isolate (loading the model once); only text goes in and PCM comes back.

## 2. Sentence sync: completion-driven, not timed

The sync mechanism is deliberately simple and it's the one thing that worked first try and never broke:

> **`speak(sentence)` resolves only when that sentence's audio has actually finished.** The UI play-loop highlights sentence *i*, awaits `speak(i)`, then advances to *i+1*.

- System: `flutter_tts` with `awaitSpeakCompletion(true)`.
- Neural: await the clip's `onPlayerComplete`.

Because advancement is **gated on real completion**, the highlight can't drift from the audio — there are no timers to fall out of step. It's engine-agnostic, which is why the same loop drives both voices and why **tap-to-seek** is just "start the loop at index N." Re-entrancy (tap while playing) is guarded with a monotonic `_playToken`.

This is a different approach from the research roadmap's planned `sentence → (startMs, endMs)` duration table ([Phase 3](../research/06-mvp-scope-and-roadmap.md)). Completion-driven is simpler and drift-free, but position-driven (the table) is more flexible for pagination, scrubbing, and future word-level highlighting — see [03](03-recommendations.md).

---

## The four stacked playback problems

Making neural playback feel as smooth as the system voice required solving these **in sequence** — each fix revealed the next problem.

## 3. Problem 1 — Long sentences get "fast-forwarded"

**Symptom:** one long sentence ("Nor can I deem… fills the cups." — 278 chars) played rushed/garbled, then the next line was normal.

**Root cause:** sherpa-onnx hands the whole sentence to Piper as **one utterance** (it only splits on `.!?`, treating commas and verse newlines as whitespace). Piper's VITS **stochastic duration predictor** is trained on sentence-length inputs; on an abnormally long one it **under-predicts durations and compresses the speech**.

**The data made it unambiguous** — every normal sentence synthesized at ~20 chars/sec; the long one ran at 37:

| sentence | chars | audio | pace |
|---|---|---|---|
| everything | ≤122 | — | ~20 c/s ✅ |
| "Nor can I deem…" (before) | 278 | 7.4 s | 37 c/s ❌ rushed |
| "Nor can I deem…" (after) | 278 | 12.9 s | 21.6 c/s ✅ |

**Fix:** **chunk** any sentence over ~120 chars into clause-sized pieces (split at `, ; :` / em-dash, fall back to word boundaries), synthesize each separately, so every synthesis stays in-distribution. (`_chunkForSynthesis` / `_splitByWords`.) The 120-char threshold is empirical — 122 chars paced normally, 278 did not.

## 4. Problem 2 — 2–3 s gap *between* sentences

**Symptom:** after fixing #1, neural had a 2–3 s pause between every sentence (system was ~instant).

**Root cause:** synth-then-play ran **serially** — nothing was being synthesized while a clip played.

**Fix:** **look-ahead pre-synthesis.** While sentence *i* plays, the UI loop tells the engine to synthesize *i+1 … i+n* on the background isolate (cached by text). By the time *i* finishes, *i+1*'s PCM is ready. Measured `synth-wait` dropped to **~0 ms** across an entire chapter.

## 5. Problem 3 — ~250 ms startup gap on *every* clip

**Symptom:** even with synthesis ready (`synth-wait ≈ 0`), there was a uniform ~250 ms gap between clips. (This is the subtle one — the gap was *after* synthesis, so it hid from a synth-time probe. Measuring **actual audio-start** via player state events was what exposed it.)

**Root cause:** per-clip playback startup = WAV file write (~75–225 ms) + `audioplayers` `play()` preparing a MediaPlayer for the new file (~60–120 ms). The look-ahead pre-*synthesized* but didn't pre-*write* or pre-*load the player*.

**Two things that did NOT work** (documented so we don't retry them):
- `setReleaseMode(ReleaseMode.stop)` to reuse one player → **worse** (play-start ballooned to ~300–560 ms).
- Moving only the WAV-write into the look-ahead → no net gain (the cost reappeared as file-read latency at play time, from disk I/O contention).

**Fix:** a **two-player ping-pong.** While player A plays the current clip, the next clip's source is `setSource`'d (prepared) on player B in the background; when A finishes, B just `resume()`s — instant. Measured gap dropped to **~2–19 ms**. (`_players[2]`, `_armPlayer`, `preloadNext`.)

## 6. Problem 4 — ~9.5 s stall after a *long* clip

**Symptom:** after switching to a slower voice (amy), a ~5–10 s dead pause appeared specifically after long lines.

**Root cause (measured):** playback position advanced normally to the end of the clip, but **`onPlayerComplete` fired ~10 s late** — only on **long clips**. Correlating overshoot (played-wallclock − audio-length) against clip length:

| clip audio length | overshoot |
|---|---|
| ≤ 8.9 s | 0.5–1.1 s (normal) |
| 15.8 s | **9.97 s** (the stall) |

So there's an emulator audio-layer threshold (~10–12 s) past which end-of-playback is badly delayed. The voice change mattered only because amy's slower pacing stretched "Nor can I deem…" from 12.9 s to 15.8 s, pushing it over.

**Fix:** **chunk-streaming.** A long sentence already synthesizes as 2–3 chunks; instead of concatenating them into one long clip, **play each chunk as its own short clip** (each ≤ ~7 s, under the threshold), back-to-back. The 2-player preload still makes *sentence→sentence* hand-offs gapless; only a long verse line gets a tiny (~0.2 s) pause between its own chunks (which lands at clause/line breaks, so it reads naturally). Measured gap after the long line: **9.5 s → 1 ms**, no clip stalls anywhere.

> ⚠️ This stall is the finding most likely to be **emulator-specific**. It must be re-checked on a real device — if it doesn't reproduce, the chunk-streaming split could be relaxed. Either way, chunk-streaming is also good for tap latency (next point), so it's worth keeping.

---

## 7. Tap-to-seek latency (inherent, not a bug)

Tapping a line that hasn't been pre-synthesized must synthesize it **on demand** before any sound. On the emulator that's ~1 s for a short line and **~3 s for a long (3-chunk) line**. Mitigations applied: pre-synthesize the opening lines when the neural engine is selected, and run a **warm-up synth** on init (the first `generate()` is a cold-start, markedly slower). The residual latency is inherent to on-demand synthesis and is **dominated by emulator slowness** — far less on a real device. Chunk-streaming also helps here (first chunk can start before the rest finishes).

## 8. Voice findings

- **Piper tiers (`low`/`medium`/`high`) are about sample rate + quality, not necessarily speed.** `en_US-amy-low` and `en_US-ryan-medium` have the **same-size ONNX model (~63 MB)** → the same synthesis compute. `amy-low` is *not* meaningfully faster; it's 16 kHz (duller) and, as packaged, slower-paced. **`ryan-medium` was the best quality/speed** of those tried; `amy-low` and `ryan-high` were worse fits (flat, or too slow on the emulator).
- The POC **currently ships `amy-low`** (a deliberate user choice during the spike); reverting to `ryan-medium` is a one-line change (`_voice` / `_asset` / `_modelFile`) plus swapping the bundled `.tar`.
- **Model packaging:** the voice is bundled as an **uncompressed `.tar`** asset (~80 MB) and extracted to app-support storage on first run. For the real app, prefer **download-on-demand** over bundling (see [03](03-recommendations.md)).

## 9. EPUB / verse text extraction

The test book is Cowper's blank-verse *Odyssey* (Standard Ebooks), which stresses text handling:
- Verse lines are `<span>`s separated by `<br/>`; `</span>` adds no whitespace, so naïve `.text` glues words together. Handle `<br/>` → space and block-closers (`</p>` etc.) → newline **before** parsing.
- Drop the chapter `<header>` (heading + bridgehead summary) so narration starts at the body.
- Sentences are split on `(?<=[.!?])\s+`. A "sentence" can legitimately contain internal newlines (verse line breaks that aren't sentence ends) — downstream code must treat `\n` as whitespace.

---

## Quick reference — fixes to carry forward

| Problem | Fix | File |
|---|---|---|
| Long sentence rushed | Chunk to ≤120 chars, clause-aware | `_chunkForSynthesis` |
| 2–3 s inter-sentence gap | Look-ahead pre-synthesis on a persistent isolate | `precache` + `tts_synth_isolate.dart` |
| ~250 ms per-clip startup | 2-player ping-pong preload | `_armPlayer` / `preloadNext` |
| ~10 s stall on long clips | Chunk-streaming (play long lines as short clips) | `speak` loop over `clips` |
| Tap latency | Warm-up synth + precache opening lines | `init` / `_setMode` |
| Drift-free sync | Completion-driven advance, `_playToken` guard | `main.dart` play-loop |

*Next: [03 · Recommendations for the App](03-recommendations.md) · Back to [index](README.md).*
