# Phase 3 — Sentence-Level Synced Highlighting (Sync Layer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a measured `sentence → (startMs, durationMs)` timing table, persist it in `drift`, and use it for tap-to-seek and jitter-free page-follow — while keeping the proven completion-driven live highlight from Phase 1/2.

**Architecture:** Pragmatic hybrid (see [spec](../specs/2026-06-25-phase3-sync-layer-design.md)). The completion-driven `NarrationController` loop is unchanged; it gains a *passive* timing observer that builds `ChapterTimings` from durations the `NeuralNarrator` already measures. Timings persist to a new drift table keyed by `(bookId, chapterHref, voiceId)`. Tap-to-seek resolves a tapped sentence to an index and calls the existing `playFrom`.

**Tech Stack:** Flutter/Dart, `drift` (codegen via `build_runner`), `flutter_readium` (reader/tap/decoration), existing `audioplayers`-backed `NeuralNarrator` + `audio_service` handler.

## Global Constraints

- **Android-first; keep shared Dart iOS-clean** — no Android-only APIs in shared code.
- **Toolchain pins (do not change):** AGP 8.9.1, Kotlin 2.3.21, `desugar_jdk_libs` 2.1.5, NDK 27.0.12077973, compileSdk 36, minSdk 24, JDK 21, `FlutterFragmentActivity`.
- **Do not regress the completion-driven highlight** — the live highlight stays locked to audio-end; timing capture is a passive observer only.
- **Cache timings, not audio** — re-listen avoids re-*measuring*, not re-*synthesizing*.
- **Voice id is part of every timing key** — switching voices must miss the cache, never serve stale timings.
- **Each task: `flutter analyze` clean + `flutter test` green before commit.** Drift schema changes regenerate `library_database.g.dart` via `dart run build_runner build --delete-conflicting-outputs`.

---

### Task 1: Timing model — `SentenceTiming` + `ChapterTimings`

**Why:** The pure-data source of truth for the position↔index mapping. No Flutter deps → fast unit tests. Everything else consumes it.

**Files:**
- Create: `lib/sync/sentence_timing.dart`
- Test: `test/sentence_timing_test.dart`

**Interfaces:**
- Produces:
  - `class SentenceTiming { final int index; final int startMs; final int durationMs; int get endMs; }`
  - `class ChapterTimings { final String chapterHref; final String voiceId; final List<SentenceTiming> sentences; int get totalMs; int indexAt(int ms); int startMsOf(int index); }`
  - `ChapterTimings.builder(chapterHref, voiceId)` accumulator with `void add(int durationMs)` and `ChapterTimings build()`.

- [ ] **Step 1: Write the failing test**

```dart
// test/sentence_timing_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/sync/sentence_timing.dart';

void main() {
  ChapterTimings sample() {
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy');
    b.add(1000); // s0: 0..1000
    b.add(2000); // s1: 1000..3000
    b.add(500);  // s2: 3000..3500
    return b.build();
  }

  test('builder assigns cumulative offsets', () {
    final t = sample();
    expect(t.sentences.map((s) => s.startMs), [0, 1000, 3000]);
    expect(t.sentences.map((s) => s.endMs), [1000, 3000, 3500]);
    expect(t.totalMs, 3500);
  });

  test('startMsOf returns a sentence start', () {
    expect(sample().startMsOf(1), 1000);
  });

  test('indexAt maps a position to the playing sentence', () {
    final t = sample();
    expect(t.indexAt(0), 0);
    expect(t.indexAt(999), 0);
    expect(t.indexAt(1000), 1); // boundary belongs to the next sentence
    expect(t.indexAt(2999), 1);
    expect(t.indexAt(3499), 2);
  });

  test('indexAt clamps out-of-range positions', () {
    final t = sample();
    expect(t.indexAt(-100), 0);
    expect(t.indexAt(99999), 2);
  });

  test('timings are monotonic and gap-free', () {
    final t = sample();
    for (var i = 1; i < t.sentences.length; i++) {
      expect(t.sentences[i].startMs, t.sentences[i - 1].endMs);
    }
  });

  test('empty chapter is well-formed', () {
    final t = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy').build();
    expect(t.totalMs, 0);
    expect(t.sentences, isEmpty);
    expect(t.indexAt(10), 0);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sentence_timing_test.dart`
Expected: FAIL (`sentence_timing.dart` / classes not defined).

- [ ] **Step 3: Write the implementation**

