# Phase 4 — Polish & Accessibility Design

*Created 2026-06-25. Implements Phase 4 of the [MVP design spec](2026-06-25-narrarr-mvp-design.md) §7. Builds on Phase 3 (sync layer).*

## 1. Goal

Make Narrarr usable by a stranger with no guidance: optional **voice downloads** with storage management, a **screen-reader-friendly** experience that resolves the TalkBack-vs-narration conflict, **dyslexia-friendly** reading options, plus **onboarding**, an app **settings/about** surface, and clean **empty/error states**.

**Exit criteria** (MVP spec §7, Phase 4): a stranger can install, import a book, download a voice, and use it accessibly without guidance.

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Voice strategy | **Bundle amy-low + optional downloads** (user-approved) | Works offline on first run; quality voices are opt-in. MVP spec §11. |
| Download source | **Hugging Face `rhasspy/piper-voices`** direct file URLs | Open, no account, no proprietary CDN (F-Droid-friendly). |
| HTTP client | **`dart:io HttpClient`** (no new dependency) | Avoids a proprietary/heavy dep; supports range requests for resume. |
| Integrity | **SHA-256 checksum verify** before a download counts as installed | MVP spec #11 (verify); never load a corrupt model. |
| Dyslexia support | **Atkinson Hyperlegible (already default) + letter/word/paragraph spacing controls** | Bundled OFL font + `EPUBPreferences` spacing fields; no risky webview @font-face work. |
| Screen-reader conflict | **Suppress the book content from the a11y tree while self-narrating; keep transport controls accessible** | Prevents TalkBack and app narration both speaking the page (#12). |

## 3. Components (one responsibility each)

### 3.1 Voice catalog & descriptor — `lib/narration/voice_manager.dart` (extend)
Extend `VoiceConfig` so a voice can be **bundled** or **downloadable**:

```dart
class VoiceConfig {
  final String id;          // 'vits-piper-en_US-amy-low'
  final String displayName; // 'Amy (low)'
  final String modelFile;   // 'en_US-amy-low.onnx'
  final String? asset;      // bundled tar asset path, or null if download-only
  final String? url;        // download tar URL, or null if bundled-only
  final String? sha256;     // expected checksum of the tar (download voices)
  final int sizeBytes;      // approx download size, for the UI
  bool get isBundled => asset != null;
}
```

`VoiceCatalog` is a static list: `amyLow` (bundled, default) + `ryanMedium` and `amyMedium` (downloadable from Hugging Face, with `url`/`sha256`/`sizeBytes`).

> **Checksum sourcing:** `sha256` is **nullable**. The download *verification mechanism* is the v1 deliverable and is unit-tested against a fixture with a computed checksum. The real catalog entries' checksums require downloading the actual Hugging Face tars (network), so they are populated as a follow-up when network is available; until then a null `sha256` downloads without verification and logs a warning. Filling the real checksums is a manual-checks item, not a code change.

### 3.2 `DownloadingVoiceManager` — `lib/narration/voice_manager.dart`
Implements `VoiceManager` and adds management ops. For a **bundled** voice it delegates to the existing `BundledVoiceManager`. For a **downloadable** voice:
- `ensureAvailable(voice)`: if already extracted → return dir; else **download** the tar (resumable), **verify SHA-256**, **extract**, return dir.
- `isInstalled(voice)`, `installedSize()`, `delete(voice)` for storage management.
- A `Stream<double> progress(voiceId)` (0..1) for the UI; download writes to a `.part` file and resumes via an HTTP `Range` header.

Testability: the network fetch is an injected `Future<HttpClientResponse> Function(Uri, {int? rangeStart})` (or a simpler injected byte-fetcher), and the base dir is injectable — mirrors `BundledVoiceManager`. Tests use a fake fetcher serving fixture tar bytes with a known checksum; checksum-mismatch and resume-from-partial are covered.

### 3.3 Active-voice persistence — `lib/narration/voice_settings.dart`
`VoiceSettings { String activeVoiceId }` + `VoiceSettingsStore` (JSON file in app-support, mirroring `ReaderSettingsStore`). Default `vits-piper-en_US-amy-low`. Selecting a voice persists the id and **evicts the previous voice's cached timings is unnecessary** (timings are voice-keyed and simply miss) — but switching **does** call `TimingRepository.evictVoice(oldId)` only when the user *deletes* a voice, to reclaim space.

### 3.4 Engine voice wiring — `lib/narration/neural_narrator.dart` (extend)
`NeuralNarrator` holds a mutable active `VoiceConfig` (default amy-low) and gains `Future<void> setVoice(VoiceConfig)` that, if the voice differs, stops, re-inits the synth isolate against the new model dir (via the `VoiceManager`), and updates `name`. The reader passes the persisted active voice as the controller's `voiceId` (so timings stay correctly keyed). Switching voice while the engine is uninitialised is a no-op beyond recording the selection.

### 3.5 Voice management UI — `lib/narration/voice_screen.dart`
A screen listing catalog voices: each shows display name, size, and state (Active / Installed / Download / Downloading <pct> / Delete). Bundled amy is always Installed and cannot be deleted. Selecting an installed voice makes it active. Download errors surface inline with retry. Reached from the app settings surface.

### 3.6 Accessibility — `lib/a11y/`
- **Screen-reader detection + policy** — `lib/a11y/a11y_policy.dart`: a pure `bool shouldExcludeContentSemantics({required bool screenReaderOn, required bool narrating})` returning `screenReaderOn && narrating`. Unit-tested. The reader wraps the book content in `ExcludeSemantics(excluding: policy)` so TalkBack does not read the page while the app narrates it; transport controls stay in the tree, labelled.
- **Semantic-label audit** — ensure every control (Listen FAB, transport buttons, settings, voice actions, import) has a `semanticLabel`/`tooltip`. Most exist from Phase 1–3; fill gaps.
- **Dyslexia options** — add `letterSpacing`, `wordSpacing`, `paragraphSpacing` to `ReaderSettings` (mapped to `EPUBPreferences`) with sliders in the settings sheet. Atkinson Hyperlegible remains the accessibility-first default font.

> Actual TalkBack speech behaviour, focus order on a device, and font rendering in the Readium webview are **device-only** and go to manual checks. The policy logic and settings plumbing are unit-tested here.

### 3.7 Onboarding — `lib/onboarding/onboarding_screen.dart`
A first-run, dismissible 2–3 panel intro: what Narrarr does, the privacy promise (offline, no account, no telemetry), and "import a book to start." A `bool seenOnboarding` flag persists (reuse the settings-store pattern). `app.dart` shows onboarding before the library on first launch only.

### 3.8 Settings / About — `lib/settings/settings_screen.dart`
A top-level settings surface (from the library app bar): entries for **Voices** (3.5), **Reading defaults** (font/size/theme/spacing), **Accessibility** (note on TalkBack behaviour), and **About** (version, "fully offline / no telemetry", open-source license note — license finalised in Phase 5, referenced here).

### 3.9 Empty / error states
- Library empty → friendly "Import your first book" call to action (audit/confirm existing).
- Import failure (DRM/corrupt) → clear message (exists from Phase 1; confirm copy).
- Voice download failure → inline error + retry (3.5).
- Book open failure → existing message; confirm it reads well.

## 4. Data flow: download & use a voice
Settings → Voices → tap Download on *ryan-medium* → `DownloadingVoiceManager.ensureAvailable` streams progress → verify SHA-256 → extract → mark Installed → tap to make Active → `VoiceSettingsStore` persists the id → next narration: reader passes `activeVoiceId` to the controller and `NeuralNarrator.setVoice(ryanMedium)` re-inits the isolate → timings are cached under the new voice id.

## 5. Out of scope (explicit)
- ❌ iOS-specific voice policy / Core ML (fast-follow).
- ❌ Speed control UI (sync seam exists; spec §6 fast-follow).
- ❌ Word-level highlighting (stretch).
- ❌ A large voice catalog (one bundled default + two optional downloads).
- ❌ OpenDyslexic as a Readium-webview @font-face (risky; Atkinson + spacing covers dyslexia for v1).
- ❌ License finalisation / store listing / F-Droid build (Phase 5).

## 6. Testing strategy
- **Unit (no device):**
  - `DownloadingVoiceManager`: download→verify→extract happy path; **checksum mismatch rejects** (and removes the bad file); resume from a partial `.part`; `delete`/`isInstalled`/`installedSize`; bundled voice delegates to `BundledVoiceManager`.
  - `VoiceCatalog`/`VoiceConfig`: `isBundled`, lookups.
  - `VoiceSettingsStore`: round-trip + default.
  - `a11y_policy`: truth table for content-semantics exclusion.
  - `ReaderSettings`: spacing fields (de)serialise + map to `EPUBPreferences`.
- **Widget (optional, where cheap):** voice screen renders the three states; onboarding advances and sets the seen flag.
- **Build:** `flutter analyze` clean; full `flutter test` green; debug APK builds.
- **Device (manual checks):** real download over network + airplane-mode offline after; TalkBack double-speak resolved; dyslexia spacing/font legibility; onboarding first-run only; thermal/battery/latency over a long session (carryover #13).

## 7. Definition of Done
- [ ] `VoiceConfig` supports bundled + downloadable; `VoiceCatalog` has amy-low (bundled) + 2 downloadable.
- [ ] `DownloadingVoiceManager` downloads, **verifies SHA-256**, extracts, resumes, deletes; bundled delegates; all unit-tested.
- [ ] Active voice persists; `NeuralNarrator.setVoice` re-inits; timings keyed by the active voice.
- [ ] Voice management screen: install / select / delete / progress / error+retry.
- [ ] Screen-reader policy excludes book content from the a11y tree while self-narrating; controls labelled; policy unit-tested.
- [ ] Dyslexia spacing options (letter/word/paragraph) in settings, mapped to `EPUBPreferences`.
- [ ] Onboarding shown on first run only; app settings/about surface present; empty/error states audited.
- [ ] `flutter analyze` clean; all unit tests green; debug APK builds.
- [ ] No regression to Phase 1–3 (reader, narration, background, sync).

## 8. Open items carried to manual checks
Real voice download + checksum on device; airplane-mode offline after download; TalkBack behaviour (double-speak, focus order); dyslexia legibility; onboarding-once; long-session thermal/battery/latency on a real mid-range Android. All recorded in the combined Phase 2/3/4 manual-checks doc.
