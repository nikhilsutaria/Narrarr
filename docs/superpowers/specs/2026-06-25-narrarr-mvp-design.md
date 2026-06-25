# Narrarr — MVP Design Spec (v1)

*Created 2026-06-25. Supersedes the v1 framing in [research/06](../../research/06-mvp-scope-and-roadmap.md) where they differ; incorporates the [POC findings](../../poc/README.md).*

This is the build spec for Narrarr v1 — the first real, shippable app, as opposed to the throwaway POC. It applies the POC's hard-won learnings, names the challenges the POC did **not** surface, and turns both into a phased MVP that a solo developer can execute.

---

## 1. What Narrarr is

Immersion reading for DRM-free EPUBs the user already owns: the book is read aloud by an **on-device, offline neural voice** while the **current sentence highlights in sync** and pages auto-advance — or pocket the phone and just listen, with lock-screen controls. Free, open-source, private (nothing leaves the device), accessibility-first.

The core loop — *EPUB text + offline neural voice + sentence highlight that stays in sync* — is **already validated** by the POC on an Android emulator. v1 is about making that loop production-grade and wrapping it in a real reader, library, and background-playback shell.

---

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Platform** | **Android-first**, iOS fast-follow | POC's proven pipeline is Android; iOS adds unvalidated work (Readium-on-iOS, voice-download policy, Core ML, App Store review). Ship Android 1.0, then a dedicated iOS hardening pass. Codebase kept iOS-clean throughout. |
| **Reader** | **`flutter_readium`, gated by a Phase-0 spike** | #1 unretired risk. A ~1-week throwaway spike proves render + programmatic highlight under the external neural pipeline *before* committing. Fallback on spike failure: **foliate-js in a WebView**, then native Readium. |
| **Playback** | **`just_audio` + `audio_service`** | Native gapless playlist + background/lock-screen controls. Spike `ConcatenatingAudioSource` early; keep the POC's `audioplayers` hacks (2-player ping-pong, chunk-streaming) as a documented fallback. |
| **Sync model** | **Position-driven** (`sentence → (Locator, startMs, endMs)` table) | More flexible than the POC's completion-driven advance: required for seek, page-turn, background re-sync, and (later) speed control and word-level highlighting. Reuse the POC's completion signal to *measure* clip durations that populate the table. |
| **Voices** | **Download-on-demand**, default a **quality** voice (`ryan-medium`-class) | Don't bloat the app with an 80 MB bundle. Low-tier voices aren't faster (same model size), just duller. One good default + a couple of optional downloads. |
| **Speed control** | **Fast-follow (NOT v1)** | Deferred to keep v1 lean. **But the Phase-3 sync layer is designed to accommodate it** (timing table + length-scale re-synth), so adding it later is an extension, not a rewrite. |

---

## 3. Carry forward from the POC (proven — reuse, don't re-derive)

These cost real debugging in the POC ([poc/02](../../poc/02-tts-pipeline-findings.md)). Treat them as known constraints:

- **`TtsEngine` abstraction** — one interface; `speak` completes on real audio-end; system + neural implementations behind it.
- **Long-sentence chunking** — split any sentence > ~120 chars into clause-sized pieces before synthesis, or Piper's duration predictor compresses/rushes long input. **Non-negotiable.**
- **Look-ahead pre-synthesis on a persistent isolate** — synthesize sentence *i+1…i+n* while *i* plays. Native pointers can't cross a `SendPort`, so `OfflineTts` lives **inside** the isolate; only text in, file path out.
- **Chunk-streaming long sentences** — play a long line as several short clips (each ≤ ~7 s). Fixes the long-clip completion stall *and* lowers tap latency. (The stall itself may be emulator-only — re-check on device; keep chunk-streaming regardless, it helps tap latency.)
- **Warm-up synth on init + precache opening lines** — the first `generate()` is a slow cold-start.
- **Verse/HTML-aware text normalization** — handle `<br/>` → space, block-closers → newline, drop chapter `<header>`, treat in-sentence `\n` as whitespace.
- **All heavy work off the UI isolate** — do synthesis **and** WAV/file encoding in the background isolate; return a small file path, never large PCM buffers, across the `SendPort`.

