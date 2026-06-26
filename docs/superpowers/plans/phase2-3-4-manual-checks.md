# Combined Manual Verification — Phases 2, 3 & 4

*One device checklist for everything deferred during Phases 2 (background read-aloud), 3 (synced highlighting / sync layer), and 4 (voices, accessibility, onboarding). All three phases are code-complete: `flutter analyze` is clean, **67/67 unit tests pass**, and the debug APK builds. The items below are the human-in-the-loop and device-only checks — background audio, real hardware behaviour, screen-reader speech, real network downloads, and the `flutter_readium` native bridge can only be confirmed on a device/emulator.*

> Run on a real **mid-range Android** where noted (every timing/thermal/latency claim from the POC and spikes is emulator-grade until confirmed on real hardware). Anything that fails becomes the first polish work before Phase 5 (beta & distribution).

---

## Session 1 — emulator pass (2026-06-26, Android 12 / API 32 x86)

Driven via Maestro on `emulator-5554`; functional items below confirmed. Audio quality, real-hardware behaviour, and network downloads still pending a physical device.

**Bugs found & fixed (commit `80cadf2`):**
- 🔴 **Blocker:** `MainActivity` was a plain `FlutterFragmentActivity`, so `audio_service`'s `AudioService.init` threw and the reader hung on "Opening book…" for every book. Fixed → extends `AudioServiceFragmentActivity`. (Not caught by unit tests — no real platform channel.)
- 🟠 **Regression:** the Reading-settings sheet overflowed (132px) and wasn't scrollable after Phase 4 added the dyslexia sliders, clipping the word/paragraph sliders and the Page theme selector. Fixed → `isScrollControlled` + `SingleChildScrollView`.

**Verified on emulator:** book persistence + restored reading position; reader renders EPUB; Listen starts narration; in-app transport bar (prev/play-pause/next/stop); Now-Playing notification w/ title+author; notification pause ⇄ in-app sync; resume; stop dismisses bar; **tap-to-seek**; **skip-next/prev**; sentence highlight + advance; onboarding once; Settings → Voices/Accessibility/About; Voices catalog (amy-low Active + 2 downloadable w/ sizes); dyslexia spacing sliders apply live; Atkinson Hyperlegible default.

**Still pending (your ears / a real device):** audio quality + gapless + no-drift-over-chapter; pause/resume *same-sentence* fidelity; audio focus (call / other app / duck / headphone unplug); real lock-screen + long backgrounded session; TalkBack double-speak + focus order; thermal/battery/latency/RTF on mid-range Android; cross-chapter narration; messy-EPUB skip of footnotes/captions; empty-library + bad-file import states.

## Session 2 — voice download wired & verified (2026-06-26)

The pre-ship catalog gap is **resolved**: downloads now point at the sherpa-onnx `tts-models` release tarballs (`.tar.bz2`), with real SHA-256 checksums and sizes measured from the assets. The extractor decompresses bzip2 transparently (`extractVoiceTar` detects the `BZh` magic). Verified end-to-end on the API-32 emulator: **Download Ryan (medium) over network → SHA-256 verify → bz2 decompress → extract 392 files → "Use" activates it (persisted) → reader re-inits on the downloaded model → narrates with synced highlight, no errors.** tap-to-seek and skip-next/prev also confirmed working (manual).

- ✅ Voices lists amy-low (bundled, Active) + 2 downloadable with sizes.
- ✅ Download over network → installed → **Use** makes it Active.
- ⚠️ **Polish:** download fetches the whole 64 MB into memory and runs SHA-256 + bzip2 decode on the **UI isolate** — visibly janks ("Skipped frames", frozen spinner during extract). Move to a background isolate / streamed hashing before shipping. Functionally correct.
- ⏳ Still device-only: airplane-mode offline *after* download (on-device synth makes this near-certain, but untested); long-press delete; interrupted-download error + resume-from-`.part`.

---

## Session 3 — emulator batch (a) + Pixel 8 (b), 2026-06-26 — AUTHORITATIVE STATUS

This block supersedes the per-item checkboxes below as the current source of truth.

