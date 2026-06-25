# Phase 3 — Sentence-Level Synced Highlighting (Sync Layer) Design

*Created 2026-06-25. Implements Phase 3 of the [MVP design spec](2026-06-25-narrarr-mvp-design.md) §7. Builds on Phase 2 (background read-aloud).*

## 1. Goal

Make the spoken sentence highlight with **no drift across a whole chapter**, pages **follow automatically**, and **tapping a sentence seeks narration there** — the product's core immersion loop. Cache per-chapter timings so re-listening doesn't re-synthesize. Leave the door open for speed control and word-level highlighting without a rewrite.

**Exit criteria** (from MVP spec §7, Phase 3):
- Spoken sentence highlighted with no drift across a whole chapter.
- Pages follow automatically to keep the spoken sentence visible.
- Tapping a sentence seeks narration to it.
- Timings cached in `drift`; re-listening a chapter does not re-synthesize.
- Speed-control-ready (timing table + length-scale seam present, not wired to UI).

## 2. Locked decision: pragmatic hybrid (not full position-driven)

The MVP spec §2 named a *position-driven* sync model. The shipped Phase 1/2 highlight is **completion-driven**: `TtsEngine.speak()` resolves on real audio-end, then the controller advances the highlight. That path has **zero drift by construction** (the highlight is locked to the audio, not to a predicted clock).

**Decision (user-approved 2026-06-25):** keep the completion-driven highlight for live playback, and **add** a measured timing table on top. We do not rebuild the working highlight around a player position stream.

| Concern | Mechanism |
|---|---|
| Live highlight (no drift) | Completion-driven advance — **unchanged** from Phase 2. |
| Seek / tap-to-seek | Timing table → resolve target sentence index → `controller.playFrom(index)`. |
| Skip sentence | Already index-based; unchanged. |
| Re-listen without re-synth | Timings persisted in `drift`, keyed by `(bookId, chapterHref, voiceId)`. |
| Speed control (later) | Table stores measured `startMs/endMs`; a `lengthScale` seam exists on the synth isolate. Adding speed = re-scale + re-synth, not a rewrite. |
| Word-level (later) | Same table, finer rows; the position→index lookup generalizes to position→token. |

**Why this over full position-driven:** for *sentence-level* highlighting the completion signal is strictly more accurate than a predicted clock, and it already works and ships. Full position-driven buys precise mid-sentence seeking and word-level karaoke — both out of v1 scope (spec §6). We build the table (the durable artifact those features need) now, without risking the proven highlight.

## 3. Architecture (what's new)

```
NeuralNarrator (Phase 2)              NEW in Phase 3
  measures audioMs per sentence  ─────►  reports duration after each speak()
                                            │
NarrationController (Phase 2)               ▼
  completion-driven advance  ───────►  builds ChapterTimings incrementally
                                            │
                                            ▼
                                       SyncTable  (sentence ⇄ ms, position→index)
                                            │
                          ┌─────────────────┼─────────────────┐
                          ▼                 ▼                 ▼
                  TimingRepository    tap-to-seek        page-follow
                  (drift cache)       (reader → index)   (goToLocator, jitter-free)
```

### 3.1 Timing model — `lib/sync/sentence_timing.dart`
Pure data, no Flutter deps (unit-testable).

```dart
/// One sentence's place in a chapter's audio timeline.
class SentenceTiming {
  final int index;       // sentence index within the chapter
  final int startMs;     // cumulative offset where this sentence begins
  final int durationMs;  // measured audio length
  int get endMs => startMs + durationMs;
}

/// A chapter's full timeline, built from measured durations.
class ChapterTimings {
  final String chapterHref;
  final String voiceId;            // invalidation key — timings are voice-specific
  final List<SentenceTiming> sentences;
  int get totalMs;
  /// Position-driven lookup: which sentence is playing at [ms]. O(log n).
  int indexAt(int ms);
  /// Start offset of a sentence (for seek-by-position / scrub readiness).
  int startMsOf(int index);
}
```

`ChapterTimings` is the **single source of truth** for the position↔index mapping. `indexAt` is the position-driven primitive the spec asked for; today it powers seek, and it is the hook speed-control and a scrubber will reuse.

### 3.2 Duration capture — surface what the engine already measures
`NeuralNarrator._Prepared.audioMs` is already computed. Surface it without changing the playback contract:

- `TtsEngine` gains `int get lastUtteranceMs;` (ms of the most recently completed `speak`, or 0). `NeuralNarrator` returns the played `_Prepared.audioMs`; `FakeTtsEngine` returns a deterministic stub for tests.
- `NarrationController`, after each `speak()` completes, appends a `SentenceTiming` (cumulative `startMs`, measured `durationMs`) to an in-progress `ChapterTimings`. On chapter roll-over it finalizes the chapter's timings and starts the next.
- The controller exposes `ChapterTimings? get currentTimings` and a `void Function(ChapterTimings)? onChapterTimed` callback so the reader can persist a finished chapter.

This keeps the completion-driven loop intact — timing capture is a passive observer of it.

### 3.3 Persistence — `drift` (`TimingRepository`)
New table; bump `LibraryDatabase.schemaVersion` 1 → 2 with an additive migration (create the new table only; `Books` untouched).

