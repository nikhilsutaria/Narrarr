# 04 · Architecture & Tech Stack

*Narrarr — pre-build research. Last updated 2026-06-24. Sources in [sources.md](sources.md).*

This turns the feasibility findings ([03](03-technical-feasibility.md)) into a concrete, solo-dev-sized architecture: the recommended stack, how the pieces fit, what to reuse, and the **one spike** that must pass before committing.

---

## 1. Recommended stack

| Layer | Choice | Why |
|---|---|---|
| **App framework** | **Flutter** (Dart) | One codebase for iOS + Android; best solo-dev productivity; first-party `sherpa_onnx` package |
| **On-device TTS** | **sherpa-onnx** (`sherpa_onnx` pub.dev) | Only framework with official Flutter + Android + iOS TTS bindings; runs Piper/Matcha/Kokoro |
| **Default voice** | **Piper** (VITS, ~30–75 MB) | Comfortably faster than real-time on mid-range phones; bundleable |
| **HQ / optional voices** | **Matcha** (iOS), **Kokoro-82M** (download, capable devices) | Higher naturalness where the hardware allows |
| **EPUB render + highlight** | **Readium via `flutter_readium`** *(spike-gated)* | Reflowable EPUB2/3 + Decorator highlight API. **Fallbacks: foliate-js in WebView, or native Readium.** |
| **Audio playback / background** | **`just_audio`** + **`audio_service`** (+ `just_audio_background`) | PCM playback, lock-screen/Now-Playing controls, both platforms |
| **Local storage** | **`drift`** (SQLite) + app file storage | Library, reading positions (serialized Locators), highlights, cached sentence timings |
| **File import** | **`file_picker`** + share-sheet / Android SAF | iOS Files & share sheet, Android Storage Access Framework |
| **Inference accel.** | XNNPACK default; Core ML EP (iOS) optional | Cross-platform baseline; optional iOS speedup |

> **Why not React Native / KMP / native?** RN works for TTS but is weaker for precise EPUB highlighting (WebView-bound). **KMP / native** give the *best* Readium access (the native toolkits fully support custom TTS engines and per-word ranges) but **double the platform work** for a solo dev. Flutter is the best starting point; **if the spike fails**, native Readium (KMP) becomes the serious fallback — see §5.

## 2. The key architectural decision: decouple TTS from the reader

Because `flutter_readium` is **v0.1.0** and only does **system-voice** TTS with **no custom-engine injection** ([03 §3](03-technical-feasibility.md)), do **not** try to plug sherpa-onnx *into* the reader. Instead, run **two cooperating subsystems** that meet at a thin sync layer:

- **Reader subsystem** — renders the EPUB and exposes (a) ordered text content with **Locators** per sentence and (b) a way to **apply a highlight decoration** at a Locator. (This is all `flutter_readium` needs to provide.)
- **Narration subsystem** — segments text into sentences, synthesizes each with sherpa-onnx, measures durations, and plays audio via `just_audio` with background controls.
- **Sync layer** — owns the `sentence → (Locator, startMs, endMs)` table; as playback position advances, it tells the reader which sentence to highlight and when to turn the page.

This keeps the risky/immature dependency (the reader bridge) responsible only for **render + highlight**, which it actually advertises — and keeps the **mature** dependency (sherpa-onnx) doing the heavy lifting.

## 3. End-to-end data flow

```
[DRM-free EPUB file]
   │  import (file_picker / share-sheet / SAF) → copy into app sandbox → index in drift
   ▼
[Reader: flutter_readium]
   │  parse spine + content → extract chapter text with per-sentence Locators
   ▼
[Sentence segmenter]  (ICU BreakIterator / NLTokenizer; abbreviation-aware)
   │  ordered sentences, each tagged with its Locator
   ▼
[Narration: sherpa-onnx (Piper)]   ── synthesize sentence N (+ look-ahead N+1) ──┐
   │  PCM audio + exact clip duration                                            │
   ▼                                                                             │
[Sync table]  sentence_index → (Locator, startMs, endMs)   ◄─────────────────────┘
   │
   ▼
[Playback: just_audio + audio_service]  (background, lock-screen controls)
   │  positionStream ticks (~50 ms)
   ▼
[Sync layer]  position → current sentence → flutter_readium.applyDecoration(Locator)
   │                                        └→ if past visible page → navigator.go(next)
   ▼
[Screen]  current sentence highlighted, page auto-advances, audio continues in background
```