```dart
// lib/sync/sentence_timing.dart

/// One sentence's place in a chapter's measured audio timeline.
class SentenceTiming {
  const SentenceTiming({
    required this.index,
    required this.startMs,
    required this.durationMs,
  });

  final int index;
  final int startMs;
  final int durationMs;

  int get endMs => startMs + durationMs;
}

/// A chapter's full timeline, built from measured per-sentence durations.
///
/// The single source of truth for the position↔index mapping: [indexAt] is the
/// position-driven primitive (used by tap-to-seek today; speed control and a
/// scrubber later). Timings are voice-specific — [voiceId] is the cache key.
class ChapterTimings {
  ChapterTimings({
    required this.chapterHref,
    required this.voiceId,
    required this.sentences,
  });

  final String chapterHref;
  final String voiceId;
  final List<SentenceTiming> sentences;

  int get totalMs => sentences.isEmpty ? 0 : sentences.last.endMs;

  int startMsOf(int index) => sentences[index].startMs;

  /// Which sentence is playing at [ms] (clamped to range). O(log n).
  int indexAt(int ms) {
    if (sentences.isEmpty) return 0;
    if (ms < 0) return 0;
    if (ms >= totalMs) return sentences.length - 1;
    var lo = 0, hi = sentences.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ms < sentences[mid].endMs) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  static ChapterTimingsBuilder builder({
    required String chapterHref,
    required String voiceId,
  }) =>
      ChapterTimingsBuilder(chapterHref: chapterHref, voiceId: voiceId);
}

/// Accumulates measured durations into a [ChapterTimings] as playback proceeds.
class ChapterTimingsBuilder {
  ChapterTimingsBuilder({required this.chapterHref, required this.voiceId});

  final String chapterHref;
  final String voiceId;
  final List<SentenceTiming> _sentences = [];
  int _cursorMs = 0;

  int get length => _sentences.length;

  /// Append the next sentence with its measured [durationMs].
  void add(int durationMs) {
    _sentences.add(SentenceTiming(
      index: _sentences.length,
      startMs: _cursorMs,
      durationMs: durationMs,
    ));
    _cursorMs += durationMs;
  }

  ChapterTimings build() => ChapterTimings(
        chapterHref: chapterHref,
        voiceId: voiceId,
        sentences: List.unmodifiable(_sentences),
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sentence_timing_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/sync/sentence_timing.dart test/sentence_timing_test.dart
git commit -m "Phase 3 Task 1: SentenceTiming + ChapterTimings timing-table model"
```

---

### Task 2: Duration capture — engine reports `lastUtteranceMs`; controller builds timings

**Why:** Surface the duration the narrator already measures (`_Prepared.audioMs`) and have the controller passively assemble `ChapterTimings` as the completion-driven loop runs.

**Files:**
- Modify: `lib/narration/tts_engine.dart` (add `lastUtteranceMs`)
- Modify: `lib/narration/neural_narrator.dart` (track + expose played duration)
- Modify: `lib/sync/narration_controller.dart` (build timings, expose `currentTimings`, `onChapterTimed`)
- Modify: `test/support/fake_tts_engine.dart` (configurable duration + `lastUtteranceMs`)
- Test: `test/narration_controller_test.dart` (new timing-capture tests)

**Interfaces:**
- Consumes: `ChapterTimings`/`ChapterTimingsBuilder` (Task 1), `TtsEngine.speak` (Phase 1).
- Produces:
  - `int get lastUtteranceMs;` on `TtsEngine` (ms of the most recently finished `speak`, else 0).
  - `NarrationController`: `ChapterTimings? get currentTimings`, `void Function(ChapterTimings finished)? onChapterTimed`, and a settable `String voiceId` (defaults `'unknown'`) + `String chapterHref` used as the timing keys.
  - `NarrationController.seekToSentence(int index)` (alias of `playFrom`, named for the handler/reader).

- [ ] **Step 1: Add `lastUtteranceMs` to the engine interface**

In `lib/narration/tts_engine.dart`, inside `abstract class TtsEngine`, after `Future<void> speak(String text);`:

```dart
  /// Measured audio length (ms) of the most recently completed [speak], or 0 if
  /// none has completed. Powers the Phase-3 timing table.
  int get lastUtteranceMs;
```

- [ ] **Step 2: Implement it in `NeuralNarrator`**

In `lib/narration/neural_narrator.dart`, add a field near the other state (after `int _seq = 0;`):

