# Phase 1 — Manual Verification Checklist

*Run these on a device/emulator after the Phase 1 build. Code is analyze- and unit-test-clean and launches; these are the human-in-the-loop checks deferred during development.*

## Library & import
- [ ] App opens to **Your Library** with the bundled **The Odyssey / Homer**.
- [ ] **Add book** → pick a real **DRM-free EPUB** → it appears (title/author) and opens.
- [ ] Add a **DRM-protected** EPUB → clear rejection message, not added.
- [ ] Add a **corrupt/non-EPUB** file → clear rejection, not added.
- [ ] **Remove** (overflow menu) an imported book → removed, **Undo** restores it; the sample's Remove is disabled.

## Reader + read-aloud
- [ ] Open a book → first chapter renders; **Listen** → neural narration with the **yellow synced highlight** and auto page-follow.
- [ ] Highlight stays locked to audio across several sentences (no drift).

## Reading settings (text-format button)
- [ ] **Font**: switch to **Atkinson Hyperlegible**, Serif, Sans, Publisher → reader text updates live.
- [ ] **Text size** −/+ and **Line spacing** slider change the page live.
- [ ] **Page theme** Light / Sepia / **Dark** → page recolors; in Dark, the highlight + text remain readable.

## Persistence
- [ ] Read partway, go **back** to the library, reopen the book → resumes near the same place.
- [ ] Fully **restart the app** → reading position **and** reading settings are retained.

## Accessibility (TalkBack)
- [ ] Library tiles announce **title + author** (cover letter is not read aloud).
- [ ] Reader **Listen**, **Reading settings**, and book **options** controls announce meaningful labels.
- [ ] Increase system font size → app text scales without clipping.

## Known issue to confirm
- [ ] **Cold-start ANR (emulator):** first launch showed an "isn't responding" dialog that cleared on Wait — `Displayed +18s`, heavy kernel/page-fault time in debug mode, with the old spike app also running. Likely emulator cold-start + the **80 MB bundled voice asset** inflating startup. Confirm on a **real device** and in a **release build**; Phase 4 download-on-demand (un-bundling the voice) should remove the asset-size contributor. If it persists, move the sample-seed asset work fully off the first-frame path.

## Offline & device (carryover)
- [ ] After the voice is extracted, enable **airplane mode** → reading + narration still work.
- [ ] **Real mid-range Android** (from the spike findings, still open): Piper RTF, tap latency, long-clip behavior, thermals over a long session.

> Anything that fails here → file it as the first items for Phase 1 polish before moving to Phase 2.
