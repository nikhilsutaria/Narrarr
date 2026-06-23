# 06 · MVP Scope & Roadmap

*Narrarr — pre-build research. Last updated 2026-06-24.*

This converts the research into a build sequence sized for **one developer**. The guiding rule is **scope discipline** — a reliable, narrow v1 beats an ambitious, fragile one (and is the antidote to the Voice Dream Reader failure mode; see [05 §4](05-risks-legal-compliance.md)).

---

## 1. What v1 *is* and *is not*

**v1 IS:**
- Import a **DRM-free EPUB** (file picker / share sheet / SAF) into an on-device library.
- A clean, accessible **reader** (reflowable, adjustable font/size/theme).
- **Tap-to-listen** with an **offline neural voice** (Piper, bundled).
- **Sentence-level synced highlighting** — the current sentence highlights as it's spoken; pages auto-advance.
- **Background playback** with lock-screen / Now-Playing controls.
- **Fully offline**, no account, no telemetry.
- **iOS + Android** from one Flutter codebase.

**v1 is NOT:**
- ❌ Word-level "karaoke" highlighting (stretch goal — [03 §2](03-technical-feasibility.md)).
- ❌ A bookstore, cloud sync, or accounts.
- ❌ DRM'd files, PDF, or non-EPUB formats.
- ❌ Voice cloning or audio export.
- ❌ A big voice catalog (one good bundled voice + a couple of optional downloads).

## 2. Roadmap (phased)

> Effort labels are *relative* for a solo dev; total to a polished v1 ≈ **3–5 months full-time / 6–12 part-time** ([03 §4](03-technical-feasibility.md)).

### Phase 0 — Validation spike ⚑ (go/no-go for the stack) · ~1–2 weeks
Build the throwaway spike from [04 §5](04-architecture-and-stack.md): open an EPUB in `flutter_readium`, synthesize one sentence with sherpa-onnx + Piper, play it via `just_audio`, and **highlight that sentence** — on a real Android phone *and* a real iPhone. Measure Piper RTF on-device.
- **Pass** → lock the stack, continue.
- **Fail** → switch to a named fallback (foliate-js WebView, or native Readium/KMP) *before* building anything real.
**Exit criteria:** one sentence renders, speaks, and highlights in sync on both platforms.

### Phase 1 — Reader & library MVP · ~3–5 weeks
EPUB import (picker/share/SAF) → app-sandbox storage → `drift` library index → reader with pagination, font/size/theme, and **persisted reading position** (Locator). No audio yet.
**Exit:** import several real-world EPUBs and read them comfortably; positions survive restart.

### Phase 2 — Offline read-aloud (no highlight) · ~3–5 weeks
Bundle one Piper voice; sentence segmentation; sherpa-onnx synthesis with **look-ahead buffering**; `just_audio` + `audio_service` playback; play/pause/skip-sentence, speed control; lock-screen controls; robust **EPUB text normalization** (skip captions/footnotes/nav).
**Exit:** press play on any chapter and hear smooth, gapless narration with background controls.

### Phase 3 — Sentence-level synced highlighting · ~2–4 weeks
Build the **sync layer**: `sentence → (Locator, startMs, endMs)` table from measured clip durations; position-driven `applyDecoration`; auto page-turn to keep the spoken sentence visible; cache timings in `drift`.
**Exit:** the spoken sentence is highlighted with no drift across a whole chapter; pages follow automatically. *(This is the core immersion experience — the product's reason to exist.)*

### Phase 4 — Voices, polish & accessibility · ~3–5 weeks
Optional voice **downloads** (Matcha for iOS HQ; Kokoro gated to capable devices) with ODR/download-on-run + storage management; screen-reader pass and dyslexia-friendly options; onboarding; settings; empty/error states; device-range testing (incl. mid-range Android thermal/latency).
**Exit:** a stranger can install, import a book, pick a voice, and use it accessibly without guidance.

### Phase 5 — Beta & distribution · ~2–4 weeks
TestFlight (iOS) + Google Play closed track + F-Droid prep (reproducible build, no proprietary deps) + GitHub Releases APK. Announce to accessibility/privacy communities ([05 §4](05-risks-legal-compliance.md)); gather feedback; fix; 1.0.

### Stretch / post-1.0 (only after the core is solid)
- **Word-level highlighting** on capable devices (Kokoro timestamped ONNX, or system-TTS callback tier) — [03 §2](03-technical-feasibility.md).
- More bundled voices / languages; per-book voice settings.
- Bookmarks, notes, dictionary lookup; sleep timer; EPUB3 Media Overlays (pre-narrated books).
- Possibly PDF/other formats — *only* if it doesn't compromise the core.

## 3. v1 Definition of Done

- [ ] Import a DRM-free EPUB on iOS **and** Android.
- [ ] Read it (reflowable, adjustable, position remembered).
- [ ] Listen with a bundled **offline neural** voice, fully offline (airplane mode).
- [ ] **Current sentence highlights** in sync; pages auto-advance; no drift over a chapter.
- [ ] Background playback + lock-screen controls work on both platforms.
- [ ] No account, no network required to read/listen, no telemetry.
- [ ] Works on a **mid-range Android** device without stalling.
- [ ] Usable with the platform screen reader.
- [ ] Builds reproducibly from source (F-Droid-ready); open-source license in place.

## 4. Sequencing rationale

- **Spike before build** kills the #1 risk cheaply.
- **Reader → audio → highlight** ships value at each step: a usable reader, then read-aloud, then immersion. If time runs short, each intermediate state is still a real product.
- **Voices & polish after the core** prevents the classic trap of perfecting voice selection before the core loop works.
- **Distribution last**, once there's something worth shipping.

---

*Previous: [05 · Risks, Legal & Compliance](05-risks-legal-compliance.md) · Back to [index](README.md).*
