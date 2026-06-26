<div align="center">

# Narrarr 🎙️📖

### Immersion reading for the books you already own

**An on-device, offline AI voice reads your DRM-free EPUBs aloud while the text highlights in sync — free, private, and open-source.**

[![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)](#-status)
[![iOS](https://img.shields.io/badge/iOS-planned-lightgrey?logo=apple&logoColor=white)](#-roadmap)
[![Built with Flutter](https://img.shields.io/badge/built%20with-Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Offline](https://img.shields.io/badge/100%25-offline-success)](#-private-by-design)
[![Accessibility first](https://img.shields.io/badge/accessibility-first--class-blueviolet)](#-features)
[![License: GPL v3](https://img.shields.io/badge/license-GPLv3-blue)](LICENSE)

[**Features**](#-features) · [**How it works**](#-how-it-works) · [**Build it**](#-getting-started) · [**Roadmap**](#-roadmap) · [**Docs**](#-documentation)

</div>

---

Narrarr turns the **personal, DRM-free EPUBs you already own** into a Kindle-style *immersion reading* experience: the book is read aloud by an **on-device neural voice** while the **current sentence highlights in sync** and the page auto-follows — so your eyes can track along, or you can pocket your phone and just listen with full lock-screen controls.

> **The pitch:** your phone is already powerful enough to narrate a book locally. You shouldn't have to pay a subscription — or upload what you read — to listen to a book you already own.

---

## 📸 Screenshots

> **Maintainer note:** screenshots aren't committed yet. Add captures to `docs/screenshots/` and uncomment the block below to make them render. Recommended set: the library grid, the reader with a sentence highlighted, the playing state, and the lock-screen / notification controls. A 10–15s screen recording of the read-aloud loop (`docs/screenshots/demo.gif`) is the single most effective thing you can add here.

<!-- Once the images exist in docs/screenshots/, delete this comment wrapper to show them:
<div align="center">

| Library | Reading + sync highlight | Lock-screen controls |
|:---:|:---:|:---:|
| <img src="docs/screenshots/library.png" width="240" alt="Library"/> | <img src="docs/screenshots/reader.png" width="240" alt="Reader with synced highlighting"/> | <img src="docs/screenshots/lockscreen.png" width="240" alt="Lock-screen playback controls"/> |

</div>
-->

<div align="center">

_📷 Screenshots coming soon — [build it yourself](#-getting-started) to see the read-aloud loop in action._

</div>

---

## ✨ Features

- 🗣️ **Read-aloud with synced highlighting** — a natural neural voice narrates while the current sentence lights up and the page follows along automatically.
- 📴 **100% offline** — narration runs entirely on-device. No network needed for core reading. The default voice is bundled in the app.
- 🆓 **Free & open-source** — no subscriptions, no accounts, no paywalls.
- 🔒 **Private by design** — your books and your reading never leave your phone.
- 🎧 **Listen anywhere** — background playback with lock-screen / notification media controls; put the phone away and keep listening.
- 👆 **Tap to jump** — tap any sentence to start narration from exactly there.
- 🎙️ **Optional higher-quality voices** — download extra voices on demand; they too run fully offline once installed.
- 📚 **Your library, your books** — import any DRM-free EPUB you own. Narrarr is a reader, not a bookstore.
- ♿ **Accessibility-first** — designed for dyslexia, low-vision, and print-disability readers, with the bundled [Atkinson Hyperlegible](https://brailleinstitute.org/freefont) font and adjustable size, spacing, and theme.

---

## 🔧 How it works

The whole-book read-aloud loop spans four cooperating layers, and one invariant makes the magic work without timers or guesswork:

> **`speak()` returns only when the audio for that sentence has actually finished playing.** The highlight advances when narration of sentence *i* completes, so it stays locked to the audio — perfectly, on any device.

```
EPUB  ─►  Segmenter        HTML → clean, narratable sentences
          (DOM-aware)      (drops nav, footnotes, captions, tables…)
            │
            ▼
        NarrationController  highlight sentence i → await its audio → advance to i+1
            │                (look-ahead pre-synthesis for gapless playback)
            ▼
        NeuralNarrator       sherpa-onnx + Piper, synthesized on a background isolate
            │                (long-sentence chunking · two-player ping-pong preload)
            ▼
        Reader + audio_service   synced highlight on screen · lock-screen controls
```

To keep narration smooth and gapless, the engine chunks long sentences on clause boundaries, pre-synthesizes the next chunk ahead of time, and hands off between two audio players so there's no silent gap between clips — all while the heavy text-to-speech FFI call runs on a persistent background isolate so the UI never janks.

---

## 🛠️ Tech stack

| Layer | What we use |
|---|---|
| **App** | [Flutter](https://flutter.dev) — one codebase for Android + iOS |
| **On-device TTS** | [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) running [Piper](https://github.com/rhasspy/piper) neural voices |
| **EPUB render + highlight** | [Readium](https://readium.org) via `flutter_readium` |
| **Audio playback** | `audioplayers` + `audio_service` (background + lock-screen MediaSession) |
| **Library storage** | [Drift](https://drift.simonbinder.eu/) (SQLite) |
| **Sync highlighting** | Sentence-level, deterministic, and offline |

The default **Amy** voice ships with the app (~bundled); optional higher-quality voices are downloaded on demand and then run fully offline.

---

## 🚦 Status

Narrarr is a **working, device-tested Android app** — past research and POC, with the full v1 loop running end-to-end:

> import a DRM-free EPUB → read it in a real Readium reader → narrate it with an offline neural voice → **the current sentence highlights in sync and the page auto-follows** → background playback with lock-screen controls.

Verified on an Android emulator **and a real Pixel 8** (including EPUB import and on-demand voice download). iOS support and app-store / F-Droid distribution are still to come. Work is tracked as **[GitHub issues](../../issues)**.

---

## 🚀 Getting started

Narrarr isn't on an app store yet — for now you build and run it from source.

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.8`)
- **Android:** minSdk **24**, compileSdk **36**, NDK **27** (required by `sherpa_onnx` + `flutter_readium`)
- A connected Android device or emulator

### Run it

```bash
git clone <this-repo-url>
cd Narrarr

flutter pub get          # install dependencies
flutter run              # build & launch on your device/emulator
```

A sample book (*The Odyssey*) and the default voice are bundled, so you can hear the read-aloud loop immediately — then import your own DRM-free EPUBs from inside the app.

### Other useful commands

```bash
flutter analyze                       # lint
flutter test                          # run the test suite
flutter build apk                     # release Android build

# Regenerate Drift database code after editing lib/library/drift/
dart run build_runner build --delete-conflicting-outputs
```

---

## 🗺️ Roadmap

- ✅ EPUB import (DRM-free) + library
- ✅ Readium reader with font/size/spacing/theme
- ✅ Offline neural read-aloud (sherpa-onnx + Piper)
- ✅ Sentence-level synced highlighting + page auto-follow
- ✅ Background playback + lock-screen controls
- ✅ Download-on-demand higher-quality voices
- 🔜 iOS support
- 🔜 App-store / F-Droid distribution

Have an idea or hit a bug? [Open an issue](../../issues) — that's how the roadmap grows.

---

## 📖 Documentation

In-depth research and rationale (market gap, feasibility, architecture, legal) lives in **[`docs/research/`](docs/research/README.md)**:

1. [Product Vision](docs/research/01-product-vision.md)
2. [Market & Competition](docs/research/02-market-competitive-analysis.md)
3. [Technical Feasibility](docs/research/03-technical-feasibility.md)
4. [Architecture & Stack](docs/research/04-architecture-and-stack.md)
5. [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md)
6. [Sources](docs/research/sources.md)

---

## 🤝 Contributing

Contributions are welcome. The best place to start is the **[issues list](../../issues)** — pick one up, or open a new one to propose a feature or report a bug. A `flutter analyze` + `flutter test` run should pass before you submit changes.

---

## ⚖️ License & legal

- **License:** Narrarr is licensed under the **[GNU General Public License v3.0](LICENSE)**. This copyleft license fits the project's use of GPL-3.0 Piper tooling and keeps Narrarr (and any forks) free and open — see [Technical Feasibility](docs/research/03-technical-feasibility.md) and [Risks, Legal & Compliance](docs/research/05-risks-legal-compliance.md).
- Narrarr **only** opens DRM-free EPUBs you own. It does **not** remove DRM and is **not** a content store.
- The legal/compliance notes in the docs are good-faith research, **not legal advice**.

---

## 🙏 Acknowledgments

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) and [Piper](https://github.com/rhasspy/piper) for on-device neural TTS
- [Readium](https://readium.org) and `flutter_readium` for EPUB rendering
- [Atkinson Hyperlegible](https://brailleinstitute.org/freefont) by the Braille Institute — accessible typography, free for everyone

<div align="center">

**Built for everyone who just wants to be read to — from the books they already own.**

</div>