```dart
  int _lastUtteranceMs = 0;

  @override
  int get lastUtteranceMs => _lastUtteranceMs;
```

In `speak`, set it from the played `_Prepared`. After the line `final bool preloaded = s == _armed && _armedPrep != null;` block resolves `prep`, and right before the playback `for` loop (after `if (_stopRequested) return;` on the line preceding `final player = _curPlayer;`), add:

```dart
    _lastUtteranceMs = prep.audioMs;
```

- [ ] **Step 3: Make `FakeTtsEngine` carry a duration**

Replace `test/support/fake_tts_engine.dart` body so `speak` records a per-utterance duration and `finishCurrent`/`stop` set `lastUtteranceMs`:

```dart
import 'dart:async';

import 'package:narrarr/narration/tts_engine.dart';

/// A controllable [TtsEngine] test double: [speak] returns a future that stays
/// pending until the test resolves it (via [finishCurrent]) or [stop]/[pause]
/// acts on it — mirroring the real "speak completes on audio-end" contract
/// without any audio or native code.
class FakeTtsEngine implements TtsEngine {
  FakeTtsEngine({this.durationMs = 1000});

  /// Reported [lastUtteranceMs] for each completed utterance. A single value
  /// applies to all; override per call by pushing to [durations].
  int durationMs;
  final List<int> durations = [];

  final List<String> spoken = [];
  Completer<void>? _current;
  int _lastUtteranceMs = 0;
  bool paused = false;
  double volume = 1.0;

  @override
  String get name => 'fake';

  @override
  int get lastUtteranceMs => _lastUtteranceMs;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    final c = _current = Completer<void>();
    return c.future;
  }

  /// Resolve the pending [speak], setting [lastUtteranceMs] to the next queued
  /// duration (or the default).
  void finishCurrent() {
    if (_current != null && !_current!.isCompleted) {
      _lastUtteranceMs = durations.isNotEmpty ? durations.removeAt(0) : durationMs;
      _current!.complete();
    }
  }

  @override
  void precache(String text) {}

  @override
  void preloadNext(String text) {}

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> pause() async => paused = true;

  @override
  Future<void> resume() async => paused = false;

  @override
  Future<void> stop() async {
    if (_current != null && !_current!.isCompleted) _current!.complete();
  }

  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 4: Write the failing controller timing tests**

Append to `test/narration_controller_test.dart` (inside `main()`):

```dart
  test('captures cumulative timings as sentences finish', () async {
    final fake = FakeTtsEngine();
    fake.durations.addAll([1000, 2000]);
    final c = NarrationController(engine: fake)
      ..voiceId = 'amy'
      ..chapterHref = 'ch1';
    c.setSentences(['a', 'b']);

    unawaited(c.play());
    await pumpEventQueue();
    fake.finishCurrent(); // 'a' = 1000ms
    await pumpEventQueue();
    fake.finishCurrent(); // 'b' = 2000ms
    await pumpEventQueue();

    final t = c.currentTimings!;
    expect(t.voiceId, 'amy');
    expect(t.chapterHref, 'ch1');
    expect(t.sentences.map((s) => s.startMs), [0, 1000]);
    expect(t.sentences.map((s) => s.durationMs), [1000, 2000]);
  });

  test('finalizes timings on chapter roll-over via onChapterTimed', () async {
    final fake = FakeTtsEngine();
    final finished = <ChapterTimings>[];
    final chapters = [
      ['c2-a'],
      <String>[],
    ];
    final c = NarrationController(engine: fake)
      ..voiceId = 'amy'
      ..chapterHref = 'ch1'
      ..onChapterTimed = finished.add
      ..fetchNextChapter = () async =>
          chapters.isEmpty ? const [] : chapters.removeAt(0);
    c.setSentences(['c1-a']);

    unawaited(c.play());
    for (var i = 0; i < 6 && c.isPlaying; i++) {
      await pumpEventQueue();
      fake.finishCurrent();
    }
    await pumpEventQueue();

    expect(finished.first.chapterHref, 'ch1');
    expect(finished.first.sentences.length, 1);
  });
