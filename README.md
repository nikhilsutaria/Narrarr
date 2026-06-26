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

## 📋 Status: live on Android (Phases 0–4 complete)

Narrarr has moved from research/POC into a **working, device-tested Android app**. The Flutter app lives at the **repo root** (`lib/`, `android/`, `ios/`). The full v1 loop runs end-to-end: import a DRM-free EPUB → read it in a real `flutter_readium` reader → read it aloud with an offline neural voice (sherpa-onnx + Piper) → **the current sentence highlights in sync and the page auto-follows** → background playback with lock-screen controls. Optional higher-quality voices download on demand and run fully offline.

Verified on an emulator and a real **Pixel 8** (incl. EPUB import and voice download). iOS and store/F-Droid distribution are still to come. Bugs and new functionality are tracked as **GitHub issues**.

- 🔬 **Research & validation** (market gap, feasibility, architecture, legal, phased plan): **[`docs/research/`](docs/research/README.md)**

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
1. [Product Vision](docs/research/01-product-vision.md) · 2. [Market & Competition](docs/research/02-market-competitive-analysis.md) · 3. [Technical Feasibility](docs/research/03-technical-feasibility.md) · 4. [Architecture & Stack](docs/research/04-architecture-and-stack.md) · 5. [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md) · [Sources](docs/research/sources.md)

## ⚖️ Notes

- Narrarr only opens **DRM-free** EPUBs you own; it does **not** remove DRM and is not a content store.
- **License:** to be finalized as an early build decision. Note that the active Piper tooling is GPL-3.0, which may favor a copyleft license for the app — see [Technical Feasibility](docs/research/03-technical-feasibility.md) and [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md).
- The legal/compliance notes in the docs are good-faith research, **not legal advice**.
