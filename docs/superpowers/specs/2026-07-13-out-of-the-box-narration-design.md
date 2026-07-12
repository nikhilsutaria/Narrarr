# Out-of-the-box narration — design

**Date:** 2026-07-13 · **Issues:** [#30](https://github.com/nikhilsutaria/Narrarr/issues/30), [#15](https://github.com/nikhilsutaria/Narrarr/issues/15) · **Milestone:** Out-of-the-box narration

## Goal

A fresh install narrates a book immediately — no model download required — and the
narration stack never gets into a state that only an app restart can fix. Neural
voices become a safe, opt-in upgrade: download, tap *Use*, keep listening from the
same sentence.

Two pieces, in dependency order:

1. **#30 — failure-safe neural engine lifecycle.** Init can fail (offline, corrupt
   model, interrupted download) and *recover in-process*; failures surface as
   messages, never as silence or chapter-skipping.
2. **#15 — system TTS as the default engine.** `SystemNarrator` backed by the
   platform TTS (`flutter_tts`), selectable alongside neural voices, default on a
   fresh prod install.

## Part 1 — engine lifecycle hardening (#30)

### `TtsSynthIsolate` (`lib/narration/tts_synth_isolate.dart`)

- **Propagate startup failure.** The isolate entry wraps `OfflineTts` construction
  in try/catch and sends an error message over the handshake port; `_onMessage`
  completes `_ready` with that error, so `start()` **throws** instead of hanging
  forever on a missing/corrupt model.
- **Single-flight `start()`.** Concurrent callers share one in-flight future and
  none returns before the ready handshake (today a second call returns
  immediately once `_isolate` is set, pre-ready).
- `dispose()` stays one-shot. Restartability is solved one level up: the narrator
  never reuses a disposed instance.

### `NeuralNarrator` (`lib/narration/neural_narrator.dart`)

- **Fresh `TtsSynthIsolate` per (re)init**, via an injectable `synthFactory`
  (tests pass a fake). This fixes the voice-switch poisoning: `setVoice()`
  disposes the old isolate and `init()` builds a new one.
- **Single-flight `init()`.** Concurrent calls await the same future. On failure
  the in-flight marker clears, the partial isolate is disposed, and `_inited`
  stays false — so the next attempt starts clean. `_inited = true` is only set
  after the synth is verifiably started.
- **Fail loudly in `speak()`.** The look-ahead cache stores the raw synthesis
  future (errors preserved, unhandled-error-silenced) instead of converting
  errors to empty clips; a synthesis failure therefore **throws out of
  `speak()`**. Legitimately empty synth output (e.g. punctuation-only sentence)
  still returns normally and skips that sentence only. `assert(_inited)` becomes
  a real `StateError` (asserts vanish in release — that's the silent path today).
- `getTemporaryDirectory()` becomes injectable so lifecycle tests run without
  platform channels.

### `NarrationController` (`lib/sync/narration_controller.dart`)

- The play loop wraps `engine.speak()` in try/catch. On error: stop the loop,
  reset `_playing`, record the error, notify. New API: `String? takeError()` —
  the reader's listener consumes it and shows a snackbar. No more silent loop
  death (nothing happens) or empty-clip sprint (chapter skipping).

### `DownloadingVoiceManager` (`lib/narration/voice_manager.dart`)

- **Single-flight per voice id:** concurrent `ensureAvailable()` calls for the
  same voice share one download future, so a second tap can't double-append to
  the `.part` file and corrupt it.

### Reader (`lib/reader/reader_screen.dart`)

- Listen FAB is **disabled while `_preparingNarrator`** (one tap = one init).
- `_startNarration` re-reads `VoiceSettings` before init, so a voice selected in
  Settings → Voices mid-session is applied without reopening the book.
- Controller errors surface as a snackbar via the existing narration listener.

## Part 2 — system TTS default (#15)

### `SystemNarrator` (new, `lib/narration/system_narrator.dart`)

Backed by `flutter_tts` behind a thin injectable adapter (`SystemTts` interface +
`FlutterTtsAdapter`), so the narrator logic is unit-testable without platform
channels. Honors the core contract — **`speak()` completes only when the
utterance finishes** — by completing on the adapter's completion callback.

- **Pause/resume:** native pause support varies by platform (Android's
  `TextToSpeech` has none), so pause = stop the current utterance while keeping
  the `speak()` future pending; resume = re-speak the same sentence from its
  start. Sentence-level granularity matches the app's sync model. The stop-cancel
  callback completes the pending future only for a real `stop()`, not a pause.
- `precache`/`preloadNext`: no-ops (system TTS streams internally).
- `lastUtteranceMs`: wall-clock measured per utterance (approximate; keys the
  timing table the same way).
- `init()`: cheap adapter setup; never downloads anything.

### Engine selection — `SwitchableTtsEngine` (new)

A `TtsEngine` that delegates every call to the active engine and can `use(next)`
(stop old → swap). `NarrationAudioHandler` construction wires
`SwitchableTtsEngine(system: SystemNarrator(), neural: NeuralNarrator(...))` —
the controller keeps its single `engine` reference; nothing else changes.

### Selection model & persistence

- A sentinel voice id **`system`** (`kSystemVoiceId`) joins the catalog surface.
  `VoiceSettings.activeVoiceId == 'system'` ⇒ system engine; any other id ⇒
  neural engine + that `VoiceConfig`.
- **Default:** prod (and unflavored tests) default to `system` — a fresh install
  narrates immediately. The QA flavor keeps defaulting to the bundled Amy so
  device QA of the neural path stays zero-setup.
- The reader resolves the selection on each Listen press and applies it through
  the switchable engine before `init()`.

### Voices screen

A pinned "System voice" tile at the top — always installed, no download, no
delete, "Uses your device's text-to-speech" — selectable like any other voice.
Timing caches key on voiceId `system` like any other voice.

## Error handling summary

| Failure | Before | After |
|---|---|---|
| Model download fails/offline | snackbar, retry OK | unchanged |
| Model load fails (corrupt) | infinite hang | `init()` throws → snackbar, retry works |
| Double-tap Listen during init | dead engine until restart | second tap disabled + single-flight init |
| Synth dies mid-chapter | silent chapter-skipping | playback stops + snackbar |
| Voice switch after playback | engine poisoned until restart | fresh isolate per init |
| Concurrent downloads | corrupt `.part` | shared single-flight download |

## Testing

All new tests follow the repo rule: no native code, fakes at the seams
(`FakeTtsEngine` pattern).

- **NeuralNarrator lifecycle:** failed-then-retried init; concurrent init
  single-flight (one `ensureAvailable`); dead-synth `speak()` throws;
  `setVoice()` uses a fresh isolate after dispose.
- **NarrationController:** engine error stops playback, sets the consumable
  error, doesn't fetch next chapters.
- **DownloadingVoiceManager:** two concurrent `ensureAvailable()` → one fetch.
- **SystemNarrator:** speak completes on completion callback; stop unblocks;
  pause keeps the future pending; resume re-speaks the same text; cancel during
  pause doesn't advance.
- **SwitchableTtsEngine:** delegation; `use()` stops the old engine.
- **Settings/catalog:** system default in prod, Amy in QA; round-trip persists.

## Out of scope

- Shrinking the sherpa-onnx native runtime out of the base APK (tracked with
  F-Droid, #6).
- Download progress UI beyond the existing indeterminate state.
- Position-driven (Phase 3) sync — the completion-driven model is unchanged.