---

## 4. Challenges the POC did NOT surface

The POC was one clean chapter, one hand-picked EPUB, one screen, foreground-only, on an emulator. Almost everything *around* the core loop is unvalidated. Prioritized by threat level:

### 🔴 Stack-risk (could force a pivot)
1. **Reader integration** — `flutter_readium` render + programmatic sentence highlight via the Decorator API, driven by an *external* pipeline. The POC's `ListView` proved nothing here. → Phase 0 gate.
2. **Locators across reflow** — sentence→position mapping must stay stable across font/theme change, pagination, and restart; highlighting a sentence that **spans a page boundary** is new. A `ListView` index won't do.
3. **Background synthesis throttling** — neural synth runs in an isolate; OS background-CPU limits (Android Doze; iOS later) can starve the look-ahead buffer when the screen locks — directly threatens the "pocket it and listen" promise. POC was foreground-only.

### 🟠 Real-world-data risk (bugs/crashes)
4. **Messy real EPUBs** — footnotes, endnotes, captions, tables, nav/TOC, image alt-text, page numbers, blockquotes, drop-caps, multi-file spines, mixed languages. The narrator must **skip non-narratable content**. POC hand-tuned one clean verse chapter.
5. **DRM'd / corrupt / non-spec files** — detect and reject gracefully with a clear message; never crash or look broken.
6. **Whole-book traversal** — POC hard-coded `book-9`, capped at 80 sentences. Real app crosses chapters/spine, front/back matter, and very large books (memory).

### 🟡 Net-new subsystems (POC stubbed entirely)
7. **Library & import** — file picker / share sheet / Android SAF, copy-to-sandbox, metadata + cover extraction, `drift` index, delete, storage accounting.
8. **Persistence** — reading position as a stable Locator; cached per-chapter sentence timings so re-listening doesn't re-synthesize.
9. **Background playback & audio focus** — lock-screen / Now-Playing / media-button / headset controls, plus interruptions (calls, other audio, Bluetooth disconnect, notification ducking) and correct resume.
10. **Seek / scrub** — jumping to an arbitrary position breaks the POC's completion-driven model; this is a core reason to go position-driven.
11. **Voice manager** — download / resume / verify (checksum) / evict; first-run download UX (and the tension with the "fully offline" promise *before* the first download); voice-switch invalidating cached timings.
12. **Accessibility conflict** — when TalkBack is on, the screen reader and the app's own narration both want to speak; needs deliberate semantics so they don't collide. Plus dyslexia fonts/themes, adjustable spacing, large tap targets.

### 🟢 Process / can't-defer-by-design
13. **Real-device performance** — sustained Piper RTF (> 1, faster-than-realtime), thermal throttling over hours, battery, memory headroom, cold-start. Every POC number is emulator (~5–10× off).
14. **Architecture & state** — POC was ad-hoc single-screen. Real app needs the 7-subsystem decomposition, real state management, navigation, DI — established in Phase 1, not retrofitted.
15. **Testing audio-sync** — POC verified by ear + logs. Need a real strategy: unit-test the segmenter and the sync-table math; decide how to assert sync without a human ear.
16. **Distribution constraints** — F-Droid reproducible build / no proprietary blobs, license decision (GPL-3 Piper *tooling* consideration), store privacy disclosures — these shape choices *now*, not at the end.

---

## 5. Architecture (7 subsystems, one purpose each)

From [research/04](../../research/04-architecture-and-stack.md). The key principle: **decouple TTS from the reader** — the immature reader bridge is responsible only for *render + highlight*; the mature TTS engine does the heavy lifting; a thin **sync layer** is the only place they meet.