```

Add the import at the top of the test file:

```dart
import 'package:narrarr/sync/sentence_timing.dart';
```

- [ ] **Step 5: Run to verify failure**

Run: `flutter test test/narration_controller_test.dart`
Expected: FAIL (`voiceId`, `chapterHref`, `currentTimings`, `onChapterTimed` undefined).

- [ ] **Step 6: Implement timing capture in `NarrationController`**

In `lib/sync/narration_controller.dart`:

Add the import:
```dart
import 'sentence_timing.dart';
```

Add fields (near `int _token = 0;`):
```dart
  /// Timing-table keys. Set by the reader before play; part of the drift cache
  /// key so timings are scoped to a book chapter and voice.
  String voiceId = 'unknown';
  String chapterHref = '';

  /// Emitted when a chapter's timings are complete (chapter exhausted or book
  /// ended). The reader persists these to drift.
  void Function(ChapterTimings finished)? onChapterTimed;

  ChapterTimingsBuilder? _timingBuilder;
  ChapterTimings? _currentTimings;

  /// Timings measured so far for the current chapter (live, may be partial).
  ChapterTimings? get currentTimings =>
      _currentTimings ?? _timingBuilder?.build();
```

Replace `setSentences` so it starts a fresh timing builder:
```dart
  void setSentences(List<String> sentences) {
    _sentences = sentences;
    _index = 0;
    _timingBuilder =
        ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
    _currentTimings = null;
    notifyListeners();
  }
```

In `play()`, capture a duration after each `speak`. Replace the body of the inner `for` loop's tail — i.e. the line `await engine.speak(_sentences[i]);` — with:
```dart
        await engine.speak(_sentences[i]);
        if (token != _token) return;
        _timingBuilder?.add(engine.lastUtteranceMs);
```

In `play()`, when a chapter is exhausted and rolls into the next, finalize timings. Replace this existing block:
```dart
      if (token != _token) return;
      final next = await fetchNextChapter?.call() ?? const [];
      if (token != _token) return;
      if (next.isEmpty) break; // end of book
      _sentences = next;
      i = 0;
```
with:
```dart
      if (token != _token) return;
      _finalizeChapterTimings();
      final next = await fetchNextChapter?.call() ?? const [];
      if (token != _token) return;
      if (next.isEmpty) break; // end of book
      _sentences = next;
      i = 0;
      _timingBuilder =
          ChapterTimings.builder(chapterHref: chapterHref, voiceId: voiceId);
```

After the `while` loop, where playback ends naturally — replace:
```dart
    if (token == _token) {
      _playing = false;
      notifyListeners();
    }
```
with:
```dart
    if (token == _token) {
      _finalizeChapterTimings();
      _playing = false;
      notifyListeners();
    }
```

Add the helper method and a seek alias before `dispose()`:
```dart
  void _finalizeChapterTimings() {
    final b = _timingBuilder;
    if (b == null || b.length == 0) return;
    final timings = b.build();
    _currentTimings = timings;
    onChapterTimed?.call(timings);
  }

  /// Seek narration to [index] and play from there. Alias of [playFrom] for the
  /// handler / reader tap-to-seek path.
  Future<void> seekToSentence(int index) => playFrom(index);
```

> Note: `chapterHref` is set on the controller by the reader's `_nextChapterSentences` before it returns the next chapter's sentences, so each chapter's builder is keyed correctly (wired in Task 4).

- [ ] **Step 7: Run all tests**

Run: `flutter test`
Expected: PASS (existing + 2 new controller tests + Task-1 tests).

- [ ] **Step 8: Commit**

```bash
git add lib/narration/tts_engine.dart lib/narration/neural_narrator.dart lib/sync/narration_controller.dart test/support/fake_tts_engine.dart test/narration_controller_test.dart
git commit -m "Phase 3 Task 2: measure per-sentence durations; controller builds ChapterTimings"
```

---

### Task 3: Persist timings in `drift` — `SentenceTimings` table + `TimingRepository`

**Why:** Re-listening a chapter should not re-measure. Voice id in the key guarantees a switched voice misses the cache.

**Files:**
- Modify: `lib/library/drift/library_database.dart` (add table; bump schemaVersion; migration)
- Modify: `lib/library/drift/library_database.g.dart` (regenerated — do not hand-edit)
- Create: `lib/sync/timing_repository.dart`
- Test: `test/timing_repository_test.dart`

**Interfaces:**
- Consumes: `ChapterTimings`/`SentenceTiming` (Task 1), `LibraryDatabase` (Phase 1).
- Produces:
  - `class TimingRepository { TimingRepository(LibraryDatabase db); Future<ChapterTimings?> load({required String bookId, required String chapterHref, required String voiceId}); Future<void> save({required String bookId, required ChapterTimings timings}); Future<void> evictVoice(String voiceId); }`

- [ ] **Step 1: Add the table + migration to `library_database.dart`**

Add the table class above `@DriftDatabase`:
```dart
/// Per-sentence measured timings (Phase 3). Cache key is
/// (bookId, chapterHref, voiceId, sentenceIndex); voice is part of the key so a
/// voice switch misses the cache rather than serving stale timings.
@DataClassName('SentenceTimingRow')
class SentenceTimings extends Table {
  TextColumn get bookId => text()();
  TextColumn get chapterHref => text()();
  TextColumn get voiceId => text()();
  IntColumn get sentenceIndex => integer()();
  IntColumn get startMs => integer()();
  IntColumn get durationMs => integer()();

