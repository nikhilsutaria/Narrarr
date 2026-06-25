# Narrarr 🎙️📖

**Immersion reading for the books you already own — free, open-source, and entirely on your device.**

Narrarr turns your **personal, DRM-free EPUBs** into a Kindle-style *immersion reading* experience: the book is read aloud by an **on-device, offline AI voice** while the text **highlights in sync** so your eyes can follow along — or pocket your phone and just listen, with lock-screen controls.

- 🆓 **Free & open-source**, forever — no subscriptions, no accounts.
- 🔒 **Private by default** — everything runs locally; your books never leave your phone.
- 📱 **Cross-platform** — one app for **iOS and Android**.
- 📚 **Your library** — bring your own DRM-free EPUBs (it's a reader, not a bookstore).
- ♿ **Accessibility-first** — built for dyslexia, low-vision, and print-disability readers.

> **The pitch:** your phone is already powerful enough to narrate a book locally. You shouldn't have to pay a subscription — or upload your reading — to listen to a book you already own.

---

## 📋 Status: concept validated (POC built)

Narrarr is **pre-build**, but the core concept has now been **proven in a throwaway proof-of-concept**: a Flutter app that reads a real EPUB aloud on Android with an offline neural voice (sherpa-onnx + Piper) while the **current sentence highlights in sync** — system and neural voices interchangeable, tap-to-seek, gapless continuous playback.

- 🔬 **Research & validation** (market gap, feasibility, architecture, legal, phased plan): **[`docs/research/`](docs/research/README.md)**
- 🧪 **POC results + the hard-won TTS-playback findings**: **[`docs/poc/`](docs/poc/README.md)**

**Verdict:** feasible for a solo developer, with a genuinely open niche. The POC de-risked the neural read-aloud + sync loop; the **Phase 0 reader spike** then de-risked the last big unknown — `flutter_readium` renders a real EPUB and lets our code **highlight an arbitrary sentence under the neural pipeline, with auto page-follow** (✅ PASS on an emulator; timing still to confirm on real hardware). See the [reader-spike findings](docs/poc/04-reader-spike-findings.md), [POC recommendations](docs/poc/03-recommendations.md), the [MVP design spec](docs/superpowers/specs/2026-06-25-narrarr-mvp-design.md), and the [roadmap](docs/research/06-mvp-scope-and-roadmap.md).

## 🧱 Planned stack (at a glance)

| Layer | Choice |
|---|---|
| App | **Flutter** (one codebase, iOS + Android) |
| On-device TTS | **sherpa-onnx** running **Piper** (default), Matcha / Kokoro (optional) |
| EPUB render + highlight | **Readium** (via `flutter_readium`); foliate-js / native Readium as fallbacks |
| Audio | `just_audio` + `audio_service` (background + lock-screen) |
| Sync highlighting | **Sentence-level** (deterministic, offline) in v1; word-level later |

*Rationale and the honest caveats are in [`docs/research/`](docs/research/README.md).*

## 📖 Documentation

**Research** → [docs/research/README.md](docs/research/README.md)
1. [Product Vision](docs/research/01-product-vision.md) · 2. [Market & Competition](docs/research/02-market-competitive-analysis.md) · 3. [Technical Feasibility](docs/research/03-technical-feasibility.md) · 4. [Architecture & Stack](docs/research/04-architecture-and-stack.md) · 5. [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md) · 6. [MVP Scope & Roadmap](docs/research/06-mvp-scope-and-roadmap.md) · [Sources](docs/research/sources.md)

**POC** → [docs/poc/README.md](docs/poc/README.md)
1. [What Was Built](docs/poc/01-what-was-built.md) · 2. [TTS Pipeline Findings](docs/poc/02-tts-pipeline-findings.md) · 3. [Recommendations for the App](docs/poc/03-recommendations.md)

## ⚖️ Notes

- Narrarr only opens **DRM-free** EPUBs you own; it does **not** remove DRM and is not a content store.
- **License:** to be finalized as an early build decision. Note that the active Piper tooling is GPL-3.0, which may favor a copyleft license for the app — see [Technical Feasibility](docs/research/03-technical-feasibility.md) and [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md).
- The legal/compliance notes in the docs are good-faith research, **not legal advice**.