- **Library/Import** — bring files in, store metadata, manage downloaded voices.
- **Reader** — render EPUB (`flutter_readium`), expose per-sentence Locators, apply highlight decorations, turn pages.
- **Segmenter** — turn chapter content into clean, speakable sentences (abbreviation-aware; ICU `BreakIterator`); skip non-narratable content. Quality-critical.
- **Narrator** — synthesize sentences (sherpa-onnx + Piper) on a persistent isolate, buffer look-ahead, measure durations.
- **Player** — play clips gaplessly (`just_audio`), expose position, own background/lock-screen controls (`audio_service`).
- **Sync** — own the `sentence → (Locator, startMs, endMs)` table; map playback position → current sentence → highlight + page turn. **Designed speed-control-ready.**
- **Voice manager** — bundle nothing heavy; download / verify / evict voices.

Each is independently testable. State management (Riverpod or Bloc — decide in implementation planning), navigation, and DI established in Phase 1.

---

## 6. v1 scope

**v1 IS:**
- Import a **DRM-free EPUB** (file picker / share sheet / Android SAF) into an on-device library.
- A clean, accessible, **reflowable reader** — adjustable font / size / line-spacing / theme; **reading position remembered** across restart and font changes.
- **Tap-to-listen** with a downloaded **offline neural voice** (Piper).
- **Sentence-level synced highlighting** — current sentence highlights as spoken; pages auto-advance; no drift over a chapter.
- Play / pause / skip-sentence; **seek** to a tapped sentence.
- **Background playback** with lock-screen / Now-Playing controls; correct interruption/resume.
- **Fully offline** after the one-time voice download; no account, no telemetry.
- Usable with **TalkBack**; dyslexia-friendly font/theme options.
- **Android.**

**v1 is NOT:**
- ❌ **Speed control** (fast-follow — sync layer is designed for it).
- ❌ Word-level "karaoke" highlighting (stretch).
- ❌ A bookstore, cloud sync, or accounts.
- ❌ DRM'd files, PDF, or non-EPUB formats.
- ❌ Voice cloning or audio export.
- ❌ A large voice catalog (one good default + a couple of optional downloads).
- ❌ **iOS** (fast-follow).

---

## 7. Build sequence

Each phase ships something real; every phase that touches timing/perf is **measured on a real mid-range Android device**, not an emulator. POC techniques are carried into the phases that need them.

### Phase 0 — Reader spike ⚑ (go/no-go gate) · ~1–2 weeks
Rebuild the proven core loop on `flutter_readium`, on a **real Android device**: open a real DRM-free EPUB → extract one chapter's text with usable per-sentence **Locators** → synthesize the first sentence with the POC's sherpa-onnx + Piper pipeline → **highlight that sentence** via the Decorator API, timed to the audio → measure Piper **RTF** on device.
- **Pass** → lock the stack; proceed.
- **Fail** (can't extract Locators / can't apply decorations programmatically / too unstable) → fall back to **foliate-js in a WebView**, then native Readium. The narration subsystem is unchanged in every fallback.
- **Retires:** #1, #2, partial #13. **Exit:** one sentence renders, speaks, and highlights in sync on a real device.

### Phase 1 — Library & reader · ~3–5 weeks
EPUB import (picker / share / SAF) → copy to app sandbox → `drift` library index (title, author, cover) → reflowable reader with pagination, font/size/theme, and **persisted Locator** position. Graceful **DRM/corrupt-file rejection**. Establish project architecture, state management, DI, navigation. No audio yet.
- **Retires:** #5, #6, #7, #8, #14; begins #4.
- **Exit:** import several real-world EPUBs and read them comfortably; positions survive restart and font change.

### Phase 2 — Offline read-aloud (no highlight) · ~3–5 weeks
Bundle/download one quality Piper voice → **whole-book sentence segmentation** (abbrev-aware; skip non-narratable content) → sherpa-onnx synthesis on the persistent isolate with **look-ahead buffering** → `just_audio` + `audio_service` playback (spike gapless `ConcatenatingAudioSource` first; chunk-streaming fallback) → play / pause / skip-sentence → lock-screen controls and **audio-focus/interruption handling**. Voice download-on-demand foundation.
- **Carries POC:** chunking ≤120 c, look-ahead isolate, chunk-streaming, warm-up, all-heavy-work-off-UI-isolate.
- **Retires:** #3, #9, completes #4; begins #11.
- **Exit:** press play on any chapter → smooth, gapless narration that keeps playing in the background and survives a phone call.

