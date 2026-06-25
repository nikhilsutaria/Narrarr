# Phase 0 — Reader Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove, on a **real Android device**, that `flutter_readium` can render a real EPUB, let our code highlight an arbitrary sentence programmatically, and keep that highlight synced to audio from the POC's neural-TTS pipeline — then record a go/no-go verdict for the stack.

**Architecture:** A throwaway Flutter spike app, separate from `/poc` and from the future real app. It renders the bundled test EPUB with `flutter_readium`'s `ReadiumReaderWidget`, segments one chapter into sentences (reusing the POC's verse-aware normalization), highlights a sentence via `FlutterReadium.applyDecorations(...)`, and drives that highlight from completion-gated neural synthesis (`TtsSynthIsolate` ported verbatim from the POC). The reader and the narrator stay decoupled — they meet only where audio-completion advances the highlight.

**Tech Stack:** Flutter (Dart) · `flutter_readium` 0.1.0 · `sherpa_onnx` (Piper, ported from POC) · `audioplayers` (ported from POC — *not* `just_audio`; see constraint below) · `epubx` + `html` (sentence extraction) · `path_provider`, `path`, `archive`.

## Global Constraints

- **This is a throwaway spike.** Optimize for answering the go/no-go question fast, not for code quality. It will be deleted, like `/poc`. Port *techniques*, not polish.
- **Android only.** Every observation must be on a **real physical Android device** (not the emulator) — the whole point is to escape the emulator's distorted timing. Plug in a device; `flutter devices` must list it.
- **Real device is load-bearing for every timing/observation step.** A step "verified on emulator" does not count.
- **Reuse the POC pipeline as-is to isolate the reader variable.** Use `audioplayers` (POC's player), NOT `just_audio`. The `just_audio` migration is a separate Phase-2 question; introducing it here would change two variables at once and muddy the verdict.
- **Android build floors (from POC):** `minSdk 24`, `compileSdk 36`, `ndkVersion 27` — required by `sherpa_onnx` / `flutter_tts` native libs. `flutter_readium` may raise `minSdk`; if its example demands higher, take the higher value.
- **Test EPUB:** `the-odyssey-homer.epub` (repo root / `poc/assets/`). Target chapter: Book IX ("The Cyclops") — expressive verse, the POC's reference passage.
- **Voice:** reuse the POC's bundled Piper `.tar` and extraction logic. The voice choice does not affect this spike's verdict.
- **Verification is observation + measurement, not unit tests.** "The highlight visually tracks the spoken sentence on a real phone" cannot be asserted by a unit test; it is verified by on-device screenshots and the developer's eyes/ears, exactly as the POC was. Where a check *can* be automated or read from a log (RTF math, non-empty Locator, decoration applied without throwing), the step says so.

---

## Pre-flight (do once, before Task 1)

- [ ] **Confirm a real Android device is connected.** Run: `flutter devices` — expect a physical device (not `emulator-5554`/`sdk_gphone`) in the list. Record its model. If none, stop and attach one; the spike is meaningless on the emulator.
- [ ] **Locate the source assets.** Confirm these exist: `poc/assets/the-odyssey-homer.epub` and `poc/assets/vits-piper-en_US-amy-low.tar`. They will be copied into the spike's `assets/`.

---

### Task 1: Scaffold the spike app and render the test EPUB

**Files:**
- Create: `spike/` (new Flutter project, sibling of `poc/`)
- Modify: `spike/pubspec.yaml` (deps + asset declarations)
- Modify: `spike/android/app/build.gradle.kts` (SDK/NDK floors)
- Create: `spike/lib/main.dart` (render-only first cut)
- Copy: `spike/assets/the-odyssey-homer.epub`

**Interfaces:**
- Consumes: nothing (entry point).
- Produces: a running app that displays the EPUB via `ReadiumReaderWidget`; a global `final readium = FlutterReadium();` facade used by every later task.

- [ ] **Step 1: Create the project**

```bash
cd c:/nlab/dev/Narrarr
flutter create --org dev.narrarr --project-name narrarr_spike spike
```

- [ ] **Step 2: Add dependencies**

```bash
cd c:/nlab/dev/Narrarr/spike
flutter pub add flutter_readium sherpa_onnx audioplayers epubx html path_provider path archive
```

Expected: `pubspec.yaml` gains all eight packages; `flutter pub get` succeeds. If `flutter_readium` fails to resolve, run `flutter pub add flutter_readium:0.1.0` explicitly.

- [ ] **Step 3: Set Android build floors**

In `spike/android/app/build.gradle.kts`, inside `android { defaultConfig { … } }`, set:

```kotlin
minSdk = 24
compileSdk = 36
ndkVersion = "27.0.12077973"
```

(If `flutter_readium`'s plugin requires a higher `minSdk`, use that value instead and note it.)

- [ ] **Step 4: Bundle the test EPUB**

```bash
mkdir -p c:/nlab/dev/Narrarr/spike/assets
cp c:/nlab/dev/Narrarr/poc/assets/the-odyssey-homer.epub c:/nlab/dev/Narrarr/spike/assets/
```

Then declare it in `spike/pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/the-odyssey-homer.epub
```

- [ ] **Step 5: Write the render-only app**

`spike/lib/main.dart` — copy the bundled EPUB to a file path (Readium needs a `file://` URI), open it, and render. The `_copyAssetToFile` helper is reused by later tasks.

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_readium/flutter_readium.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final readium = FlutterReadium();

Future<String> copyAssetToFile(String asset) async {
  final dir = await getApplicationSupportDirectory();
  final out = File(p.join(dir.path, p.basename(asset)));
  if (!await out.exists()) {
    final data = await rootBundle.load(asset);
    await out.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }
  return out.path;
}

void main() => runApp(const SpikeApp());

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});
  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: SpikeHome());
}

