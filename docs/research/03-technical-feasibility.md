# 03 · Technical Feasibility

*Narrarr — pre-build research. Last updated 2026-06-24. Sources in [sources.md](sources.md).*

This document answers the make-or-break question: **can a solo developer actually build offline neural TTS with synced highlighting for personal EPUBs, on both iOS and Android?** Short answer: **yes — with sentence-level highlighting as the dependable target, and one integration that must be de-risked with a spike first.** The architecture that follows from these findings is in [04 · Architecture & Stack](04-architecture-and-stack.md).

> ⚠️ **Confidence note.** Engine capabilities, the verified `sherpa_onnx`/`flutter_readium` package facts, and the sentence-vs-word reliability gap are well-corroborated. Specific on-device benchmark *numbers* vary by source and device and are directional, not guarantees — treat them as "comfortably real-time" vs "borderline" buckets, and re-measure on target hardware during the spike.

---

## 1. On-device TTS engine survey

The hard constraints: must run **offline on a phone**, in roughly **real-time or faster** (so playback doesn't stall), at a **mobile-sane size/RAM**, under a **license that permits free redistribution**, with a **real iOS + Android path**.

| Engine | Size (1 voice) | Speed on phone | RAM | Quality | License | Mobile path | Verdict |
|---|---|---|---|---|---|---|---|
| **Piper** (VITS) | ~20–75 MB | **Well faster than real-time** on mid-range Android | ~80 MB | Good | MIT weights / GPL-3 tooling | **Excellent** — via sherpa-onnx (official Flutter/Android/iOS) | ✅ **Primary** |
| **Matcha-TTS** | ~150–210 MB | Faster than real-time; best on iOS | ~210 MB | Very good | Apache-2.0 | Excellent — via sherpa-onnx | ✅ Strong alt (esp. iOS) |
| **Kokoro-82M** | ~80 MB (int8) – 330 MB | **Borderline/slower than real-time on mid-range Android**; OK on recent iOS | up to ~800 MB peak | Excellent | Apache-2.0 | Good — sherpa-onnx / ONNX Runtime | ⚠️ Optional "HQ" download, capable devices only |
| **eSpeak-NG** | ~5 MB | Trivial | <20 MB | Poor (robotic) | GPL-3+ | Good | ⛑️ Last-resort fallback |
| XTTS-v2 (Coqui) | 1.8+ GB | Not viable on phone | ~3.6 GB | Very good | **CPML non-commercial** | None | ❌ Eliminated (license + size) |
| Parler-TTS | 1.8+ GB | Not viable | 1.8–3.6 GB | Very good | Apache-2.0 | None | ❌ Eliminated (size) |
| MeloTTS | ~200 MB | Unproven on mobile | ? | Good | MIT | None proven | ❌ Deprioritized |
| StyleTTS2 | — | Not viable on phone | 2+ GB | Very good | MIT | None | ❌ Use Kokoro (its derivative) instead |

**sherpa-onnx (k2-fsa, Apache-2.0)** is the linchpin: it is the *only* framework that ships **official iOS (XCFramework), Android (AAR/JNI), and Flutter** bindings for these models, and supports Piper/VITS, Matcha, Kokoro and more. *Verified:* the `sherpa_onnx` Flutter package is mature (v1.13.x, Android multi-arch + iOS arm64) and actively maintained. This collapses the hardest part of "neural AI on a phone" into a dependency.

**Recommendation:**
- **Default voice: Piper via sherpa-onnx.** It's the only engine that is *comfortably* faster than real-time on mid-range Android, is small enough to bundle one voice, and has the most battle-tested mobile path.
- **iOS high-quality option: Matcha-TTS** (best quality/speed on Apple silicon).
- **Optional download: Kokoro-82M** as a "higher quality, capable devices only" voice — *never* the default on Android.

## 2. The synced-highlighting problem (the crux)

To highlight the text being spoken, the app must map **audio time → text position**, in real time, offline. *Verified:* sherpa-onnx's high-level TTS API returns **audio only — no word/phoneme timestamps**. So there are three strategies, easiest → hardest:

### Approach A — Sentence-level deterministic timing ✅ (recommended for v1)
Synthesize **one sentence at a time**; you know each clip's exact duration, so you know exactly when each sentence starts and ends. Build a `sentence → (startMs, endMs)` table and highlight the current sentence as audio plays. **Zero drift, no extra models, fully offline.** It also sounds natural (narrators pause at sentence ends) and lets you synthesize sentence *N+1* while *N* plays. Research on TTS-narrated ebooks reports direct-timing capture vastly outperforms post-hoc forced alignment for sync reliability. This is essentially what Kindle Immersion Reading does in practice.

### Approach B — Word-level via model/aligner ⚠️ (later phase)
Options, all heavier:
- **Kokoro timestamped ONNX variant** emits phoneme durations → word boundaries, but Kokoro is slow on mid-range Android and memory-hungry → restrict to capable devices.
- **On-device forced alignment** (aeneas, MFA, WhisperX, ctc-forced-aligner): all require loading a **second heavy model** (hundreds of MB) alongside the TTS model → impractical on a phone and prone to drift. The OSS **OpenReader** project does Whisper-based word alignment, but as a *self-hosted server* pattern, not on a phone.
- **Proportional estimation** within a sentence (split sentence duration across word lengths): crude karaoke that's cheap but imprecise.

### Approach C — Platform system TTS word callbacks 🔁 (fallback voice path)
iOS `AVSpeechSynthesizer` (`willSpeakRange`) and Android `TextToSpeech` (`onRangeStart`) emit **word-boundary callbacks for free** — but only when using **system voices** (not the neural models). Useful as a zero-download "instant voice" tier and for word-level highlight without bundling anything, at the cost of voice quality/consistency.

| Approach | Granularity | Offline | Extra model | Drift risk | Effort | When |
|---|---|---|---|---|---|---|
| A · Sentence timing | Sentence | ✅ | none | none | Low | **v1** |
| B · Word (Kokoro/aligner) | Word | ✅ | yes (heavy) | medium | High | Later, capable devices |
| C · System-TTS callbacks | Word | ✅ | none | low | Low–med | Optional "instant voice" tier |

**Recommendation:** ship **Approach A (sentence-level)** with neural voices in v1; offer **Approach C** as an optional instant/word-level tier if cheap; treat **Approach B word-level neural** as a v2 stretch goal on capable devices. **Do not promise word-perfect neural karaoke in v1.**

## 3. EPUB rendering & precise highlighting

Rendering reflowable EPUB2/3 *and* being able to highlight a specific text range is a solved problem only in a few places:

- **Readium** (Kotlin + Swift toolkits) is the industry standard: reflowable EPUB2/3, **Locators** (stable positions), a **Decorator API** for highlights, and a **TTS guide** with per-utterance ranges. Powers 100+ apps. This is the gold standard — but its full power lives in the **native** toolkits.
- **`flutter_readium`** — *verified:* a **very early (v0.1.0)** Flutter bridge that *does* render EPUB2/3 and supports **highlights via the Decorator API**, but its TTS is **platform-native (system voices)** and it advertises **no custom-engine injection**. Useful for rendering + highlighting; **not** a drop-in for neural TTS.
- **foliate-js** in a WebView: mature, accurate JS renderer; you control highlighting via the DOM, at the cost of JS↔Dart glue. A strong fallback.

**Implication:** the cleanest design is to **let the reader handle rendering + highlighting, and run neural TTS as a *separate* synchronized pipeline** (sherpa-onnx → audio → `just_audio`), rather than trying to plug a neural engine *inside* the reader. Details in [04](04-architecture-and-stack.md).

## 4. Feasibility verdict

**Feasible for a solo developer.** Rough effort to a polished v1: **~3–5 months full-time, or ~6–12 months part-time.** Every major component exists as mature OSS; the work is integration and UX, not invention. The lowest-effort wins (sherpa-onnx + Piper, background audio, file import) are well-trodden; the real engineering is the **render ↔ audio ↔ highlight synchronization** and **robust EPUB text extraction**.

## 5. Traps & showstoppers (read before committing)

1. **`flutter_readium` is v0.1.0.** It can render + highlight, but it won't host neural TTS and its API may be too thin/unstable to drive external sync. **This is the #1 risk** → the [04](04-architecture-and-stack.md) **validation spike** exists specifically to test it, with foliate-js / native Readium as named fallbacks. Do not write months of code before this spike passes.
2. **Kokoro on mid-range Android is a trap.** It's slower than real-time there and memory-hungry. Make Piper the default; gate Kokoro behind a "capable device" check and an explicit download.
3. **On-device forced alignment for word-level is a trap.** A second heavy model will exhaust RAM and still drift. Use sentence-level timing instead.
4. **EPUB text extraction is a silent quality killer.** EPUB is messy HTML — footnotes, asides, captions, nav. Naive extraction makes the voice read "Chapter 3 Notes See footnote 47" mid-paragraph. Budget real time for content normalization; Readium handles much of this better than rolling your own.
5. **Model size vs app stores.** A 30–80 MB Piper voice is borderline-large to bundle; Kokoro definitely isn't bundleable. Plan **download-on-first-run** (Android) / **on-demand resources** (iOS), with an offline-first onboarding flow. (See [05](05-risks-legal-compliance.md).)
6. **DRM is out of scope.** The app can only open **DRM-free** EPUBs; purchased Kindle/Kobo files won't parse. This is a product constraint, not a bug — communicate it clearly.
7. **Piper's original repo is archived; the active fork is GPL-3.** Fine for a fully-OSS app. The MIT-licensed voice weights remain usable via sherpa-onnx regardless, so the dependency is low-risk.
8. **Streaming without gaps.** With Piper's speed this is usually fine, but unusual words can spike synthesis time — implement a 1–2 sentence look-ahead synthesis buffer.

---

*Previous: [02 · Market & Competitive Analysis](02-market-competitive-analysis.md) · Next: [04 · Architecture & Stack](04-architecture-and-stack.md)*
