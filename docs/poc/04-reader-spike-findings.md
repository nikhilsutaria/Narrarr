# 04 · Reader Spike Findings (Phase 0)

*Narrarr — Phase 0 stack go/no-go. Run 2026-06-25 on an Android emulator.*

This is the result of the [Phase 0 reader spike](../superpowers/plans/2026-06-25-phase0-reader-spike.md): does `flutter_readium` render a real EPUB and let our code highlight an arbitrary sentence — driven by the POC's neural-TTS pipeline — well enough to build the real app on? The spike app lives in [`/spike`](../../spike/) (throwaway, like `/poc`).

---

## Verdict: ✅ PASS (functional) — timing still to confirm on real hardware

`flutter_readium` 0.1.0 can render a real EPUB, expose per-sentence Locators, and **highlight an arbitrary sentence programmatically** (correctly spanning multiple verse lines) with automatic page-following, all driven by the POC's external sherpa-onnx + Piper pipeline. The #1 stack risk (#1/#2 in the [MVP spec](../superpowers/specs/2026-06-25-narrarr-mvp-design.md)) is **retired**. **Lock the stack and proceed to Phase 1.**

Two caveats: **(a)** all timing below is from an **x86_64 emulator**, not a real device — RTF, tap latency, and the long-clip stall must still be re-measured on a real mid-range Android before they're trusted; **(b)** `flutter_readium` 0.1.0 demands a **bleeding-edge, tightly-pinned toolchain** that took nine build iterations to satisfy — a real integration cost (see below).

> ⚠️ Measured on a host-backed x86_64 emulator, which here was **fast** (RTF ~0.1). Do not generalize timing to low-end ARM devices without a real-device run.

---

## Checkpoint results

| # | Checkpoint | Result | Evidence |
|---|---|---|---|
| 1 | EPUB renders on device | ✅ PASS | Standard Ebooks *Odyssey* cover + reflowed Book IX body rendered in `ReadiumReaderWidget`. |
| 2 | **Programmatic highlight (crux)** | ✅ PASS | `applyDecorations('group', [ReaderDecoration(locator: Locator(href, text: LocatorText(highlight: sentence)))])` highlighted the exact sentence — including a 3-line verse sentence — in amber. |
| 3 | Auto page-follow | ✅ PASS | `goToLocator()` to the sentence locator navigated across chapters (cover → Book IX) and within the chapter (`prog` 0.0 → 0.045) to keep the highlighted sentence on screen. |
| 4 | On-device Piper RTF | ✅ PASS (emulator) | **RTF 0.10–0.13** across 9 sentences (≈8–10× faster than real-time). See table. |
| 5 | Integrated synced loop | ✅ PASS | Completion-driven loop advanced the highlight [1]→[9] in lockstep with audio, page-following each, no drift, no stalls, no exceptions. |

### RTF samples (emulator, `en_US-amy-low`)

| chars | synth | audio | RTF |
|---|---|---|---|
| 107 | 664 ms | 6 576 ms | 0.10 |
| 278 | 1 782 ms | 14 864 ms | 0.12 |
| 40 | 291 ms | 2 320 ms | 0.13 |
| 115 | 732 ms | 6 624 ms | 0.11 |
| 143 | 938 ms | 8 184 ms | 0.11 |

---

## Notable findings (carry into the real build)

### A. `flutter_readium` 0.1.0 toolchain is bleeding-edge and brittle
Getting it to build on Android required, in sequence: **AGP ≥ 8.9.1** (template ships 8.7.3); **core-library desugaring enabled** with **`desugar_jdk_libs` ≥ 2.1.5**; **Kotlin 2.3.21** (the plugin pins it; older Kotlin gives an internal compiler error in the plugin's serialization code); the **new Kotlin `compilerOptions` DSL** (the old `kotlinOptions { jvmTarget }` is rejected); and **JDK ≥ 18** (the plugin targets Java 18 — JDK 17 fails with `invalid source release: 18`; we installed **Temurin 21** and set `flutter config --jdk-dir`). This is a real maintenance/repro-build risk for a solo dev and for the F-Droid goal — pin all of it explicitly and watch it across plugin updates.

### B. Host Activity must be `FlutterFragmentActivity`
`ReadiumReaderWidget` casts the host Activity to `FragmentActivity`. The default `MainActivity : FlutterActivity` throws `ClassCastException` and the reader hangs on its loading spinner. Fix: `MainActivity : FlutterFragmentActivity`. (Same will apply to iOS-equivalent host setup — verify during the iOS fast-follow.)

### C. The Decorator highlight model is exactly what the sync layer needs
Highlighting by `LocatorText(highlight: <sentence text>)` (no precomputed CSS selector) **worked** and correctly bounded a multi-line verse sentence. Re-applying the same group id cleanly replaces the previous highlight, and `applyDecorations(group, [])` clears it. flutter_readium also exposes `setDecorationStyle(utterance, range)` for a built-in TTS-style utterance/word highlight — worth evaluating for Phase 3 / word-level later.

### D. Locator hrefs are spine-relative and clean
This EPUB's reading order is `epub/text/book-1.xhtml … book-24.xhtml`; matching `href.contains('book-9')` found the chapter, and the same fragment matched epubx's content key — so the segmenter and the reader agree on chapter identity. `onTextLocatorChanged` streams `{href, locations.progression, totalProgression}` for position persistence (Phase 1) and position-driven sync (Phase 3).

### E. Emulator was fast; the POC's long-clip stall did NOT reproduce
RTF ~0.1 on this emulator (the POC assumed emulators are 5–10× slower than devices — not the case here). The 278-char sentence played as a **single 14.8 s clip with no completion stall** and paced *normally* (~19 c/s), unlike the POC's emulator where long single utterances rushed and >12 s clips stalled ~10 s. Tentative implication: the POC's long-clip stall and long-sentence rush may have been specific to its older `audioplayers`/sherpa setup — **but confirm on a real device before relaxing chunk-streaming / chunking in Phase 2.**

---

## What this still does NOT answer (must do on real hardware)
- Real mid-range **Android** RTF, **tap-to-audio latency**, thermal behavior over a long session, memory headroom.
- Whether the long-clip stall / long-sentence rush reproduce on device (→ keep POC chunking + chunk-streaming as carry-forwards until proven unnecessary).
- iOS: nothing here is iOS-validated (fast-follow), incl. the FragmentActivity-equivalent host setup and voice download policy.

## Recommendation
Proceed to **Phase 1 (Library & reader)** on this stack. Bake the §A toolchain pins and §B host-Activity requirement into the real project's Android config from day one. Re-run the timing checks (§"does NOT answer") on a real device early in Phase 2.

*Spike code: [`/spike`](../../spike/). Plan: [phase0-reader-spike](../superpowers/plans/2026-06-25-phase0-reader-spike.md). Back to [index](README.md).*
