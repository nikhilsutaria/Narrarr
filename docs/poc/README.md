# Narrarr — POC Findings

*Proof-of-concept phase. Last updated 2026-06-24.*

This folder documents the **throwaway proof-of-concept** built in [`/poc`](../../poc/) after the [research phase](../research/README.md) — and, more importantly, the **hard-won technical findings** from making on-device neural read-aloud actually sound smooth. It exists so the real app is built on evidence, not re-discovery.

> The POC's job was to answer: *does the core Narrarr loop — EPUB text + on-device neural voice + sentence highlight that stays in sync — actually work and feel good?* **Yes.** But getting neural TTS to play **gaplessly** took solving four stacked problems that aren't obvious up front. They're all documented here.

## Headline outcome

**The concept is validated on an Android emulator.** A Flutter app loads a real EPUB (*The Odyssey*, Book IX), shows the text, and reads it aloud while the **current sentence highlights in sync** and the view auto-scrolls. It supports **two interchangeable engines** — the OS voice (`flutter_tts`) and a fully **offline neural voice** (sherpa-onnx + Piper) — selectable at runtime, plus **tap-any-line-to-play-from-there**.

After fixes, neural continuous playback is **gapless** (0–19 ms between sentences) with correct, drift-free sentence sync.

## What this de-risks (vs. the research Phase 0 spike)

The research plan ([06 · roadmap](../research/06-mvp-scope-and-roadmap.md)) called for a 1–2 week Phase 0 spike to prove "one sentence renders, speaks, and highlights." The POC went **further**, proving the *continuous* experience and solving Phase-2/Phase-3 problems early:

- ✅ On-device Piper synthesis + playback + **sentence-level synced highlighting**, end-to-end.
- ✅ **Gapless** sentence-to-sentence playback (the research's "look-ahead buffering" — built and proven).
- ✅ A clean **engine abstraction** (system vs neural behind one interface) and a **completion-driven sync** that doesn't drift.
- ✅ Robust handling of **long sentences** and **verse** text.

…but it did so on a **custom `ListView` reader** and **`audioplayers`**, *not* the research-recommended `flutter_readium` + `just_audio`. See [03 · recommendations](03-recommendations.md) for what that means for the real build.

## Important caveats

- **Emulator only.** Everything was measured on an x86 Android emulator, which is **~5–10× slower** at neural synthesis than a real phone and has at least one audio quirk (long-clip stall) that may not exist on device. **Real-device testing is a prerequisite before trusting any timing.** ([02 §6](02-tts-pipeline-findings.md))
- **Throwaway code.** `/poc` is a disposable spike with diagnostic logging still in place — it is *reference*, not the foundation of the app.
- **Not committed.** Per the working agreement during the spike, `/poc/` and the test EPUB are untracked. (Research docs are committed.)

## Read in this order

1. **[01 · What Was Built](01-what-was-built.md)** — scope, repo layout, dependencies, how to run, the engine abstraction, the demo passage.
2. **[02 · TTS Pipeline Findings](02-tts-pipeline-findings.md)** — the core value: the synth→playback pipeline, the completion-driven sync, and the **four stacked playback problems** (rushed long sentences, inter-sentence gap, per-clip startup gap, long-clip stall) with the measurements and the fix for each. Plus voice and emulator findings.
3. **[03 · Recommendations for the App](03-recommendations.md)** — what to carry forward, what to change, how this updates the research roadmap, and open questions to resolve before real development.
4. **[04 · Reader Spike Findings](04-reader-spike-findings.md)** — Phase 0 go/no-go: `flutter_readium` renders + highlights an arbitrary sentence under the neural pipeline (**PASS**, emulator); the bleeding-edge toolchain it demands; what still needs a real device.