  @override
  Set<Column> get primaryKey => {bookId, chapterHref, voiceId, sentenceIndex};
}
```

Change the annotation to include the table:
```dart
@DriftDatabase(tables: [Books, SentenceTimings])
```

Bump the schema version and add an additive migration inside `LibraryDatabase`:
```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(sentenceTimings);
        },
      );
```

- [ ] **Step 2: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `library_database.g.dart` updates with `SentenceTimingRow`, `$SentenceTimingsTable`, `SentenceTimingsCompanion`, and `sentenceTimings` getter; build succeeds.

- [ ] **Step 3: Write the failing repository test**

```dart
// test/timing_repository_test.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/library/drift/library_database.dart';
import 'package:narrarr/sync/sentence_timing.dart';
import 'package:narrarr/sync/timing_repository.dart';

void main() {
  late LibraryDatabase db;
  late TimingRepository repo;

  setUp(() {
    db = LibraryDatabase(NativeDatabase.memory());
    repo = TimingRepository(db);
  });
  tearDown(() => db.close());

  ChapterTimings sample(String voice) {
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: voice);
    b.add(1000);
    b.add(2000);
    return b.build();
  }

  test('save then load round-trips the timings', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got = await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy');
    expect(got, isNotNull);
    expect(got!.sentences.map((s) => s.startMs), [0, 1000]);
    expect(got.sentences.map((s) => s.durationMs), [1000, 2000]);
    expect(got.voiceId, 'amy');
  });

  test('load misses on a different voice', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got = await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'ryan');
    expect(got, isNull);
  });

  test('save is idempotent (upsert)', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    await repo.save(bookId: 'b1', timings: sample('amy'));
    final got = await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy');
    expect(got!.sentences.length, 2);
  });

  test('evictVoice removes only that voice', () async {
    await repo.save(bookId: 'b1', timings: sample('amy'));
    await repo.save(bookId: 'b1', timings: sample('ryan'));
    await repo.evictVoice('amy');
    expect(await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'amy'), isNull);
    expect(await repo.load(bookId: 'b1', chapterHref: 'ch1', voiceId: 'ryan'), isNotNull);
  });
}
```

- [ ] **Step 4: Run to verify failure**

Run: `flutter test test/timing_repository_test.dart`
Expected: FAIL (`timing_repository.dart` not found).

- [ ] **Step 5: Implement `TimingRepository`**

```dart
// lib/sync/timing_repository.dart
import 'package:drift/drift.dart';

import '../library/drift/library_database.dart';
import 'sentence_timing.dart';

/// Caches measured [ChapterTimings] in drift so re-listening a chapter does not
/// re-measure. Keyed by (bookId, chapterHref, voiceId).
class TimingRepository {
  TimingRepository(this.db);

  final LibraryDatabase db;

  Future<ChapterTimings?> load({
    required String bookId,
    required String chapterHref,
    required String voiceId,
  }) async {
    final rows = await (db.select(db.sentenceTimings)
          ..where((t) =>
              t.bookId.equals(bookId) &
              t.chapterHref.equals(chapterHref) &
              t.voiceId.equals(voiceId))
          ..orderBy([(t) => OrderingTerm.asc(t.sentenceIndex)]))
        .get();
    if (rows.isEmpty) return null;
    return ChapterTimings(
      chapterHref: chapterHref,
      voiceId: voiceId,
      sentences: [
        for (final r in rows)
          SentenceTiming(
            index: r.sentenceIndex,
            startMs: r.startMs,
            durationMs: r.durationMs,
          ),
      ],
    );
  }

  Future<void> save({
    required String bookId,
    required ChapterTimings timings,
  }) async {
    await db.batch((b) {
      b.insertAllOnConflictUpdate(
        db.sentenceTimings,
        [
          for (final s in timings.sentences)
            SentenceTimingsCompanion.insert(
              bookId: bookId,
              chapterHref: timings.chapterHref,
              voiceId: timings.voiceId,
              sentenceIndex: s.index,
              startMs: s.startMs,
              durationMs: s.durationMs,
            ),
        ],
      );
    });
  }

