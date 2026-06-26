# Phase 2 — Manual Verification Checklist

*Run on a device/emulator after the Phase 2 build. Code is analyze-clean, 30/30 unit tests pass, and the debug APK builds; these are the human-in-the-loop checks deferred during development. Background playback, audio focus, and the audioplayers↔audio_session focus interplay are inherently device-only.*

## Background playback & lock-screen (the core of Phase 2)
- [ ] Open a book → **Listen** → narration starts; a **Now-Playing notification** appears with title + author.
- [ ] **Lock the screen** → narration keeps playing; lock-screen shows transport controls.
- [ ] Notification/lock-screen **play-pause, next, previous, stop** all work and stay in sync with the in-app bar.
- [ ] **Home button / background the app** → narration continues (foreground service stays alive, look-ahead isn't starved over a long locked session — challenge #3).

## Transport controls (in-app)
- [ ] Mini-player bar appears when narration is active: **prev / play-pause / next / stop**.
- [ ] **Pause** then **resume** continues the same sentence (no restart, no skipped audio).
- [ ] **Skip-next / skip-previous** jump one sentence and keep playing gaplessly.

## Audio focus & interruptions (challenge #9)
- [ ] **Phone call** mid-narration → pauses; after the call → **resumes**.
- [ ] **Another app plays audio** (e.g. a video) → narration pauses/resumes appropriately.
- [ ] A transient **navigation/notification prompt** → narration **ducks** (lowers) then restores, rather than hard-stopping.
- [ ] **Unplug headphones / disconnect Bluetooth** → narration **pauses** (doesn't blast the speaker).
- [ ] ⚠️ **Focus interplay:** `audioplayers` also manages Android audio focus by default; confirm it and `audio_session` don't double-handle (e.g. double-pause, or fail to resume). If they fight, set the `audioplayers` `AudioContext` to defer focus to `audio_session`.

## Whole-book narration (challenges #4, #6)
- [ ] Narration **crosses chapter boundaries** automatically and continues into the next chapter (page follows).
- [ ] On a **messy real EPUB**, the narrator **skips** footnotes, figure captions, tables, nav/TOC, and page numbers (doesn't read "forty-two" mid-sentence or recite a footnote).
- [ ] No false sentence breaks mid-name ("Dr. Smith", "Mr. Jones", initials).
- [ ] A **large book** narrates without excessive memory use or stutter at load.

## Voice manager
- [ ] First run still extracts the bundled amy voice and narrates (extraction relocated to `VoiceManager`, behaviour unchanged).

## Regression (must still hold from Phase 1)
- [ ] Reading position still persists across restart and font change.
- [ ] The existing yellow synced highlight still tracks the spoken sentence (Phase-1 completion-driven highlight; position-driven is Phase 3).

## Carryover (still open from the spike findings)
- [ ] **Real mid-range Android:** Piper RTF, tap latency, long-clip behaviour, thermals/battery over a long locked session.
- [ ] **Airplane mode** after the voice is extracted → reading + narration still fully offline.

> Anything that fails here → first items for Phase 2 polish before Phase 3 (position-driven synced highlighting).