class SpikeHome extends StatefulWidget {
  const SpikeHome({super.key});
  @override
  State<SpikeHome> createState() => _SpikeHomeState();
}

class _SpikeHomeState extends State<SpikeHome> {
  Publication? _pub;
  String _status = 'opening…';

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final path = await copyAssetToFile('assets/the-odyssey-homer.epub');
      final pub = await readium.openPublication('file://$path');
      setState(() {
        _pub = pub;
        _status = 'opened: ${pub.metadata.title}';
      });
      debugPrint('[spike] $_status · spine items: ${pub.readingOrder.length}');
    } catch (e) {
      setState(() => _status = 'open FAILED: $e');
      debugPrint('[spike] open FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pub = _pub;
    if (pub == null) {
      return Scaffold(body: Center(child: Text(_status)));
    }
    return Scaffold(
      appBar: AppBar(title: Text(pub.metadata.title)),
      body: ReadiumReaderWidget(
        publication: pub,
        verticalScroll: false,
        loadingWidget: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
```

> Note: `Publication.readingOrder` and `metadata.title` are the expected accessors; if the analyzer reports different names, adjust to the real API (`flutter pub get` then check `flutter_readium`'s exported symbols). This is the first place the v0.1.0 API meets reality.

- [ ] **Step 6: Run on the real device and verify rendering**

```bash
cd c:/nlab/dev/Narrarr/spike
flutter run -d <real-device-id>
```

Expected on device: the app opens, shows the book title in the app bar, and renders a readable, paginated EPUB page (swipe turns pages). Log shows `[spike] opened: …`.

**Verdict checkpoint 1 (render):** If `flutter_readium` cannot even open/render the EPUB on a real device, that is an early **FAIL** → jump to Task 7 and evaluate the foliate-js fallback before investing further.

- [ ] **Step 7: Commit**

```bash
git add spike/ && git commit -m "spike: render test EPUB with flutter_readium on device"
```

---

### Task 2: Extract one chapter's sentences (verse-aware)

**Files:**
- Create: `spike/lib/sentences.dart`
- Test: `spike/test/sentences_test.dart`
- Modify: `spike/lib/main.dart` (log extracted sentences)

**Interfaces:**
- Consumes: the EPUB bytes / a chapter's HTML.
- Produces: `Future<List<String>> extractSentences(Uint8List epubBytes, {String contentFileHint = 'book-9', int max = 40})` — ordered, trimmed, non-empty sentences from the target chapter. Reused by Tasks 3, 5, 6.

This is one place a real unit test *is* possible (pure text → text), so do it test-first.

- [ ] **Step 1: Write the failing test**

`spike/test/sentences_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr_spike/sentences.dart';

void main() {
  test('splits verse-aware HTML into clean sentences', () {
    const html = '<header><h2>Book IX</h2><p>summary</p></header>'
        '<p>Sing, O Muse.<br/>Of the man.</p><p>He sailed far. And wide!</p>';
    final out = sentencesFromHtml(html);
    expect(out, ['Sing, O Muse. Of the man.', 'He sailed far.', 'And wide!']);
  });
}
```

(`sentencesFromHtml` is the pure-text core; `extractSentences` wraps EPUB parsing around it.)

- [ ] **Step 2: Run it, verify it fails**

Run: `cd c:/nlab/dev/Narrarr/spike && flutter test test/sentences_test.dart`
Expected: FAIL — `sentences.dart` / `sentencesFromHtml` not defined.

- [ ] **Step 3: Implement `sentences.dart`** (port the POC's `epub_loader.dart` normalization)

```dart
import 'dart:typed_data';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;

/// Verse-aware HTML → clean speakable sentences. Ported from poc/lib/epub_loader.dart.
List<String> sentencesFromHtml(String html) {
  if (html.isEmpty) return const [];
  final pre = html
      .replaceAll(RegExp(r'<header[\s\S]*?</header>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
      .replaceAll(
        RegExp(r'</(p|div|h[1-6]|li|blockquote|section)>', caseSensitive: false),
        '\n',
      );
  final doc = html_parser.parse(pre);
  final text = (doc.body?.text ?? doc.documentElement?.text ?? '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\s*\n\s*'), '\n')
      .trim();
  return text
      .split(RegExp(r'(?<=[.!?])\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Load the EPUB and return the target chapter's sentences.
Future<List<String>> extractSentences(
  Uint8List epubBytes, {
  String contentFileHint = 'book-9',
  int max = 40,
}) async {
  final book = await EpubReader.readBook(epubBytes);
  final files = book.Content?.Html ?? const {};
  final hint = contentFileHint.toLowerCase();
  String html = '';
  for (final e in files.entries) {
    if (e.key.toLowerCase().contains(hint)) {
      html = e.value.Content ?? '';
      break;
    }
  }
  return sentencesFromHtml(html).take(max).toList();
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `flutter test test/sentences_test.dart`
Expected: PASS.

- [ ] **Step 5: Log the real chapter's sentences in `main.dart`**

In `_open()`, after a successful open, also read the EPUB bytes and call `extractSentences`, logging the count and first three. Expected log: ~30–40 sentences, the first being recognizable Book IX text.

- [ ] **Step 6: Commit**

```bash
git add spike/lib/sentences.dart spike/test/sentences_test.dart spike/lib/main.dart
git commit -m "spike: verse-aware sentence extraction (ported from POC)"
```

---

### Task 3: Highlight an arbitrary sentence programmatically (THE CRUX)

This is the single most important task — it retires risk #1/#2 from the spec. If `applyDecorations` cannot reliably highlight a sentence we name (by its text), the stack fails.

**Files:**
- Modify: `spike/lib/main.dart` (highlight controls + `_highlightSentence`)

**Interfaces:**
- Consumes: `extractSentences` (Task 2), the open `Publication`, the chapter `href`.
- Produces: `Future<void> highlightSentence(int index)` — clears the previous highlight and applies a new one for sentence `index` via `readium.applyDecorations`. Reused by Task 6.

- [ ] **Step 1: Find the target chapter's `href`**

After open, locate the spine/reading-order item whose href contains `book-9` and store it (`_chapterHref`). Log it. Expected: a non-empty href like `/text/chapter-9.xhtml` (exact form is whatever this EPUB uses — log it to learn it).

- [ ] **Step 2: Implement `highlightSentence` using the Decorator API**

```dart
static const _hlGroup = 'spike-utterance';

Future<void> highlightSentence(int index) async {
  final s = _sentences[index];
  final deco = ReaderDecoration(
    id: 'utterance',
    locator: Locator(
      href: _chapterHref,
      type: 'application/xhtml+xml',
      text: LocatorText(highlight: s),
    ),
    style: ReaderDecorationStyle(
      style: DecorationStyle.highlight,
      tint: Colors.amber.withOpacity(0.5),
    ),
  );
  // Re-applying the same group id replaces the previous decoration.
  await readium.applyDecorations(_hlGroup, [deco]);
  debugPrint('[spike] highlighted [$index]: '
      '${s.length > 40 ? "${s.substring(0, 40)}…" : s}');
}
```

- [ ] **Step 3: Add temporary UI to trigger it**

Add a `BottomAppBar` (over the reader, like the docs' `ReaderPage` example) with "◀ prev / next ▶" buttons that call `highlightSentence(--/++_idx)`, and a label showing `_idx`. This is throwaway control to drive the highlight by hand before audio exists.

- [ ] **Step 4: Run on device and verify highlight**

Run: `flutter run -d <real-device-id>`. Tap "next" repeatedly.
Expected on device: each tap visually highlights the **correct** sentence on the page (amber tint), and the previous highlight disappears (group replacement works). Take an on-device screenshot of a highlighted sentence.

**Verdict checkpoint 2 (programmatic highlight — the crux):**
- ✅ Highlight lands on the right sentence, replaces cleanly → the core risk is retired; continue.
- ⚠️ Highlight is offset / partial / requires a `cssSelector` instead of `LocatorText.highlight` → try supplying `locations: Locations(cssSelector: …)` (you'd need to derive selectors during extraction). Note the extra work in the findings.
- ❌ Cannot programmatically highlight a named sentence at all → **FAIL** → Task 7, foliate-js fallback.

- [ ] **Step 5: Verify clearing**

Add a "clear" button calling `readium.applyDecorations(_hlGroup, [])`. Tap it; expected: highlight disappears. Confirms decoration lifecycle is under our control.

- [ ] **Step 6: Commit**

```bash
git add spike/lib/main.dart
git commit -m "spike: programmatic sentence highlight via applyDecorations"
```

---

### Task 4: Auto page-turn to keep the highlighted sentence visible

**Files:**
- Modify: `spike/lib/main.dart` (page-follow logic)

**Interfaces:**
- Consumes: `highlightSentence`, `readium.goToLocator`, `readium.onTextLocatorChanged`.
- Produces: `highlightSentence` extended to bring the sentence on-screen when it's off the visible page.

- [ ] **Step 1: Subscribe to position changes**

In `initState`, `readium.onTextLocatorChanged.listen((loc) { _currentLoc = loc; debugPrint('[spike] loc href=${loc.href} prog=${loc.locations?.progression}'); });`. This tells us where the reader currently is.

- [ ] **Step 2: Navigate to the sentence when highlighting**

Extend `highlightSentence`: after `applyDecorations`, also call `await readium.goToLocator(deco.locator)` so the reader scrolls/pages to the highlighted sentence. Guard against redundant navigation when the sentence is already on the current page (compare hrefs / progression if available; if not determinable in v0.1.0, just always call `goToLocator` and observe whether it no-ops when already visible).

- [ ] **Step 3: Run on device and verify auto page-turn**

Run on device; tap "next" past the bottom of a page.
Expected: when the highlighted sentence is on the next page, the reader **turns the page** to show it, and the highlight is visible there. Capture a screenshot before/after a page turn.

**Verdict checkpoint 3 (page-follow):** If `goToLocator` to a `LocatorText.highlight`-only locator doesn't navigate (needs precise `progression`/`position`), note it — Phase 3 would then need to derive richer Locators during segmentation. Not a hard fail, but a cost to record.

- [ ] **Step 4: Commit**

```bash
git add spike/lib/main.dart
git commit -m "spike: auto page-turn follows the highlighted sentence"
```

---

### Task 5: Port the neural pipeline; synth + play one sentence; measure RTF on device

**Files:**
- Copy: `spike/lib/tts/tts_synth_isolate.dart` (verbatim from POC)
- Create: `spike/lib/tts/spike_narrator.dart` (minimal synth-one-sentence + play + RTF)
- Copy: `spike/assets/vits-piper-en_US-amy-low.tar` + declare in `pubspec.yaml`
- Modify: `spike/lib/main.dart` (wire a "Speak this sentence" button)

**Interfaces:**
- Consumes: `TtsSynthIsolate.synth(text) → (Float32List samples, int sampleRate)`.
- Produces: `SpikeNarrator` with `Future<void> init()`, `Future<Duration> speak(String text)` (completes when audio finishes; returns audio length), and a logged **RTF = synthWallMs / audioMs**.

> This task is independent of the reader and may be implemented in parallel with Tasks 3–4.

- [ ] **Step 1: Copy the isolate verbatim**

```bash
mkdir -p c:/nlab/dev/Narrarr/spike/lib/tts
cp c:/nlab/dev/Narrarr/poc/lib/tts/tts_synth_isolate.dart c:/nlab/dev/Narrarr/spike/lib/tts/
```

(No changes — it's a clean, proven, isolate-only module: `start({model, tokens, dataDir, numThreads})`, `synth(text, {sid, speed})`, `dispose()`.)

- [ ] **Step 2: Bundle the voice and declare it**

```bash
cp c:/nlab/dev/Narrarr/poc/assets/vits-piper-en_US-amy-low.tar c:/nlab/dev/Narrarr/spike/assets/
```

Add `- assets/vits-piper-en_US-amy-low.tar` under `flutter: assets:` in `pubspec.yaml`.

- [ ] **Step 3: Implement `spike_narrator.dart`** (port the POC's model-extraction + a *minimal* synth/encode/play — no look-ahead, no 2-player ping-pong; the spike only needs one sentence at a time, and RTF)

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'tts_synth_isolate.dart';

class SpikeNarrator {
  static const _voice = 'vits-piper-en_US-amy-low';
  static const _asset = 'assets/vits-piper-en_US-amy-low.tar';
  static const _modelFile = 'en_US-amy-low.onnx';

  final _synth = TtsSynthIsolate();
  final _player = AudioPlayer();
  late Directory _tmp;
  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    final dir = await _ensureModel();
    await _synth.start(
      model: p.join(dir, _modelFile),
      tokens: p.join(dir, 'tokens.txt'),
      dataDir: p.join(dir, 'espeak-ng-data'),
      numThreads: 2,
    );
    _tmp = await getTemporaryDirectory();
    await _synth.synth('Ready.'); // warm-up cold start
    _inited = true;
  }

  /// Synthesize + play [text], completing when audio finishes. Logs RTF.
  Future<Duration> speak(String text) async {
    final sw = Stopwatch()..start();
    final (samples, sr) = await _synth.synth(text);
    final synthMs = sw.elapsedMilliseconds;
    final audioMs = (samples.length * 1000 / sr).round();
    final rtf = synthMs / audioMs;
    debugPrint('[spike] RTF=${rtf.toStringAsFixed(2)} '
        '(synth ${synthMs}ms / audio ${audioMs}ms) chars=${text.length}');
    final path = p.join(_tmp.path, 'spike.wav');
    await File(path).writeAsBytes(_wav(samples, sr), flush: true);
    final done = Completer<void>();
    final sub = _player.onPlayerComplete.listen((_) => done.complete());
    await _player.play(DeviceFileSource(path));
    await done.future;
    await sub.cancel();
    return Duration(milliseconds: audioMs);
  }

  Future<String> _ensureModel() async {
    final support = await getApplicationSupportDirectory();
    final dir = p.join(support.path, _voice);
    if (await File(p.join(dir, _modelFile)).exists()) return dir;
    final data = await rootBundle.load(_asset);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    for (final e in TarDecoder().decodeBytes(bytes)) {
      final out = p.join(support.path, e.name);
      if (e.isFile) {
        await Directory(p.dirname(out)).create(recursive: true);
        await File(out).writeAsBytes(e.content as List<int>);
      } else {
        await Directory(out).create(recursive: true);
      }
    }
    return dir;
  }

  // 16-bit PCM WAV — identical to poc/lib/tts/neural_tts_engine.dart `_wavFromFloat`.
  Uint8List _wav(Float32List s, int sr) {
    final n = s.length, dataSize = n * 2;
    final b = ByteData(44 + dataSize);
    var o = 0;
    void str(String x) { for (final c in x.codeUnits) b.setUint8(o++, c); }
    str('RIFF'); b.setUint32(o, 36 + dataSize, Endian.little); o += 4;
    str('WAVE'); str('fmt '); b.setUint32(o, 16, Endian.little); o += 4;
    b.setUint16(o, 1, Endian.little); o += 2;
    b.setUint16(o, 1, Endian.little); o += 2;
    b.setUint32(o, sr, Endian.little); o += 4;
    b.setUint32(o, sr * 2, Endian.little); o += 4;
    b.setUint16(o, 2, Endian.little); o += 2;
    b.setUint16(o, 16, Endian.little); o += 2;
    str('data'); b.setUint32(o, dataSize, Endian.little); o += 4;
    for (var i = 0; i < n; i++) {
      b.setInt16(o, (s[i] * 32767).round().clamp(-32768, 32767), Endian.little);
      o += 2;
    }
    return b.buffer.asUint8List();
  }

  Future<void> dispose() async { await _player.dispose(); _synth.dispose(); }
}
```

(Add `import 'dart:async';` for `Completer`.)

- [ ] **Step 4: Wire a "Speak" button in `main.dart`**

On a "Speak [idx]" button press: `await _narrator.speak(_sentences[_idx])`. Initialize `_narrator` once (`SpikeNarrator()..init()`), showing a "warming up…" state until `init()` completes.

- [ ] **Step 5: Run on device and record RTF**

Run on device; speak several short and several long sentences from Book IX.
Expected: clear audio; **RTF < 1.0** (faster than real-time) for normal sentences — record the actual values. RTF ≥ 1.0 on a mid-range device would threaten gapless playback and must be flagged.

**Verdict checkpoint 4 (on-device synthesis):** Record real-device RTF (vs the POC's emulator numbers). Note whether the long sentence "fast-forward" rush still occurs without chunking (it likely will — chunking is a known Phase-2 carry-forward; here just confirm the behavior matches the POC's finding).

- [ ] **Step 6: Commit**

```bash
git add spike/lib/tts/ spike/assets/ spike/pubspec.yaml spike/lib/main.dart
git commit -m "spike: port neural synth+play, measure on-device Piper RTF"
```

---

### Task 6: The integrated loop — audio-driven highlight on device

**Files:**
- Modify: `spike/lib/main.dart` (completion-gated play loop)

**Interfaces:**
- Consumes: `SpikeNarrator.speak` (Task 5), `highlightSentence` (Tasks 3–4).
- Produces: a "Play" button that runs the POC's completion-driven loop over the chapter, highlighting each sentence as it's spoken.

- [ ] **Step 1: Implement the play loop** (the POC's completion-driven pattern, with a monotonic token guard)

```dart
int _playToken = 0;

Future<void> _play({int from = 0}) async {
  final token = ++_playToken;
  for (var i = from; i < _sentences.length; i++) {
    if (token != _playToken) return; // superseded by a newer Play/stop
    await highlightSentence(i);       // highlight + page-follow
    setState(() => _idx = i);
    await _narrator.speak(_sentences[i]); // returns when audio finishes
  }
}

void _stop() => _playToken++;
```

Wire "Play" → `_play(from: _idx)` and "Stop" → `_stop()`.

- [ ] **Step 2: Run on device and verify the synced experience**

Run on device; press Play. Watch a full ~30-sentence run of Book IX.
Expected on device:
- The highlighted sentence matches the sentence being spoken, with no growing drift across the run.
- Pages turn automatically to keep the spoken sentence on screen.
- Capture a short screen recording (or a few timed screenshots) as evidence.

**Verdict checkpoint 5 (the whole point):** Highlight stays locked to audio across a chapter on a real device, with automatic page-following. This is the success condition from the spec's Phase-0 exit criteria.

- [ ] **Step 3: Measure tap latency and watch for the long-clip stall on device**

Add: tapping a sentence (or a "jump to [idx]") calls `_play(from: idx)`. Measure the wall-time from tap to first audio for a short and a long line (log `Stopwatch`). Also watch whether the POC's ~10 s long-clip completion stall reproduces on the real device.
Expected/record:
- Tap-to-audio latency (real device should be far below the emulator's ~1 s / ~3 s).
- **Whether the long-clip stall reproduces on real hardware** — this directly informs whether chunk-streaming is still needed in Phase 2 (POC flagged it as the most likely emulator-only artifact).

- [ ] **Step 4: Commit**

```bash
git add spike/lib/main.dart
git commit -m "spike: integrated completion-driven audio→highlight loop on device"
```

---

### Task 7: Record the verdict and the go/no-go decision

**Files:**
- Create: `docs/poc/04-reader-spike-findings.md`
- Modify: `docs/poc/README.md` (link the new doc)
- Modify: `README.md` (status line: spike result)

**Interfaces:**
- Consumes: every verdict checkpoint and measurement above.
- Produces: a committed findings doc with an explicit **PASS / FAIL** verdict and the recommended next action.

- [ ] **Step 1: Write `docs/poc/04-reader-spike-findings.md`** covering, with the real-device numbers gathered:
  - **Verdict:** PASS (lock `flutter_readium`) or FAIL (which fallback, and why).
  - Checkpoint results 1–5 (render, programmatic highlight, page-follow, RTF, integrated sync).
  - On-device **Piper RTF** vs the POC's emulator figures.
  - Whether the **long-clip stall** and high **tap latency** reproduced on real hardware (→ does Phase 2 still need chunk-streaming?).
  - Any flutter_readium friction discovered (did `LocatorText.highlight` suffice, or were `cssSelector`/`position` Locators required? did `goToLocator` page-follow work?).
  - Confirmed real-device model and OS version.

- [ ] **Step 2: If FAIL** — do not start the real build. Write up which fallback (foliate-js WebView → native Readium) and what specifically blocked `flutter_readium`. The narration subsystem (Tasks 2 & 5) carries over to any fallback unchanged; record that.

- [ ] **Step 3: If PASS** — state that the stack (`flutter_readium` + `sherpa_onnx` + the POC pipeline) is locked, and that Phase 1 (Library & reader) may begin. Note any Locator-richness requirement Phase 3 inherits from the spike.

- [ ] **Step 4: Update `docs/poc/README.md` and root `README.md`** with the one-line verdict and a link to `04-reader-spike-findings.md`.

- [ ] **Step 5: Commit**

```bash
git add docs/poc/04-reader-spike-findings.md docs/poc/README.md README.md
git commit -m "docs: reader-spike findings and stack go/no-go verdict"
```

---

## Self-Review (completed against the spec)

- **Spec coverage:** This plan implements spec §7 Phase 0 in full — render (Task 1), Locators/sentences (Task 2), programmatic highlight = risk #1/#2 (Task 3), page-follow (Task 4), on-device RTF = risk #13 (Task 5), integrated sync + long-clip/tap-latency device check (Task 6), go/no-go verdict with named fallbacks (Task 7). POC carry-forwards used: verse normalization (Task 2), `TtsSynthIsolate`/isolate synthesis + WAV encode (Task 5), completion-driven `_playToken` loop (Task 6).
- **Out of scope (correctly):** `just_audio` migration, look-ahead/2-player gapless, chunk-streaming, library/import, persistence, background playback, speed control — all deferred to later phases per the spec; the spike deliberately holds the audio pipeline at POC parity to isolate the reader variable.
- **Placeholder scan:** no TBD/TODO; every code step shows real code; flutter_readium calls use the verified v0.1.0 API (`openPublication`, `ReadiumReaderWidget`, `onTextLocatorChanged`, `applyDecorations`, `ReaderDecoration`/`ReaderDecorationStyle`/`DecorationStyle`, `Locator`/`LocatorText`/`Locations`, `goToLocator`). Two accessors are flagged as "confirm against analyzer" (`Publication.readingOrder`, `metadata.title`) because v0.1.0 docs don't pin them — this is honest spike-time API discovery, not a placeholder.
- **Type consistency:** `highlightSentence(int)`, `extractSentences(...)`/`sentencesFromHtml(...)`, `SpikeNarrator.speak → Duration`, `_playToken` guard, and `_hlGroup`/`copyAssetToFile` names are used consistently across tasks.

---

*Predecessor: [MVP design spec](../specs/2026-06-25-narrarr-mvp-design.md). On PASS, the next plan is Phase 1 (Library & reader).*