**Verified on real Pixel 8 (owner):** audio quality, gaplessness & **no drift over a chapter**; **lock-screen** playback + controls; **long backgrounded** session; **audio-focus** interruptions — phone call / other app / duck / **headphone unplug** (so `audioplayers` and `audio_session` don't fight for focus); page-follow not jumpy; tap-to-seek fidelity; **EPUB import**. → Core experience confirmed good on device.

**Verified on emulator this session:** **cold-start** with no ANR; **airplane-mode** narration fully offline (bundled voice); **failed download** shows "Download failed. Tap to retry." + Retry.

**Verified earlier (Sessions 1–2):** narration start + Now-Playing notification (title+author); mini-player transport + notification⇄in-app sync; skip-next/prev; sentence highlight + advance; **voice download end-to-end** (network → SHA-256 verify → bz2 → extract → activate → narrate); voices list/activate; dyslexia spacing (live); onboarding-once; settings/about.

**Deferred by decision:** thermal / battery / RTF over long sessions (#13) — left to real-world use, fix-as-we-go.

**STILL OPEN (small, none blocks the core v1 loop):**
- Cross-chapter narration continuing into the next chapter (#53)
- Messy-EPUB: skips footnotes/captions, no false breaks like "Dr. Smith" (#54–55); large-book load (#56)
- Timing-cache re-listen: tap-to-seek before play / no re-measure / voice-switch re-measure (#72–74)
- Voice long-press **delete** UI (#84) — covered by unit tests; UI not driven (model was cleared via app-data reset)
- Failed-download **resume-from-`.part`** (#85) — code present, not exercised
- **TalkBack**: no double-speak, readable when stopped, labels/focus/48dp (#89–91)
- Empty-library + bad-file **import-error** states (#98)

Best cleared opportunistically — TalkBack and a messy/multi-chapter EPUB on the Pixel, or a short focused follow-up.

---

## PHASE 2 — Background read-aloud

### Background playback & lock-screen (core of Phase 2)
- [ ] Open a book → **Listen** → narration starts; a **Now-Playing notification** appears with title + author.
- [ ] **Lock the screen** → narration keeps playing; lock-screen shows transport controls.
- [ ] Notification/lock-screen **play-pause, next, previous, stop** all work and stay in sync with the in-app bar.
- [ ] **Home button / background the app** → narration continues (foreground service alive; look-ahead isn't starved over a long locked session — challenge #3).

### Transport controls (in-app)
- [ ] Mini-player bar appears when narration is active: **prev / play-pause / next / stop**.
- [ ] **Pause** then **resume** continues the same sentence (no restart, no skipped audio).
- [ ] **Skip-next / skip-previous** jump one sentence and keep playing gaplessly.

### Audio focus & interruptions (challenge #9)
- [ ] **Phone call** mid-narration → pauses; after the call → **resumes**.
- [ ] **Another app plays audio** (e.g. a video) → narration pauses/resumes appropriately.
- [ ] A transient **navigation/notification prompt** → narration **ducks** then restores, rather than hard-stopping.
- [ ] **Unplug headphones / disconnect Bluetooth** → narration **pauses** (doesn't blast the speaker).
- [ ] ⚠️ **Focus interplay:** `audioplayers` also manages Android audio focus by default; confirm it and `audio_session` don't double-handle (double-pause, or fail to resume). If they fight, set the `audioplayers` `AudioContext` to defer focus to `audio_session`.

### Whole-book narration (challenges #4, #6)
- [ ] Narration **crosses chapter boundaries** automatically and continues into the next chapter (page follows).
- [ ] On a **messy real EPUB**, the narrator **skips** footnotes, figure captions, tables, nav/TOC, and page numbers.
- [ ] No false sentence breaks mid-name ("Dr. Smith", "Mr. Jones", initials).
- [ ] A **large book** narrates without excessive memory use or stutter at load.

---

## PHASE 3 — Sentence-level synced highlighting (sync layer)

### Synced highlight & page-follow (the product's reason to exist)
- [ ] The **spoken sentence highlights** as it plays, with **no drift across a whole chapter** (highlight stays locked to the audio).
- [ ] The page **auto-follows** to keep the spoken sentence visible across page boundaries.
- [ ] ⚠️ **Page-follow jitter:** `flutter_readium` 0.1.0 exposes no visible-range/current-locator getter, so the reader navigates on every sentence (always-follow). Confirm this isn't visibly jumpy or fighting manual page turns. If it is, the fix is gating on a visible-range API (track upstream) or a debounce.

### Tap-to-seek
- [ ] **Select a sentence** in the reader → narration **seeks** to it and plays from there.
- [ ] ⚠️ **Selection→locator fidelity:** tap-to-seek is wired to `ReadiumReaderWidget.onTextSelected` and resolves the selected text to a sentence (exact → whitespace-normalized → contains). Confirm a normal selection reliably lands on the intended sentence on device; note any selections that fail to resolve (resolver returns no match → no-op, which is safe).

### Timing cache (re-listen fast path)
- [ ] **Re-open a chapter** you've already listened to with the same voice → tap-to-seek works **immediately, before pressing play** (timings loaded from the drift cache).
- [ ] A re-listen does **not re-measure** durations (timings are cached; only audio is re-synthesized — audio itself is intentionally not cached in v1).
- [ ] Switching the active voice and re-listening **re-measures** under the new voice id (no stale timings served).

---

## PHASE 4 — Voices, accessibility, onboarding

### Voice download & management (challenge #11)
- [ ] Settings → **Voices** lists amy-low (bundled, Active) plus the downloadable voices with sizes.
- [ ] **Download** a voice over the network → progress shows → it becomes **Installed**, then **Use** makes it Active.
- [ ] After download, **airplane mode** → the downloaded voice still narrates fully offline.
- [ ] **Long-press** a downloaded (non-bundled) voice → **deletes** it; if it was active, the app falls back to amy-low.
- [ ] A **failed/interrupted download** shows an inline error and **Retry**; retry **resumes** from the partial `.part` file rather than restarting.
- [x] ✅ **Catalog wiring (RESOLVED — see Session 2):** download URLs now point at the sherpa-onnx `tts-models` release `.tar.bz2` bundles with real SHA-256 checksums and measured sizes; the extractor decompresses bzip2 transparently. Verified end-to-end on the emulator (download → verify → extract → activate → narrate). Remaining polish: the download/verify/decode runs on the UI isolate and janks — move off the main isolate before shipping.

### Accessibility (challenge #12)
- [ ] With **TalkBack ON**, start narration → the screen reader does **not** also read the page aloud over the app's voice (book content is excluded from the a11y tree while self-narrating).
- [ ] With TalkBack ON and narration **stopped**, the page **is** readable by TalkBack again.
- [ ] Transport controls, Listen button, settings, and voice actions are all **announced with clear labels** and have ≥48dp targets; focus order is sensible.
- [ ] **Dyslexia options:** the reader text settings expose letter / word / paragraph **spacing** sliders; increasing them visibly changes the page. Atkinson Hyperlegible remains the default font.

### Onboarding, settings, states
- [ ] **First launch** shows the onboarding intro (what Narrarr is + privacy promise); **Get started** dismisses it.
- [ ] **Relaunch** the app → onboarding does **not** show again.
- [ ] Library **Settings** (gear) → Voices, Accessibility note, and **About** (version, "fully offline / no telemetry") are reachable.
- [ ] **Empty library** state and **import errors** (DRM/corrupt file) read clearly (carried from Phase 1).

---

## Carryover — still open from the spike/POC findings
- [ ] **Real mid-range Android:** sustained Piper **RTF** (faster-than-realtime), tap latency, long-clip behaviour, and **thermal/battery over a long locked session** (challenge #13).
- [ ] **Airplane mode** after the voice is available → reading + narration fully offline (bundled voice day one; downloaded voices after their download).
- [ ] **Cold-start**: first Listen press loads the model without an ANR (Phase-1 note; players are now lazily constructed).

> Anything that fails here → first items for polish before **Phase 5 (beta & distribution)**: Google Play closed track, F-Droid reproducible build, license finalisation, store privacy disclosures.
