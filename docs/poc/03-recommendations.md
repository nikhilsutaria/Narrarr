# 03 · Recommendations for the App

*Narrarr POC. Last updated 2026-06-24.*

How the POC should shape the real build. The short version: **the core loop and the neural-playback techniques are proven — reuse them — but re-validate the playback layer and the reader choice, which the POC deliberately stubbed.**

## Carry forward (proven in the POC)

- **The `TtsEngine` abstraction** — one interface, `speak` completing on real audio-end, with system and neural implementations behind it. Clean and worth keeping.
- **Completion-driven sentence sync** — drift-free and engine-agnostic. (But see the open question on position-driven sync below.)
- **Long-sentence chunking** (≤~120 chars, clause-aware) — required for Piper to pace long sentences correctly. Non-negotiable.
- **Look-ahead pre-synthesis on a persistent isolate** — the answer to the inter-sentence gap, and the research roadmap's "look-ahead buffering." Keep the isolate (native pointers can't cross `SendPort`).
- **Chunk-streaming long sentences** — play long lines as short clips. Fixes the long-clip stall *and* lowers tap latency.
- **Warm-up synth on init + precache opening lines** — cuts first-line and Play latency.
- **Verse-aware EPUB text normalization** — handle `<br/>`, block-closers, `<header>`, and internal newlines.

## Re-validate / change for the real app

### 1. Playback layer — strongly consider `just_audio` (the research pick)
The POC used `audioplayers` and had to **engineer around** two of its limits: a ~250 ms per-clip startup (solved with a 2-player ping-pong) and a ~10 s completion stall on long clips (solved with chunk-streaming). The research recommended **`just_audio`**, whose `ConcatenatingAudioSource` does **gapless playlist** playback natively. That could **subsume both hacks** — queue sentence clips as playlist items, get gapless transitions for free, and drive highlighting from `currentIndexStream`. **Spike this early**: if `just_audio` plays a queue of clips gaplessly *and* handles long clips without the stall, it's a simpler, sturdier foundation than the POC's hand-rolled playback. Keep chunk-streaming as a fallback either way.

### 2. Reader — use `flutter_readium`, then re-prove sync under it
The POC rendered text in a plain `ListView`. The real app needs a true **reflowable EPUB reader** (pagination, font/theme, persisted position). The research's Phase 0 was specifically *"can `flutter_readium` (v0.1.0) render + highlight under an external neural-TTS pipeline?"* — **the POC did not answer this** (it used a custom reader). That question is still open and is the **#1 remaining stack risk**. Re-run that spike with the POC's proven TTS pipeline behind it; keep the research's named fallbacks (foliate-js WebView, native Readium) ready.

### 3. Sync model — weigh completion-driven vs. position-driven
Completion-driven (POC) is simple and drift-free, but it advances *one clip at a time* and ties highlighting to clip boundaries. The research roadmap's **`sentence → (Locator, startMs, endMs)` table** (driven by measured clip durations + player position) is more flexible for **pagination, scrubbing/seek, background playback, and eventual word-level highlighting**. Recommendation: move to position-driven sync for the real app, but keep the POC's completion signal as the source of truth for clip durations.

### 4. Voices — download-on-demand, default to quality
Bundling an 80 MB voice bloats the app. Use **download-on-demand** (the roadmap's ODR/download-on-run) with storage management. Default to a **quality** voice (`ryan-medium`-class), not the low tier — low tier isn't faster (same model size), just duller. Offer one or two optional downloads, not a big catalog.

### 5. Keep heavy work off the UI isolate
The long-clip investigation pointed at the **UI isolate** as a contention point (synthesis-result transfer + WAV encoding can block it). For the real app, do **synthesis *and* WAV/file encoding entirely in the background isolate**, returning a file path (small) to the UI — never ship large PCM buffers across the `SendPort` to the UI thread.

### 6. Background playback
Not in the POC. The real app needs `audio_service` (or equivalent) for lock-screen / Now-Playing controls and continued playback when backgrounded — design the playback layer with this in mind from the start.

### 7. Drop the diagnostic scaffolding
The POC code has timing/stall logging and a hard-coded test chapter — all throwaway. Don't port it; port the *techniques*.

## ⚠️ Validate on real hardware before trusting anything

Every timing number in these docs is from an **x86 emulator** (~5–10× slower at neural synth; at least one audio quirk). Before committing to the stack, **measure Piper real-time-factor and the long-clip behavior on a real mid-range Android and a real iPhone.** Several POC "problems" (tap latency, the long-clip stall) may shrink or vanish on device — and one (the research's mid-range Android thermal/latency risk) can only be judged there.

## How this updates the research roadmap

The POC effectively ran an **enhanced Phase 0** and pre-solved much of **Phase 2** (look-ahead, gapless playback) and **Phase 3** (sentence sync) — but on a custom reader + `audioplayers`. So the roadmap ([06](../research/06-mvp-scope-and-roadmap.md)) should be read with these deltas:

- **Phase 0 is *not* fully discharged.** Its real load-bearing question — `flutter_readium` rendering + highlighting under the neural pipeline, on real devices — remains. Re-scope Phase 0 to exactly that, reusing the POC's TTS pipeline.
- **Phase 2** can lean on the proven look-ahead/chunking/chunk-streaming work, but should be (re)built on `just_audio` + `audio_service` and benchmarked on device.
- **Phase 3** has a working reference implementation (completion-driven); decide completion- vs position-driven before building.

## Open questions to resolve before real development

1. Does `flutter_readium` (v0.1.0) render + highlight acceptably under an external neural-TTS pipeline? (Stack go/no-go.)
2. Does `just_audio` `ConcatenatingAudioSource` give gapless clip-queue playback **and** avoid the long-clip stall on a real device?
3. On a real mid-range Android: Piper RTF, tap latency, thermal behavior over a long listening session?
4. Completion-driven vs position-driven sync — which for v1?
5. Voice strategy: which default voice, which optional downloads, bundle vs download-on-demand?

*Back to [index](README.md) · Research [roadmap](../research/06-mvp-scope-and-roadmap.md).*
