# Contributing to Narrarr

First off — thank you. Narrarr exists to let people **listen to the DRM-free books they already own**, for free and fully offline, with accessibility as a first-class concern. Contributions of every kind are welcome: code, bug reports, documentation, testing on real devices, accessibility feedback, and ideas.

This guide explains how to get involved productively. It's a living document — if something here is unclear or out of date, that itself is a great first contribution.

## Table of contents

- [Code of conduct](#code-of-conduct)
- [Ways to contribute](#ways-to-contribute)
- [Before you start: issues first](#before-you-start-issues-first)
- [Development setup](#development-setup)
- [Project layout](#project-layout)
- [Coding guidelines](#coding-guidelines)
- [Testing](#testing)
- [Commits & pull requests](#commits--pull-requests)
- [Reporting bugs & requesting features](#reporting-bugs--requesting-features)
- [License](#license)

## Code of conduct

Be respectful, inclusive, and constructive. We follow the spirit of the [Contributor Covenant](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Harassment or exclusionary behavior isn't tolerated. Given the project's audience includes people with disabilities, please be especially mindful and welcoming in discussions about accessibility.

## Ways to contribute

You don't have to write code to help:

- 🐛 **Report bugs** — especially anything that crashes, mis-narrates, or breaks on a real device.
- 💡 **Propose features** — open an issue describing the problem you want solved.
- 📖 **Improve docs** — fix typos, clarify setup steps, expand the README or research docs.
- ♿ **Accessibility feedback** — test with TalkBack/screen readers, large fonts, or as a dyslexia/low-vision reader and tell us what's awkward.
- 🧪 **Device testing** — run the app on hardware we don't have and report what works. Some paths (the neural voice engine, the Readium reader) can't be unit-tested and rely on real-device verification.
- 🗣️ **Voices & languages** — suggest additional offline voices or localization.
- 🧑‍💻 **Code** — pick up an open issue and send a pull request.

New here? Look for issues labeled [`good first issue`](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) or [`documentation`](../../issues?q=is%3Aissue+is%3Aopen+label%3Adocumentation).

## Before you start: issues first

Work is tracked entirely as **[GitHub issues](../../issues)**.

- **Found a bug or have an idea?** Open an issue first so we can discuss it before code is written. This avoids duplicate or wasted effort.
- **Want to work on something?** Comment on the issue so it can be assigned to you and others don't pick up the same task.
- For anything more than a trivial fix, please wait for a quick 👍 on the approach before investing a lot of time — it saves everyone a painful "thanks, but we went a different way."

## Development setup

Narrarr is a Flutter app (one codebase at the repo root). See the [README → Getting started](README.md#-getting-started) for the full version; in short:

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart `^3.8`)
- **Android:** minSdk **24**, compileSdk **36**, NDK **27** (required by `sherpa_onnx` + `flutter_readium`)
- A connected Android device or emulator (iOS support is in progress)

### Run it

```bash
git clone https://github.com/nikhilsutaria/Narrarr.git
cd Narrarr

flutter pub get          # install dependencies
flutter run              # build & launch on your device/emulator
```

A sample book and the default voice are bundled, so the read-aloud loop works immediately.

### Database codegen

The library store uses [Drift](https://drift.simonbinder.eu/) (SQLite). After editing anything under `lib/library/drift/` (tables, DAOs, `@DataClassName`), regenerate the generated code — **never hand-edit `*.g.dart`**:

```bash
dart run build_runner build --delete-conflicting-outputs
# or, while iterating:
dart run build_runner watch
```

## Project layout

A quick map (see the [README → How it works](README.md#-how-it-works) for the architecture):

- `lib/reader/` — the Readium reader, HTML→sentence segmenter, reading-position handling.
- `lib/narration/` — the TTS stack: the `TtsEngine` interface, the neural (sherpa-onnx + Piper) engine, the background synth isolate, the `audio_service` handler, and voice management.
- `lib/sync/` — the controller that drives playback over a sentence list and keeps the highlight locked to the audio.
- `lib/library/` — EPUB import (DRM-free only) and the SQLite-backed library store.
- `lib/onboarding/`, `lib/settings/`, `lib/a11y/`, `lib/ui/` — first-run, settings, accessibility policy, theming.
- In-depth rationale (market, feasibility, architecture, legal) lives in [`docs/research/`](docs/research/README.md).

## Coding guidelines

- **Match the surrounding code.** Follow the existing naming, structure, and comment style. Lint with `flutter_lints` (see `analysis_options.yaml`).
- **Accessibility is a product requirement, not a nice-to-have.** The audience includes dyslexia, low-vision, and print-disability readers. Respect `lib/a11y/a11y_policy.dart` and the bundled Atkinson Hyperlegible font; provide semantic labels, ≥48dp touch targets, and don't rely on color alone.
- **DRM & legal posture.** Narrarr only opens DRM-free EPUBs the user owns. **Never** add anything that removes or circumvents DRM, and don't turn the app into a content store. Note that Piper's tooling is GPL-3.0 (see [`docs/research/`](docs/research/README.md)).
- **Keep narration's core invariant.** `TtsEngine.speak()` must complete only when the utterance has actually finished playing (or `stop()` interrupts it) — this is what keeps the highlight in sync. Don't break it.
- **Keep the cold-start path light.** The neural model loads lazily on first play; don't move heavy work to launch.

## Testing

A green `flutter analyze` **and** `flutter test` is required before any change is merged.

```bash
flutter analyze                        # lint — must be clean
flutter test                           # full unit/widget suite
flutter test test/segmenter_test.dart  # a single file
flutter test --name "substring"        # tests matching a name
```

Conventions:

- **Tests avoid native code.** There's no audio or FFI in the test suite. Exercise the controller/handler with `test/support/fake_tts_engine.dart` (a `TtsEngine` double whose `speak` stays pending until the test resolves it). Mirror that pattern for new TTS-dependent tests.
- **Prefer pure, testable logic.** Where possible, factor logic out of platform-bound widgets/plugins so it can be unit-tested (see `lib/sync/book_position.dart`, `lib/reader/chapter_titles.dart`).
- **Native/device paths.** The neural engine and the Readium-backed reader screen can't be unit-tested. If you change those, please **smoke-test on a real device** and say so in your PR (e.g. cold-launch play/pause, voice download, resume).
- Add or update tests for any behavior you change.

## Commits & pull requests

1. **Branch from `main`** with a descriptive name: `feature/…`, `fix/…`, `docs/…`, or `chore/…`.
2. **Keep the PR focused** — one logical change. Smaller PRs get reviewed faster.
3. **Reference the issue** it addresses (e.g. `Closes #123`).
4. **Write clear commit messages** — a concise summary line, then a body explaining the *why* if it isn't obvious.
5. **Make sure `flutter analyze` and `flutter test` pass**, and note any manual device testing you did.
6. **Open the PR against `main`** and describe what changed and how you verified it.

We'll review as soon as we can. Expect questions or change requests — that's a normal part of the process, not a rejection. Be ready to iterate, and please be patient: this is a small project.

## Reporting bugs & requesting features

Open an [issue](../../issues/new/choose) and include, where relevant:

- What you expected vs. what happened.
- Steps to reproduce.
- Device / Android version, and whether it's a debug or release build.
- Logs or screenshots if you have them.

For EPUB-specific bugs, remember Narrarr only handles **DRM-free** EPUBs — please don't attach or describe DRM-protected files.

## License

Narrarr is licensed under the **[GNU General Public License v3.0](LICENSE)**. By contributing, you agree that your contributions will be licensed under the same GPL-3.0 terms.

---

Thanks again for helping make reading more accessible for everyone. 💜
