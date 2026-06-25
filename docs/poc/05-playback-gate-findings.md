# 05 · Playback Gate Findings (Phase 2, Task 1)

*Narrarr — Phase 2 player go/no-go. Decided 2026-06-25.*

This resolves [MVP spec](../superpowers/specs/2026-06-25-narrarr-mvp-design.md) open-question #2 — which audio player backs background read-aloud — and Task 1 of the [Phase 2 plan](../superpowers/plans/2026-06-25-phase2-read-aloud-background.md).

---

## Decision: ✅ Keep `audioplayers`; add `audio_service` for background + lock-screen. **No `just_audio` migration.**

The spec's plan was "spike `just_audio`'s `ConcatenatingAudioSource` gapless first, fall back to the POC's `audioplayers` hacks." We are **adopting the documented fallback as primary**, without running the spike, on the following reasoning:

1. **The gapless problem is already solved.** The POC's `NeuralNarrator` plays a *dynamically-synthesized, ever-growing* clip queue gaplessly via a 2-player ping-pong (pre-arm the next clip's source on the spare player while the current one plays). This is proven on the emulator and ported verbatim into the real app. `just_audio`'s `ConcatenatingAudioSource` is designed for *known* playlists; appending freshly-synthesized clips mid-playback while preserving perfect gaplessness is exactly the uncertain part the spike would have to prove — i.e. it would be re-litigating a problem we've already beaten.

2. **`audio_service` is player-agnostic.** Background playback, the foreground service, the lock-screen / Now-Playing `MediaSession`, media-button and headset handling, and audio-focus/interruption events all come from `audio_service` + `audio_session` — **independent of the player**. Migrating the player buys nothing toward the actual Phase-2 goal (background + lock-screen).

3. **Lower risk, faster, fully autonomous.** Migrating to `just_audio` risks regressing the one subsystem that already works end-to-end; it also has its own long-clip behavior to re-validate. Keeping `audioplayers` lets Phase 2 focus its risk budget on the genuinely new work (background throttling #3, audio focus #9).

This deviates from the spec's literal "spike `just_audio` first" but is explicitly within its pre-authorized fallback ("keep the POC's `audioplayers` hacks ... as a documented fallback"). User-approved on 2026-06-25.

## Dependency added

- `audio_service: ^0.18.18` (pulls in `audio_session`, `rxdart`, `wakelock_plus`). Resolves cleanly against `flutter_readium` 0.1.0 / `sherpa_onnx` 1.13.3 / `drift`.
- `just_audio` **not** added.

## Revisit-if

- If, on a real mid-range device, the `audioplayers` ping-pong shows audible gaps under background-CPU throttling that we cannot tune out (look-ahead depth, chunk size), reopen this and spike `just_audio`. Until then, `audioplayers` stands.

---

*Prev: [04 · Reader Spike Findings](04-reader-spike-findings.md). Next: Phase 2 Tasks 2–6 build on this decision.*