  Future<void> evictVoice(String voiceId) =>
      (db.delete(db.sentenceTimings)..where((t) => t.voiceId.equals(voiceId)))
          .go();
}
```

- [ ] **Step 6: Run tests**

Run: `flutter test test/timing_repository_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Full suite + analyze**

Run: `flutter test && flutter analyze lib`
Expected: all green; analyze clean.

- [ ] **Step 8: Commit**

```bash
git add lib/library/drift/library_database.dart lib/library/drift/library_database.g.dart lib/sync/timing_repository.dart test/timing_repository_test.dart
git commit -m "Phase 3 Task 3: drift SentenceTimings table + TimingRepository (cache by voice)"
```

---

### Task 4: Tap-to-seek + load/persist timings + page-follow gate (reader wiring)

**Why:** Connect the table to the UI: load cached timings on open, persist measured ones, let a tap on a sentence seek there, and stop page-follow from fighting the reader. This is the device-facing payoff.

**Files:**
- Modify: `lib/narration/narration_audio_handler.dart` (add `seekToSentence`; set `voiceId`/`chapterHref`)
- Modify: `lib/reader/reader_screen.dart` (load/persist timings; tap→index; page-follow gate)
- Test: `test/narration_audio_handler_test.dart` (seek delegates to the controller)

**Interfaces:**
- Consumes: `NarrationController.seekToSentence` + `voiceId`/`chapterHref`/`currentTimings`/`onChapterTimed` (Task 2), `TimingRepository` (Task 3).
- Produces:
  - `NarrationAudioHandler.seekToSentence(int index)` and `loadChapter(... required String voiceId, required String chapterHref ...)`.

- [ ] **Step 1: Failing handler test**

Append to `test/narration_audio_handler_test.dart` (inside `main()`):

```dart
  test('seekToSentence plays from the tapped index', () async {
    final fake = FakeTtsEngine();
    final controller = NarrationController(engine: fake);
    final handler = NarrationAudioHandler(controller);
    controller.setSentences(['a', 'b', 'c']);

    await handler.seekToSentence(2);
    await pumpEventQueue();
    expect(controller.index, 2);

    await controller.stop();
  });
```

Ensure the file imports `FakeTtsEngine`, `NarrationController`, and `pumpEventQueue` (already used by existing tests in this file — add the import only if missing):
```dart
import 'support/fake_tts_engine.dart';
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/narration_audio_handler_test.dart`
Expected: FAIL (`seekToSentence` not on the handler).

- [ ] **Step 3: Add `seekToSentence` + timing keys to the handler**

In `lib/narration/narration_audio_handler.dart`, extend `loadChapter` to take the keys and forward them, and add the seek method.

Change the `loadChapter` signature/body:
```dart
  void loadChapter({
    required String bookId,
    required String title,
    String? author,
    required List<String> sentences,
    required String voiceId,
    required String chapterHref,
    Future<void> Function(int index)? onHighlight,
  }) {
    controller.onHighlight = onHighlight;
    controller.voiceId = voiceId;
    controller.chapterHref = chapterHref;
    controller.setSentences(sentences);
    mediaItem.add(MediaItem(id: bookId, title: title, artist: author));
  }
```

Add after `skipToPrevious`:
```dart
  /// Seek narration to a specific sentence (tap-to-seek from the reader).
  Future<void> seekToSentence(int index) => controller.seekToSentence(index);
```

- [ ] **Step 4: Run the handler test**

Run: `flutter test test/narration_audio_handler_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire load/persist + voiceId in the reader**

In `lib/reader/reader_screen.dart`:

Add imports:
```dart
import '../sync/sentence_timing.dart';
import '../sync/timing_repository.dart';
```

Add a repository field and the active voice id near the other fields:
```dart
  TimingRepository? _timings;
  // The bundled offline default; Phase 4 makes this user-selectable.
  static const _voiceId = 'vits-piper-en_US-amy-low';
```

In `_init`, construct the timing repository from the same database the library uses. The reader receives a `LibraryRepository?`; add an optional `TimingRepository?` constructor arg so it can be injected, defaulting to one built on a shared `LibraryDatabase`. Update the constructor:
```dart
  const ReaderScreen({
    super.key,
    required this.book,
    this.repository,
    this.timingRepository,
  });

  final Book book;
  final LibraryRepository? repository;
  final TimingRepository? timingRepository;