```dart
@DataClassName('SentenceTimingRow')
class SentenceTimings extends Table {
  TextColumn get bookId => text()();
  TextColumn get chapterHref => text()();
  TextColumn get voiceId => text()();
  IntColumn  get sentenceIndex => integer()();
  IntColumn  get startMs => integer()();
  IntColumn  get durationMs => integer()();
  @override
  Set<Column> get primaryKey => {bookId, chapterHref, voiceId, sentenceIndex};
}
```

`TimingRepository`:
- `Future<ChapterTimings?> load(bookId, chapterHref, voiceId)` — returns cached timings or null.
- `Future<void> save(bookId, ChapterTimings)` — upsert a finished chapter (single batch).
- `Future<void> evictVoice(voiceId)` — drop all timings for a voice (used by Phase 4 voice-switch/evict).

Voice id is part of the key, so switching voices simply misses the cache and re-measures; no stale timings are ever served. The repository is injectable (mirrors `DriftLibraryRepository`), with an in-memory `NativeDatabase.memory()` for tests.

### 3.4 Tap-to-seek — `lib/reader/` wiring
Tapping a rendered sentence seeks narration to it. Flow:
1. The reader receives a tap with a `Locator` from `flutter_readium`.
2. Resolve tap → sentence index: match the tapped locator's text/CFI against the chapter's sentence list (reuse the same text the segmenter produced; fall back to nearest progression if no exact text match).
3. `handler.seekToSentence(index)` → `controller.playFrom(index)` (starts playing there if idle, or jumps if already playing). The completion-driven loop takes over from the new index; the timing table records from there.

> **Integration risk:** `flutter_readium`'s tap/selection→`Locator` surface is the least-proven API here (it's the same Decorator-family bridge flagged as the #1 stack risk in the MVP spec). The index-resolution is written defensively (exact text match → progression fallback) and the on-device behaviour is a **manual check**. If the tap API can't yield a usable locator, tap-to-seek degrades to "tap shows a seek affordance on the transport bar" — the skip/seek plumbing still works; only the discovery gesture changes. The timing table and persistence do not depend on this.

### 3.5 Page-follow refinement
Phase 2 already calls `goToLocator` on every highlight. Refine so it only navigates when the highlighted sentence is **not already visible** (avoid mid-page jitter / fighting the user's manual page turns). If `flutter_readium` exposes current-visible-range, gate on it; otherwise keep the always-navigate behaviour (correct, slightly jumpy) and note the polish as a manual check. No regression either way.

## 4. Data flow (one chapter, first listen → re-listen)

**First listen:** press Listen → controller plays sentence 0, `speak` returns `audioMs` → append timing → highlight advances → … chapter ends → `onChapterTimed(timings)` → `TimingRepository.save`. Tap a later sentence any time → `indexAt`/index resolve → `playFrom`.

**Re-listen (same voice):** reader opens chapter → `TimingRepository.load` hits → `ChapterTimings` available immediately → tap-to-seek works **before** playback (we know every sentence's offset without synthesizing). Live playback still re-synthesizes audio (we cache timings, not audio — audio caching is out of scope), but never re-measures.

## 5. Out of scope (explicit)
- ❌ Full player-position-stream-driven highlight (completion-driven stays).
- ❌ Speed-control UI (seam only; spec §6 fast-follow).
- ❌ Word-level highlighting (table generalizes later; spec stretch).
- ❌ Caching synthesized **audio** (only timings are cached).
- ❌ iOS-specific work (keep shared Dart iOS-clean).

## 6. Testing strategy
- **Unit (no device):**
  - `SentenceTiming`/`ChapterTimings`: cumulative offsets, `indexAt` boundaries (first/last/exact-boundary/out-of-range), `startMsOf`, monotonic & gap-free invariant.
  - `NarrationController` timing capture: after a fake play-through, `currentTimings` is monotonic, gap-free, and matches the fake engine's reported durations; chapter roll-over finalizes and restarts.
  - `TimingRepository` against `NativeDatabase.memory()`: save→load round-trip, voice-id miss, `evictVoice`, upsert idempotency.
  - Tap→index resolution: exact text match, whitespace-normalized match, progression fallback.
- **Build:** `flutter analyze` clean, full `flutter test` green, debug APK builds.
- **Deferred to device (manual checks):** no-drift over a real chapter; tap-to-seek gesture on `flutter_readium`; page-follow jitter; re-listen uses cache (no re-measure).

## 7. Definition of Done
- [ ] `SentenceTiming`/`ChapterTimings` with tested `indexAt`/`startMsOf` and monotonic-gap-free invariant.
- [ ] Engine reports `lastUtteranceMs`; controller builds `ChapterTimings` during playback and emits finished chapters.
- [ ] `SentenceTimings` drift table (schemaVersion 2 + additive migration) + `TimingRepository` with load/save/evict, tested in-memory.
- [ ] Tap-to-seek wired (defensive index resolution); skip/seek route through `playFrom`.
- [ ] Page-follow no longer fights the reader (visible-gate or documented no-regression fallback).
- [ ] `flutter analyze` clean; all unit tests green; debug APK builds.
- [ ] Completion-driven live highlight not regressed.

## 8. Open items carried to manual checks
flutter_readium tap→Locator fidelity; visible-range API availability for page-follow gating; on-device no-drift confirmation; re-listen cache hit. All recorded in the combined Phase 2/3/4 manual-checks doc.