### Phase 3 — Sentence-level synced highlighting · ~2–4 weeks
Build the **position-driven sync layer**: `sentence → (Locator, startMs, endMs)` table populated from measured clip durations; position-driven `applyDecoration` highlighting; auto page-turn to keep the spoken sentence visible; **seek** to a tapped sentence; cache timings in `drift`. **Designed speed-control-ready** (table + length-scale re-synth path stubbed, not wired to UI).
- **Retires:** #10; completes the core immersion loop.
- **Exit:** spoken sentence highlighted with no drift across a whole chapter; pages follow automatically; tapping a sentence seeks there. *(The product's reason to exist.)*

### Phase 4 — Polish & accessibility · ~3–5 weeks
Optional voice **downloads** with storage management; **TalkBack** pass (resolve the screen-reader-vs-narration conflict) + dyslexia options; onboarding; settings; empty/error states; **device-range testing incl. thermal/battery over a long session**.
- **Retires:** #11 (full), #12, #13 (full).
- **Exit:** a stranger can install, import a book, download a voice, and use it accessibly without guidance.

### Phase 5 — Beta & distribution · ~2–4 weeks
Google Play closed track + **F-Droid reproducible-build prep** (no proprietary blobs) + GitHub Releases APK; **license finalized** (GPL-3 Piper-tooling consideration); store privacy disclosures; announce to accessibility/privacy communities; feedback → 1.0.
- **Retires:** #16.

> **Total to polished Android v1 ≈ 3–5 months full-time / 6–12 part-time** (solo). iOS fast-follow is a separate effort after 1.0.

---

## 8. v1 Definition of Done (Android)

- [ ] Import a DRM-free EPUB; DRM/corrupt files rejected with a clear message.
- [ ] Read it: reflowable, adjustable font/size/theme, position remembered across restart **and** font change.
- [ ] Listen with a downloaded offline neural voice, fully offline (airplane mode) after the one-time download.
- [ ] **Current sentence highlights** in sync; pages auto-advance; **no drift over a chapter**.
- [ ] Tap a sentence to seek there; play / pause / skip-sentence work.
- [ ] Background playback + lock-screen controls; survives a phone call / Bluetooth disconnect and resumes correctly.
- [ ] No account, no network required to read/listen (post-download), no telemetry.
- [ ] Works on a **real mid-range Android** without stalling or overheating over a long session.
- [ ] Usable with TalkBack; dyslexia-friendly options present.
- [ ] Builds reproducibly from source (F-Droid-ready); open-source license in place.

---

## 9. Testing strategy (challenge #15)

- **Unit** — segmenter (abbreviation/verse/edge cases), sync-table math (position → sentence index), chunking thresholds, Locator (de)serialization.
- **Integration** — import → index → render → segment → synth → play → highlight, on a corpus of **real, messy EPUBs** (build a small test library covering footnotes, tables, multi-file spines, EPUB2 & EPUB3, a DRM'd file, a corrupt file).
- **Sync without a human ear** — assert the timing table is monotonic and gap-free and that the highlighted index matches the table at sampled positions; reserve by-ear checks for quality/naturalness only.
- **Device matrix** — at least one low-end and one mid-range real Android device; long-session thermal/battery run.

---

## 10. Open questions to resolve during implementation planning

1. **State management** — Riverpod vs Bloc (decide before Phase 1 scaffolding).
2. **just_audio gapless** — does `ConcatenatingAudioSource` give gapless clip-queue playback *and* avoid the long-clip stall on a real device? (Validate in Phase 2; chunk-streaming fallback ready.)
3. **Voice default & catalog** — exact default voice and which 1–2 optional downloads; download hosting/CDN.
4. **License** — copyleft (GPL-3, aligns with Piper tooling) vs permissive; finalize before Phase 5, ideally noted by Phase 1.
5. **Segmenter source of truth** — segment from `flutter_readium`'s extracted content vs a parallel parse; must produce Locator-aligned sentences.

---

*Predecessor docs: [research/](../../research/README.md) · [poc/](../../poc/README.md). This spec is the bridge from POC to v1 build.*