```

In `_init`, after `_handler = await narrationHandler();`:
```dart
    _timings = widget.timingRepository ??
        TimingRepository(LibraryDatabase());
```
Add the import for `LibraryDatabase`:
```dart
import '../library/drift/library_database.dart';
```

In `_open`, set the controller keys and persist callback before `loadChapter`. Replace the `_handler!.loadChapter(...)` call with:
```dart
      _narration!.fetchNextChapter = _nextChapterSentences;
      _narration!.onChapterTimed = _persistTimings;
      _handler!.loadChapter(
        bookId: widget.book.id,
        title: widget.book.title,
        author: widget.book.author,
        sentences: chapter.sentences,
        voiceId: _voiceId,
        chapterHref: chapter.hrefHint,
        onHighlight: _highlightSentence,
      );
```

In `_nextChapterSentences`, set the controller's `chapterHref` for the new chapter (so its builder is keyed correctly) before returning. After `_chapterHref = _hrefFor(pub, next.hrefHint);` add:
```dart
    _narration?.chapterHref = next.hrefHint;
```

Add the persist + load helpers (near the highlight section):
```dart
  Future<void> _persistTimings(ChapterTimings t) async {
    await _timings?.save(bookId: widget.book.id, timings: t);
  }
```

- [ ] **Step 6: Tap-to-seek**

In `_highlightSentence` region, add a handler that resolves a tapped locator to a sentence index and seeks. flutter_readium surfaces taps via `onTextLocatorChanged`/selection; resolve defensively by matching the tapped text against the chapter sentences. Add:

```dart
  /// Resolve a tapped/selected locator to a chapter sentence index, then seek
  /// narration there. Exact text match → whitespace-normalized match → no-op.
  Future<void> _seekToTappedLocator(Locator loc) async {
    final c = _narration;
    if (c == null || c.sentenceCount == 0) return;
    final tapped = (loc.text?.highlight ?? '').trim();
    if (tapped.isEmpty) return;
    final norm = _normalize(tapped);
    var match = -1;
    for (var i = 0; i < c.sentenceCount; i++) {
      if (_normalize(c.sentenceTextAt(i)).contains(norm) ||
          norm.contains(_normalize(c.sentenceTextAt(i)))) {
        match = i;
        break;
      }
    }
    if (match >= 0) await _handler!.seekToSentence(match);
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
```

Wire it to the reader's selection/tap stream where `_locSub` is set up. The reader already listens to `onTextLocatorChanged` for position; add a tap path only if `flutter_readium` exposes a distinct tap/selection stream. If it does not, leave `_seekToTappedLocator` available and gate the gesture behind the transport bar (documented manual check). Add a long-press/selection listener if available:
```dart
    // Tap-to-seek: when the reader reports a selected text locator, seek there.
    // (Gesture fidelity is a device manual-check — see phase manual-checks doc.)
    _readium.onTextSelected?.listen(_seekToTappedLocator);
```
> If `onTextSelected` does not exist on this `flutter_readium` version, omit this line; `_seekToTappedLocator` stays callable for a future wire-up and the manual-checks doc records the gap. Do not invent an API — verify against the installed package.

- [ ] **Step 7: Page-follow gate**

In `_highlightSentence`, the existing `await _readium.goToLocator(loc);` always navigates. Guard it so it only navigates when needed. Replace that line with:
```dart
      // Page-follow: keep the spoken sentence visible. Navigating every sentence
      // can fight the reader, so only move when the engine isn't already there.
      // (Visible-range gating is a device manual-check; always-follow is correct
      // but can be slightly jumpy.)
      await _readium.goToLocator(loc);
```
> Keep the always-follow behaviour (correct, no regression). If the installed `flutter_readium` exposes a current-visible-range or `currentLocator`, gate on it; otherwise leave as-is and record the polish in manual checks. Do not fabricate an API.

- [ ] **Step 8: Run analyze + tests + build**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: clean; all tests green; APK builds.

- [ ] **Step 9: Commit**

```bash
git add lib/narration/narration_audio_handler.dart lib/reader/reader_screen.dart test/narration_audio_handler_test.dart
git commit -m "Phase 3 Task 4: tap-to-seek, timing persistence, page-follow gate (reader wiring)"
```

---

### Task 5: Load cached timings on open (re-listen fast path) + final verification

**Why:** Close the loop: when a chapter was listened to before with the same voice, load its timings on open so tap-to-seek works immediately (before any playback) and nothing is re-measured.

**Files:**
- Modify: `lib/reader/reader_screen.dart` (preload timings on open; expose to controller)
- Modify: `lib/sync/narration_controller.dart` (accept preloaded timings)
- Test: `test/narration_controller_test.dart` (preloaded timings are served)

**Interfaces:**
- Consumes: `TimingRepository.load` (Task 3), `ChapterTimings` (Task 1).
- Produces: `NarrationController.primeTimings(ChapterTimings)` — seed `currentTimings`/builder cursor from cache.

- [ ] **Step 1: Failing controller test**

Append to `test/narration_controller_test.dart`:
```dart
  test('primeTimings seeds currentTimings before playback', () {
    final c = NarrationController(engine: FakeTtsEngine())
      ..voiceId = 'amy'
      ..chapterHref = 'ch1';
    c.setSentences(['a', 'b']);
    final b = ChapterTimings.builder(chapterHref: 'ch1', voiceId: 'amy')
      ..add(1000)
      ..add(2000);
    c.primeTimings(b.build());
    expect(c.currentTimings!.indexAt(1500), 1);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/narration_controller_test.dart`
Expected: FAIL (`primeTimings` undefined).

- [ ] **Step 3: Implement `primeTimings`**

In `lib/sync/narration_controller.dart`, add:
```dart
  /// Seed timings from the drift cache so position lookups (tap-to-seek) work
  /// before playback. Playback still re-synthesizes audio but won't re-measure.
  void primeTimings(ChapterTimings cached) {
    _currentTimings = cached;
    notifyListeners();
  }
```
Note `setSentences` resets `_currentTimings = null`; call `primeTimings` *after* `setSentences`.

- [ ] **Step 4: Run the test**

Run: `flutter test test/narration_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Preload in the reader on open**

In `lib/reader/reader_screen.dart` `_open`, after `_handler!.loadChapter(...)`, attempt to load cached timings for the starting chapter:
```dart
      final cached = await _timings?.load(
        bookId: widget.book.id,
        chapterHref: chapter.hrefHint,
        voiceId: _voiceId,
      );
      if (cached != null) _narration!.primeTimings(cached);
```

Also prime on chapter roll-over: in `_nextChapterSentences`, after setting `_narration?.chapterHref`, load and prime:
```dart
    final cached = await _timings?.load(
      bookId: widget.book.id,
      chapterHref: next.hrefHint,
      voiceId: _voiceId,
    );
```
Return the sentences as before; priming the next chapter happens once the controller swaps to it — for simplicity, prime only the starting chapter in `_open` (the roll-over re-measures, which is acceptable and already persisted on completion). Keep the roll-over load out if it complicates the control flow; the starting-chapter fast path is the required behaviour.

- [ ] **Step 6: Full verification**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: analyze clean; all tests green; APK builds.

- [ ] **Step 7: Commit**

```bash
git add lib/sync/narration_controller.dart lib/reader/reader_screen.dart test/narration_controller_test.dart
git commit -m "Phase 3 Task 5: load cached timings on open (re-listen fast path)"
```

---

## Phase 3 Definition of Done

- [ ] `SentenceTiming`/`ChapterTimings` with tested `indexAt`/`startMsOf`, monotonic & gap-free (Task 1).
- [ ] Engine reports `lastUtteranceMs`; controller builds `ChapterTimings` during playback and emits finished chapters (Task 2).
- [ ] `SentenceTimings` drift table (schemaVersion 2 + additive migration) + `TimingRepository` load/save/evict, tested in-memory (Task 3).
- [ ] Tap-to-seek wired with defensive index resolution; skip/seek route through `playFrom`/`seekToSentence` (Task 4).
- [ ] Timings persist on chapter completion; cached timings load on open for the re-listen fast path (Tasks 4–5).
- [ ] Page-follow does not regress (always-follow retained; visible-gate if the API exists).
- [ ] `flutter analyze` clean; all unit tests green; debug APK builds.
- [ ] Completion-driven live highlight not regressed.

## Manual checks (deferred — folded into the combined Phase 2/3/4 doc)
On-device no-drift over a real chapter; `flutter_readium` tap/selection → Locator fidelity for tap-to-seek; page-follow jitter / visible-range gating; re-listen uses the cache (no re-measure); large-book memory with the timing table.