Persisted to `drift`/files: library metadata, last position (Locator), highlights, and **cached per-chapter sentence timings** (a few KB) so re-listening doesn't re-synthesize.

## 4. Reusable open-source building blocks

Lean on these; build only the sync layer and UX.

| Component | What to reuse | Link |
|---|---|---|
| **sherpa-onnx** (Apache-2.0) | On-device TTS engine + Flutter/Android/iOS bindings | github.com/k2-fsa/sherpa-onnx · `sherpa_onnx` (pub.dev) |
| **Piper voices** (MIT weights) | Default neural voice models | github.com/OHF-Voice/piper1-gpl |
| **Kokoro-82M** (Apache-2.0) | Optional HQ voice (+ timestamped ONNX variant for later word-level) | huggingface.co/hexgrad/Kokoro-82M |
| **Readium** Kotlin/Swift toolkits | EPUB engine, Locators, Decorator, TTS guide (native fallback path) | github.com/readium |
| **flutter_readium** (v0.1.0) | Flutter EPUB render + Decorator highlight | pub.dev/packages/flutter_readium |
| **foliate-js** | WebView EPUB renderer (fallback) + DOM highlighting | github.com/johnfactotum/foliate-js |
| **just_audio / audio_service** | Playback + background/lock-screen controls | pub.dev |
| **Reference apps to study** | VoxSherpa, NekoSpeak (Android sherpa-onnx), Auread (iOS Readium+SwiftUI), Readest (OSS reader), OpenReader (word alignment), Storyteller (EPUB3 Media Overlays format) | see [sources.md](sources.md) |

## 5. ⚑ The validation spike (do this *first*, before any real build)

**Goal:** prove the riskiest seam — reader render + highlight driven by an *external* neural-TTS pipeline — works on both platforms.

**Spike definition (target ~1–2 weeks):**
1. Open a known DRM-free EPUB in `flutter_readium` on a real Android device **and** a real iPhone.
2. Extract one chapter's text with usable **per-sentence Locators**.
3. Synthesize the first sentence with sherpa-onnx + Piper; play it via `just_audio`.
4. **Highlight that sentence** in the rendered page via `flutter_readium`'s Decorator API, timed to the audio.
5. Measure Piper synthesis RTF on the test devices to confirm "faster than real-time."

**Pass / fail:**
- ✅ **Pass** → the Flutter + flutter_readium + sherpa-onnx stack is confirmed; proceed with the build.
- ❌ **Fail** (flutter_readium too thin/unstable to extract Locators or apply decorations programmatically) → fall back, in order: **(a) foliate-js in a WebView** (full DOM control of highlighting; more JS↔Dart glue), or **(b) native Readium via KMP** (best capability, most work). The narration subsystem (sherpa-onnx + just_audio) is unchanged in every fallback.

This spike is **Phase 0** of the roadmap and the project's go/no-go gate for the stack.

## 6. Component responsibilities (one purpose each)

- **Library/Import** — bring files in, store metadata, manage downloaded voices.
- **Reader** — render EPUB, expose sentence Locators, apply highlight decorations.
- **Segmenter** — turn chapter HTML/text into clean, speakable sentences (the quality-critical bit).
- **Narrator** — synthesize sentences (sherpa-onnx), buffer look-ahead, measure durations.
- **Player** — play PCM, expose position, own background/lock-screen controls.
- **Sync** — map position ↔ sentence ↔ Locator; drive highlight + page turns.
- **Voice manager** — bundle Piper; download/verify/evict optional voices.

Each is independently testable and small enough to reason about — which matters most when one person maintains all of it.

---

*Previous: [03 · Technical Feasibility](03-technical-feasibility.md) · Next: [05 · Risks, Legal & Compliance](05-risks-legal-compliance.md)*
