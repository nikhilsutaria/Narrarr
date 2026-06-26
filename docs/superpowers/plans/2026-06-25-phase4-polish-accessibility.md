# Phase 4 — Polish & Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship download-on-demand voices with storage management, a screen-reader-friendly experience, dyslexia options, onboarding, an app settings/about surface, and clean empty/error states — so a stranger can install, import, download a voice, and use the app accessibly.

**Architecture:** See [spec](../specs/2026-06-25-phase4-polish-accessibility-design.md). `VoiceConfig` gains bundled-vs-downloadable fields; `DownloadingVoiceManager` adds download/verify/resume/delete on top of the Phase-2 `BundledVoiceManager` seam; active voice persists and flows to `NeuralNarrator.setVoice` and the Phase-3 timing key. Accessibility is a pure policy + `ExcludeSemantics` wiring + spacing options. Onboarding/settings/about are new screens wired from `app.dart`/library.

**Tech Stack:** Flutter/Dart, `dart:io HttpClient` (downloads, no new heavy dep), `crypto` (SHA-256, pure Dart), `archive` (tar, already present), `drift` (timing eviction, Phase 3), `flutter_readium` (`EPUBPreferences` spacing).

## Global Constraints

- **Android-first; keep shared Dart iOS-clean** — no Android-only APIs in shared code.
- **Toolchain pins (do not change):** AGP 8.9.1, Kotlin 2.3.21, `desugar_jdk_libs` 2.1.5, NDK 27.0.12077973, compileSdk 36, minSdk 24, JDK 21, `FlutterFragmentActivity`.
- **Offline-first:** amy-low stays bundled and is the default; the app must narrate with no network on first run.
- **No proprietary blobs (F-Droid path):** downloads use `dart:io HttpClient`; SHA-256 via the pure-Dart `crypto` package; voices come from Hugging Face `rhasspy/piper-voices` direct URLs.
- **Verify before trusting:** a downloaded voice counts as installed only after SHA-256 matches (when a checksum is known); a mismatch deletes the file.
- **Do not regress Phase 1–3:** reader, narration, background playback, and the sync/timing layer must keep working.
- **Each task: `flutter analyze` clean + `flutter test` green before commit.**

---

### Task 1: Voice descriptor + catalog (bundled vs downloadable)

**Why:** Everything downstream needs a voice model that knows whether it ships in the app or is fetched, its URL/checksum/size, and a catalog to list.

**Files:**
- Modify: `lib/narration/voice_manager.dart` (extend `VoiceConfig`; update `BundledVoiceManager` for nullable `asset`)
- Modify: `lib/narration/neural_narrator.dart` (uses `VoiceConfig.amyLow` — keep compiling)
- Create: `lib/narration/voice_catalog.dart`
- Test: `test/voice_catalog_test.dart`
- Modify: `test/voice_manager_test.dart` (construct via the new fields)

**Interfaces:**
- Produces:
  - `VoiceConfig{ String id; String displayName; String modelFile; String? asset; String? url; String? sha256; int sizeBytes; bool get isBundled; }`
  - `VoiceCatalog`: `static const VoiceConfig amyLow; static const ryanMedium; static const amyMedium; static const List<VoiceConfig> all; static VoiceConfig? byId(String id);`

- [ ] **Step 1: Write the failing catalog test**

```dart
// test/voice_catalog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_manager.dart';

void main() {
  test('amy-low is the bundled default', () {
    expect(VoiceCatalog.amyLow.isBundled, isTrue);
    expect(VoiceCatalog.amyLow.asset, isNotNull);
    expect(VoiceCatalog.amyLow.id, 'vits-piper-en_US-amy-low');
  });

  test('downloadable voices declare a url and are not bundled', () {
    expect(VoiceCatalog.ryanMedium.isBundled, isFalse);
    expect(VoiceCatalog.ryanMedium.url, isNotNull);
    expect(VoiceCatalog.ryanMedium.sizeBytes, greaterThan(0));
  });

  test('all contains the catalog and byId resolves', () {
    expect(VoiceCatalog.all, contains(VoiceCatalog.amyLow));
    expect(VoiceCatalog.byId('vits-piper-en_US-amy-low'), VoiceCatalog.amyLow);
    expect(VoiceCatalog.byId('nope'), isNull);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/voice_catalog_test.dart`
Expected: FAIL (`voice_catalog.dart` and new fields missing).

- [ ] **Step 3: Extend `VoiceConfig` in `voice_manager.dart`**

Replace the existing `VoiceConfig` class (the one with `id`/`asset`/`modelFile` + `amyLow`) with:

```dart
/// A Piper voice. Either **bundled** (ships as a `.tar` asset) or
/// **downloadable** (fetched from [url], integrity-checked with [sha256]).
class VoiceConfig {
  const VoiceConfig({
    required this.id,
    required this.displayName,
    required this.modelFile,
    this.asset,
    this.url,
    this.sha256,
    this.sizeBytes = 0,
  });

  final String id; // e.g. 'vits-piper-en_US-amy-low'
  final String displayName; // e.g. 'Amy (low)'
  final String modelFile; // .onnx filename inside the extracted dir
  final String? asset; // bundled tar asset path (null if download-only)
  final String? url; // download tar URL (null if bundled-only)
  final String? sha256; // expected tar checksum (download voices)
  final int sizeBytes; // approx download size for the UI

  bool get isBundled => asset != null;
}
```

Remove the old `static const amyLow = ...` from `VoiceConfig` (it moves to `VoiceCatalog`).

Update `BundledVoiceManager.ensureAvailable` to use the non-null asset:
```dart
    final bytes = await _loadAsset(voice.asset!);
```

- [ ] **Step 4: Create the catalog**

```dart
// lib/narration/voice_catalog.dart
import 'voice_manager.dart';

/// The voices Narrarr offers: one bundled default + optional downloads.
/// Download URLs are Hugging Face `rhasspy/piper-voices` direct files (open,
/// no account). `sha256` is filled when the real tars are checksummed on a
/// networked machine; until then download proceeds unverified (logged).
class VoiceCatalog {
  VoiceCatalog._();

  static const amyLow = VoiceConfig(
    id: 'vits-piper-en_US-amy-low',
    displayName: 'Amy (low) — bundled',
    asset: 'assets/voices/vits-piper-en_US-amy-low.tar',
    modelFile: 'en_US-amy-low.onnx',
    sizeBytes: 0,
  );

  static const ryanMedium = VoiceConfig(
    id: 'vits-piper-en_US-ryan-medium',
    displayName: 'Ryan (medium)',
    modelFile: 'en_US-ryan-medium.onnx',
    url:
        'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/medium/en_US-ryan-medium.onnx',
    sha256: null,
    sizeBytes: 63 * 1024 * 1024,
  );

  static const amyMedium = VoiceConfig(
    id: 'vits-piper-en_US-amy-medium',
    displayName: 'Amy (medium)',
    modelFile: 'en_US-amy-medium.onnx',
    url:
        'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/amy/medium/en_US-amy-medium.onnx',
    sha256: null,
    sizeBytes: 63 * 1024 * 1024,
  );

  static const List<VoiceConfig> all = [amyLow, ryanMedium, amyMedium];

  static VoiceConfig? byId(String id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }
}
```

> Note: real Piper voices ship as multiple files (`.onnx`, `.onnx.json`, plus shared `espeak-ng-data`). The Phase-2 bundled voice is a single `.tar` containing all of them. Task 2 handles the **tar** case (a `.tar` URL); if a catalog voice points at a bare `.onnx`, Task 2's downloader still stores it but extraction expects a tar — so catalog download URLs MUST point at a packaged `.tar`. Update the `url`s to the project's hosted `.tar` bundles when available; the HF `.onnx` URLs above are placeholders for size/shape and are flagged in manual checks. The download/verify/extract **mechanism** is what this phase delivers and tests.

- [ ] **Step 5: Fix references to the moved `amyLow`**

In `lib/narration/neural_narrator.dart`, change the default and import:
```dart
import 'voice_catalog.dart';
```
```dart
  NeuralNarrator({this.voice = VoiceCatalog.amyLow, VoiceManager? voiceManager})
```
In `test/voice_manager_test.dart`, replace any `VoiceConfig.amyLow` with `VoiceCatalog.amyLow` and add `import 'package:narrarr/narration/voice_catalog.dart';`. If the test constructs a `VoiceConfig` inline, add the now-required `displayName`.

- [ ] **Step 6: Run tests**

Run: `flutter test test/voice_catalog_test.dart test/voice_manager_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze + full suite**

Run: `flutter analyze lib && flutter test`
Expected: clean; all green.

- [ ] **Step 8: Commit**

```bash
git add lib/narration/voice_manager.dart lib/narration/voice_catalog.dart lib/narration/neural_narrator.dart test/voice_catalog_test.dart test/voice_manager_test.dart
git commit -m "Phase 4 Task 1: voice descriptor (bundled/downloadable) + VoiceCatalog"
```

---

### Task 2: `DownloadingVoiceManager` — download, verify SHA-256, extract, resume, delete

**Why:** The core of #11. Fetches a voice, checks integrity, extracts, supports resume and deletion. Built on the Phase-2 bundled seam so bundled voices are unchanged.

**Files:**
- Modify: `pubspec.yaml` (add `crypto`)
- Modify: `lib/narration/voice_manager.dart` (shared `extractVoiceTar`; `DownloadingVoiceManager`)
- Test: `test/downloading_voice_manager_test.dart`

**Interfaces:**
- Consumes: `VoiceConfig` (Task 1), `BundledVoiceManager` (Phase 2), `archive` `TarDecoder`, `crypto` `sha256`.
- Produces:
  - `typedef VoiceBytesFetcher = Future<List<int>> Function(Uri url, {int offset});`
  - `class DownloadingVoiceManager implements VoiceManager { DownloadingVoiceManager({Directory? baseDir, VoiceBytesFetcher? fetch, Future<Uint8List> Function(String asset)? loadAsset}); Future<String> ensureAvailable(VoiceConfig voice, {void Function(double)? onProgress}); Future<bool> isInstalled(VoiceConfig voice); Future<void> delete(VoiceConfig voice); Future<int> installedSize(); }`

- [ ] **Step 1: Add `crypto`**

In `pubspec.yaml` under `dependencies:` add:
```yaml
  crypto: ^3.0.6
```
Run: `flutter pub get`
Expected: resolves cleanly.

- [ ] **Step 2: Write the failing test**

```dart
// test/downloading_voice_manager_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dvm'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // Build a tar containing a fake model file, return (bytes, sha256-hex).
  (Uint8List, String) fakeVoiceTar(String voiceId, String modelFile) {
    final archive = Archive()
      ..addFile(ArchiveFile('$voiceId/$modelFile', 4, [1, 2, 3, 4]));
    final bytes = Uint8List.fromList(TarEncoder().encode(archive));
    return (bytes, sha256.convert(bytes).toString());
  }

  VoiceConfig downloadable({String? checksum}) {
    final (_, hex) = fakeVoiceTar('voiceX', 'voiceX.onnx');
    return VoiceConfig(
      id: 'voiceX',
      displayName: 'Voice X',
      modelFile: 'voiceX.onnx',
      url: 'https://example.test/voiceX.tar',
      sha256: checksum ?? hex,
      sizeBytes: 100,
    );
  }

  test('downloads, verifies checksum, extracts the model dir', () async {
    final (bytes, hex) = fakeVoiceTar('voiceX', 'voiceX.onnx');
    final v = VoiceConfig(
      id: 'voiceX',
      displayName: 'Voice X',
      modelFile: 'voiceX.onnx',
      url: 'https://example.test/voiceX.tar',
      sha256: hex,
      sizeBytes: bytes.length,
    );
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      fetch: (uri, {offset = 0}) async => bytes.sublist(offset),
    );
    final dir = await m.ensureAvailable(v);
    expect(File(p.join(dir, 'voiceX.onnx')).existsSync(), isTrue);
    expect(await m.isInstalled(v), isTrue);
  });

  test('rejects a checksum mismatch and does not install', () async {
    final (bytes, _) = fakeVoiceTar('voiceX', 'voiceX.onnx');
    final v = downloadable(checksum: 'deadbeef');
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      fetch: (uri, {offset = 0}) async => bytes.sublist(offset),
    );
    await expectLater(m.ensureAvailable(v), throwsA(isA<Exception>()));
    expect(await m.isInstalled(v), isFalse);
  });

  test('delete removes an installed voice', () async {
    final (bytes, hex) = fakeVoiceTar('voiceX', 'voiceX.onnx');
    final v = VoiceConfig(
      id: 'voiceX',
      displayName: 'Voice X',
      modelFile: 'voiceX.onnx',
      url: 'https://example.test/voiceX.tar',
      sha256: hex,
    );
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      fetch: (uri, {offset = 0}) async => bytes.sublist(offset),
    );
    await m.ensureAvailable(v);
    await m.delete(v);
    expect(await m.isInstalled(v), isFalse);
  });

  test('bundled voice delegates to BundledVoiceManager', () async {
    final (bytes, _) = fakeVoiceTar('vits-piper-en_US-amy-low', 'en_US-amy-low.onnx');
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      loadAsset: (asset) async => bytes,
    );
    final dir = await m.ensureAvailable(VoiceCatalog.amyLow);
    expect(File(p.join(dir, 'en_US-amy-low.onnx')).existsSync(), isTrue);
  });
}
```

- [ ] **Step 3: Run to verify failure**

Run: `flutter test test/downloading_voice_manager_test.dart`
Expected: FAIL (`DownloadingVoiceManager` not defined).

- [ ] **Step 4: Factor the shared tar extractor**

In `lib/narration/voice_manager.dart`, add a top-level helper and use it from `BundledVoiceManager`:
```dart
/// Extract a voice `.tar` (model + tokens + espeak-ng-data) into [support].
Future<void> extractVoiceTar(Uint8List bytes, Directory support) async {
  for (final entry in TarDecoder().decodeBytes(bytes)) {
    final outPath = p.join(support.path, entry.name);
    if (entry.isFile) {
      await Directory(p.dirname(outPath)).create(recursive: true);
      await File(outPath).writeAsBytes(entry.content as List<int>);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}
```
Replace the inline extraction loop in `BundledVoiceManager.ensureAvailable` with:
```dart
    final bytes = await _loadAsset(voice.asset!);
    await extractVoiceTar(bytes, support);
    return modelDir;
```

- [ ] **Step 5: Implement `DownloadingVoiceManager`**

Append to `lib/narration/voice_manager.dart`:
```dart
import 'package:crypto/crypto.dart';

/// Fetches [bytes] for [url] starting at [offset] (for resume). Injected for
/// tests; production uses [httpVoiceFetcher].
typedef VoiceBytesFetcher = Future<List<int>> Function(Uri url, {int offset});

/// Downloads, verifies, extracts and manages downloadable voices, delegating
/// bundled voices to [BundledVoiceManager]. The seam Phase 2 left for #11.
class DownloadingVoiceManager implements VoiceManager {
  DownloadingVoiceManager({
    Directory? baseDir,
    VoiceBytesFetcher? fetch,
    Future<Uint8List> Function(String asset)? loadAsset,
  })  : _baseDir = baseDir,
        _fetch = fetch ?? httpVoiceFetcher,
        _bundled = BundledVoiceManager(baseDir: baseDir, loadAsset: loadAsset);

  final Directory? _baseDir;
  final VoiceBytesFetcher _fetch;
  final BundledVoiceManager _bundled;

  Future<Directory> _base() async =>
      _baseDir ?? await getApplicationSupportDirectory();

  String _modelDirPath(Directory support, VoiceConfig v) =>
      p.join(support.path, v.id);

  @override
  Future<String> ensureAvailable(VoiceConfig voice,
      {void Function(double)? onProgress}) async {
    if (voice.isBundled) return _bundled.ensureAvailable(voice);

    final support = await _base();
    final modelDir = _modelDirPath(support, voice);
    if (await File(p.join(modelDir, voice.modelFile)).exists()) {
      return modelDir; // already installed
    }

    final url = Uri.parse(voice.url!);
    final partFile = File(p.join(support.path, '${voice.id}.part'));
    await partFile.parent.create(recursive: true);

    final resumeFrom = await partFile.exists() ? await partFile.length() : 0;
    final fresh = await _fetch(url, offset: resumeFrom);
    final sink = partFile.openSync(mode: FileMode.writeOnlyAppend);
    try {
      sink.writeFromSync(fresh);
    } finally {
      sink.closeSync();
    }
    onProgress?.call(1.0);

    final bytes = await partFile.readAsBytes();
    final expected = voice.sha256;
    if (expected != null && sha256.convert(bytes).toString() != expected) {
      await partFile.delete();
      throw Exception('Voice ${voice.id} failed checksum verification');
    }

    await extractVoiceTar(Uint8List.fromList(bytes), support);
    await partFile.delete();
    return modelDir;
  }

  Future<bool> isInstalled(VoiceConfig voice) async {
    if (voice.isBundled) {
      final support = await _base();
      return File(p.join(_modelDirPath(support, voice), voice.modelFile))
          .exists();
    }
    final support = await _base();
    return File(p.join(_modelDirPath(support, voice), voice.modelFile)).exists();
  }

  Future<void> delete(VoiceConfig voice) async {
    final support = await _base();
    final dir = Directory(_modelDirPath(support, voice));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<int> installedSize() async {
    final support = await _base();
    var total = 0;
    await for (final e in support.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }
}

/// Production fetcher: HTTP GET with a Range header for resume.
Future<List<int>> httpVoiceFetcher(Uri url, {int offset = 0}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    if (offset > 0) req.headers.add(HttpHeaders.rangeHeader, 'bytes=$offset-');
    final resp = await req.close();
    final out = <int>[];
    await for (final chunk in resp) {
      out.addAll(chunk);
    }
    return out;
  } finally {
    client.close();
  }
}
```

Add `import 'dart:io';` is already present; ensure `import 'dart:typed_data';` present (it is). The `crypto` import goes at the top with the others.

- [ ] **Step 6: Run the test**

Run: `flutter test test/downloading_voice_manager_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 7: Analyze + full suite**

Run: `flutter analyze lib && flutter test`
Expected: clean; all green.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/narration/voice_manager.dart test/downloading_voice_manager_test.dart
git commit -m "Phase 4 Task 2: DownloadingVoiceManager (download, SHA-256 verify, extract, resume, delete)"
```

---

### Task 3: Active-voice persistence + engine `setVoice` + timing key

**Why:** Persist which voice is active, make the engine switch to it, and keep Phase-3 timings correctly keyed by the active voice.

**Files:**
- Create: `lib/narration/voice_settings.dart` (`VoiceSettings` + `VoiceSettingsStore`)
- Modify: `lib/narration/neural_narrator.dart` (`setVoice`)
- Test: `test/voice_settings_test.dart`
- Test: `test/neural_narrator_voice_test.dart` (setVoice updates the active voice/name)

**Interfaces:**
- Consumes: `VoiceConfig`/`VoiceCatalog` (Task 1), `VoiceManager` (Phase 2/Task 2).
- Produces:
  - `class VoiceSettings { String activeVoiceId; }` + `class VoiceSettingsStore { Future<VoiceSettings> load(); Future<void> save(VoiceSettings); }` (default `VoiceCatalog.amyLow.id`).
  - `NeuralNarrator`: `VoiceConfig get voice;` (already a field — make it mutable) + `Future<void> setVoice(VoiceConfig)`.

- [ ] **Step 1: Failing settings test**

```dart
// test/voice_settings_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('vs'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('defaults to the bundled amy voice', () async {
    final store = VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json')));
    final s = await store.load();
    expect(s.activeVoiceId, VoiceCatalog.amyLow.id);
  });

  test('round-trips the active voice id', () async {
    final f = File(p.join(tmp.path, 'v.json'));
    final store = VoiceSettingsStore(file: f);
    await store.save(VoiceSettings(activeVoiceId: 'vits-piper-en_US-ryan-medium'));
    final s = await VoiceSettingsStore(file: f).load();
    expect(s.activeVoiceId, 'vits-piper-en_US-ryan-medium');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/voice_settings_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `voice_settings.dart`**

```dart
// lib/narration/voice_settings.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'voice_catalog.dart';

/// Which voice the user has selected as active.
class VoiceSettings {
  VoiceSettings({String? activeVoiceId})
      : activeVoiceId = activeVoiceId ?? VoiceCatalog.amyLow.id;
  String activeVoiceId;

  Map<String, dynamic> toJson() => {'activeVoiceId': activeVoiceId};
  factory VoiceSettings.fromJson(Map<String, dynamic> j) =>
      VoiceSettings(activeVoiceId: j['activeVoiceId'] as String?);
}

/// Persists [VoiceSettings] as a small JSON file in app-support storage.
class VoiceSettingsStore {
  VoiceSettingsStore({File? file}) : _injected = file;
  final File? _injected;

  Future<File> _file() async =>
      _injected ??
      File(p.join((await getApplicationSupportDirectory()).path,
          'voice_settings.json'));

  Future<VoiceSettings> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return VoiceSettings();
      return VoiceSettings.fromJson(
          (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
    } catch (_) {
      return VoiceSettings();
    }
  }

  Future<void> save(VoiceSettings s) async {
    final f = await _file();
    await f.writeAsString(jsonEncode(s.toJson()));
  }
}
```

- [ ] **Step 4: Run the settings test**

Run: `flutter test test/voice_settings_test.dart`
Expected: PASS.

- [ ] **Step 5: Failing engine `setVoice` test**

```dart
// test/neural_narrator_voice_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/neural_narrator.dart';
import 'package:narrarr/narration/voice_catalog.dart';

void main() {
  test('setVoice updates the active voice and engine name when idle', () async {
    final n = NeuralNarrator(voice: VoiceCatalog.amyLow);
    expect(n.voice.id, VoiceCatalog.amyLow.id);
    await n.setVoice(VoiceCatalog.ryanMedium);
    expect(n.voice.id, VoiceCatalog.ryanMedium.id);
    expect(n.name, contains('ryan'));
  });
}
```

- [ ] **Step 6: Run to verify failure**

Run: `flutter test test/neural_narrator_voice_test.dart`
Expected: FAIL (`voice` is `final`; no `setVoice`).

- [ ] **Step 7: Make `voice` mutable + add `setVoice`**

In `lib/narration/neural_narrator.dart`, change `final VoiceConfig voice;` to:
```dart
  VoiceConfig voice;
```
Add after `init()`:
```dart
  /// Switch the active voice. If the engine was already initialised, re-init the
  /// synth isolate against the new model; otherwise just record the selection
  /// (the lazy [init] will pick it up). Safe to call while idle.
  Future<void> setVoice(VoiceConfig next) async {
    if (next.id == voice.id) return;
    voice = next;
    if (_inited) {
      await stop();
      _synth.dispose();
      _inited = false;
      _cache.clear();
      await init();
    }
  }
```

> `init()` already resolves `voice` via `_voiceManager.ensureAvailable(voice)`, so re-init loads the new model. The default `_voiceManager` is `BundledVoiceManager`; for downloaded voices the handler injects a `DownloadingVoiceManager` (Task 4 wiring) so `ensureAvailable` finds the extracted dir.

- [ ] **Step 8: Run tests**

Run: `flutter test test/neural_narrator_voice_test.dart test/voice_settings_test.dart`
Expected: PASS.

- [ ] **Step 9: Use `DownloadingVoiceManager` as the engine's default manager**

In `lib/narration/narration_audio_handler.dart`, the handler builds `NeuralNarrator()`. Give the engine a `DownloadingVoiceManager` so downloaded voices resolve:
```dart
      NarrationController(
        engine: NeuralNarrator(voiceManager: DownloadingVoiceManager()),
      ),
```
Add the import:
```dart
import 'voice_manager.dart';
```

- [ ] **Step 10: Analyze + full suite + build**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: clean; green; APK builds.

- [ ] **Step 11: Commit**

```bash
git add lib/narration/voice_settings.dart lib/narration/neural_narrator.dart lib/narration/narration_audio_handler.dart test/voice_settings_test.dart test/neural_narrator_voice_test.dart
git commit -m "Phase 4 Task 3: active-voice persistence + NeuralNarrator.setVoice + DownloadingVoiceManager wiring"
```

---

### Task 4: Voice management screen + active-voice wiring in the reader

**Why:** The user-facing surface to download, select, and delete voices, and the wiring so the chosen voice actually narrates and keys timings.

**Files:**
- Create: `lib/narration/voice_screen.dart` (`VoiceScreen`)
- Modify: `lib/reader/reader_screen.dart` (read active voice; pass to handler/controller; `setVoice`)
- Test: `test/voice_screen_test.dart` (widget: lists catalog; shows Active/Download/Delete)

**Interfaces:**
- Consumes: `VoiceCatalog`, `DownloadingVoiceManager`, `VoiceSettingsStore` (Tasks 1–3), `TimingRepository.evictVoice` (Phase 3).
- Produces: `VoiceScreen` (stateful), navigated to from settings (Task 6).

- [ ] **Step 1: Failing widget test**

```dart
// test/voice_screen_test.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:narrarr/narration/voice_screen.dart';
import 'package:narrarr/narration/voice_settings.dart';
import 'package:path/path.dart' as p;

void main() {
  testWidgets('lists catalog voices with amy marked active', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('vscreen');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await tester.pumpWidget(MaterialApp(
      home: VoiceScreen(
        manager: DownloadingVoiceManager(baseDir: tmp),
        settingsStore: VoiceSettingsStore(file: File(p.join(tmp.path, 'v.json'))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Amy (low) — bundled'), findsOneWidget);
    expect(find.text('Ryan (medium)'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget); // amy is active by default
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/voice_screen_test.dart`
Expected: FAIL (`voice_screen.dart` missing).

- [ ] **Step 3: Implement `VoiceScreen`**

```dart
// lib/narration/voice_screen.dart
import 'package:flutter/material.dart';

import 'voice_catalog.dart';
import 'voice_manager.dart';
import 'voice_settings.dart';

/// Manage offline voices: download, select active, delete. Bundled amy is
/// always available and cannot be deleted.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.manager,
    required this.settingsStore,
  });

  final DownloadingVoiceManager manager;
  final VoiceSettingsStore settingsStore;

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen> {
  String _activeId = VoiceCatalog.amyLow.id;
  final _installed = <String, bool>{};
  final _busy = <String, bool>{};
  final _error = <String, String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await widget.settingsStore.load();
    for (final v in VoiceCatalog.all) {
      _installed[v.id] = await widget.manager.isInstalled(v);
    }
    if (mounted) setState(() => _activeId = s.activeVoiceId);
  }

  Future<void> _download(VoiceConfig v) async {
    setState(() {
      _busy[v.id] = true;
      _error.remove(v.id);
    });
    try {
      await widget.manager.ensureAvailable(v);
      _installed[v.id] = true;
    } catch (e) {
      _error[v.id] = 'Download failed. Tap to retry.';
    } finally {
      if (mounted) setState(() => _busy[v.id] = false);
    }
  }

  Future<void> _select(VoiceConfig v) async {
    await widget.settingsStore.save(VoiceSettings(activeVoiceId: v.id));
    if (mounted) setState(() => _activeId = v.id);
  }

  Future<void> _delete(VoiceConfig v) async {
    await widget.manager.delete(v);
    _installed[v.id] = false;
    if (_activeId == v.id) await _select(VoiceCatalog.amyLow);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voices')),
      body: ListView(
        children: [
          for (final v in VoiceCatalog.all) _tile(v),
        ],
      ),
    );
  }

  Widget _tile(VoiceConfig v) {
    final installed = _installed[v.id] ?? v.isBundled;
    final active = _activeId == v.id;
    final busy = _busy[v.id] ?? false;
    final err = _error[v.id];

    Widget trailing;
    if (busy) {
      trailing = const SizedBox(
          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (active) {
      trailing = const Text('Active');
    } else if (installed) {
      trailing = TextButton(
        onPressed: () => _select(v),
        child: const Text('Use'),
      );
    } else {
      trailing = TextButton(
        onPressed: () => _download(v),
        child: Text(err != null ? 'Retry' : 'Download'),
      );
    }

    return ListTile(
      title: Text(v.displayName),
      subtitle: Text(err ??
          (v.isBundled
              ? 'Bundled • offline'
              : '${(v.sizeBytes / 1024 / 1024).round()} MB download')),
      trailing: trailing,
      onLongPress: (installed && !v.isBundled) ? () => _delete(v) : null,
    );
  }
}
```

- [ ] **Step 4: Run the widget test**

Run: `flutter test test/voice_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the active voice into the reader**

In `lib/reader/reader_screen.dart`, replace the hard-coded `_voiceId` with the persisted active voice. Add a field and load it in `_init`:
```dart
import '../narration/voice_settings.dart';
import '../narration/voice_catalog.dart';
```
Replace:
```dart
  // The bundled offline default; Phase 4 makes this user-selectable.
  static const _voiceId = 'vits-piper-en_US-amy-low';
```
with:
```dart
  String _voiceId = VoiceCatalog.amyLow.id;
```
In `_init`, before `_open()`:
```dart
    final vs = await VoiceSettingsStore().load();
    _voiceId = vs.activeVoiceId;
    final selected = VoiceCatalog.byId(_voiceId) ?? VoiceCatalog.amyLow;
    await _handler!.controller.engine.setVoiceIfNeeded(selected);
```

- [ ] **Step 6: Add `setVoiceIfNeeded` to the `TtsEngine` interface (safe no-op default)**

`setVoice` is on `NeuralNarrator` but not the `TtsEngine` interface (the reader holds an `engine`). Add a neutral method to the interface so the reader can call it on any engine:

In `lib/narration/tts_engine.dart`, add:
```dart
  /// Switch the active voice if this engine supports voices. Default: no-op.
  Future<void> setVoiceIfNeeded(Object voice) async {}
```
In `lib/narration/neural_narrator.dart`, implement it by forwarding to `setVoice` when the argument is a `VoiceConfig`:
```dart
  @override
  Future<void> setVoiceIfNeeded(Object voice) async {
    if (voice is VoiceConfig) await setVoice(voice);
  }
```
Add the override stub to `FakeTtsEngine` (`test/support/fake_tts_engine.dart`):
```dart
  @override
  Future<void> setVoiceIfNeeded(Object voice) async {}
```

> Using `Object` keeps `TtsEngine` free of a `VoiceConfig` import (the interface stays engine-agnostic). The reader passes a `VoiceConfig`; `NeuralNarrator` type-checks it.

- [ ] **Step 7: Analyze + full suite + build**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: clean; green; APK builds.

- [ ] **Step 8: Commit**

```bash
git add lib/narration/voice_screen.dart lib/narration/tts_engine.dart lib/narration/neural_narrator.dart lib/reader/reader_screen.dart test/support/fake_tts_engine.dart test/voice_screen_test.dart
git commit -m "Phase 4 Task 4: voice management screen + active-voice wiring in the reader"
```

---

### Task 5: Accessibility — screen-reader policy, content-semantics exclusion, dyslexia spacing

**Why:** Resolve the TalkBack-vs-narration conflict (#12) and give dyslexia-friendly spacing controls.

**Files:**
- Create: `lib/a11y/a11y_policy.dart`
- Test: `test/a11y_policy_test.dart`
- Modify: `lib/reader/reader_settings.dart` (spacing fields + EPUBPreferences mapping)
- Modify: `lib/reader/reader_settings_sheet.dart` (spacing sliders)
- Modify: `lib/reader/reader_screen.dart` (`ExcludeSemantics` around the reader content while self-narrating)
- Test: `test/reader_settings_test.dart` (spacing round-trip + mapping)

**Interfaces:**
- Produces:
  - `bool shouldExcludeContentSemantics({required bool screenReaderOn, required bool narrating})` in `a11y_policy.dart`.
  - `ReaderSettings.letterSpacing`, `.wordSpacing`, `.paragraphSpacing` (doubles) with JSON + `EPUBPreferences` mapping.

- [ ] **Step 1: Failing a11y policy test**

```dart
// test/a11y_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/a11y/a11y_policy.dart';

void main() {
  test('exclude content semantics only when screen reader is on AND narrating',
      () {
    expect(
        shouldExcludeContentSemantics(screenReaderOn: true, narrating: true),
        isTrue);
    expect(
        shouldExcludeContentSemantics(screenReaderOn: true, narrating: false),
        isFalse);
    expect(
        shouldExcludeContentSemantics(screenReaderOn: false, narrating: true),
        isFalse);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/a11y_policy_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement the policy**

```dart
// lib/a11y/a11y_policy.dart

/// When the OS screen reader (TalkBack) is on AND the app is narrating aloud,
/// the page text and the app's own voice both speak. Resolve by removing the
/// book content from the accessibility tree while self-narrating; transport
/// controls stay accessible. Pure so it is unit-testable.
bool shouldExcludeContentSemantics({
  required bool screenReaderOn,
  required bool narrating,
}) =>
    screenReaderOn && narrating;
```

- [ ] **Step 4: Run the policy test**

Run: `flutter test test/a11y_policy_test.dart`
Expected: PASS.

- [ ] **Step 5: Failing reader-settings spacing test**

```dart
// test/reader_settings_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/reader/reader_settings.dart';

void main() {
  test('spacing fields round-trip through json', () {
    final s = ReaderSettings(
        letterSpacing: 0.06, wordSpacing: 0.16, paragraphSpacing: 1.4);
    final back = ReaderSettings.fromJson(s.toJson());
    expect(back.letterSpacing, 0.06);
    expect(back.wordSpacing, 0.16);
    expect(back.paragraphSpacing, 1.4);
  });

  test('spacing maps into EPUBPreferences', () {
    final prefs = ReaderSettings(letterSpacing: 0.06).toEpubPreferences();
    expect(prefs.letterSpacing, 0.06);
  });
}
```

- [ ] **Step 6: Run to verify failure**

Run: `flutter test test/reader_settings_test.dart`
Expected: FAIL.

- [ ] **Step 7: Add spacing to `ReaderSettings`**

In `lib/reader/reader_settings.dart`, add constructor params + fields (defaults 0 = publisher default), include them in `toEpubPreferences`, `toJson`, `fromJson`, and `copyWith`:

Constructor:
```dart
  ReaderSettings({
    this.font = ReaderFont.atkinson,
    this.fontSizePercent = 110,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
    this.letterSpacing = 0.0,
    this.wordSpacing = 0.0,
    this.paragraphSpacing = 0.0,
  });
```
Fields:
```dart
  double letterSpacing; // 0.0–0.25 (em)
  double wordSpacing; // 0.0–0.5 (em)
  double paragraphSpacing; // 0.0–2.0 (em)
```
In `toEpubPreferences`, add to the `EPUBPreferences(...)`:
```dart
      letterSpacing: letterSpacing == 0 ? null : letterSpacing,
      wordSpacing: wordSpacing == 0 ? null : wordSpacing,
      paragraphSpacing: paragraphSpacing == 0 ? null : paragraphSpacing,
```
In `toJson`:
```dart
        'letterSpacing': letterSpacing,
        'wordSpacing': wordSpacing,
        'paragraphSpacing': paragraphSpacing,
```
In `fromJson`:
```dart
        letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0.0,
        wordSpacing: (j['wordSpacing'] as num?)?.toDouble() ?? 0.0,
        paragraphSpacing: (j['paragraphSpacing'] as num?)?.toDouble() ?? 0.0,
```
In `copyWith`, add the three params and pass-through.

- [ ] **Step 8: Run reader-settings tests**

Run: `flutter test test/reader_settings_test.dart`
Expected: PASS.

- [ ] **Step 9: Add spacing sliders to the settings sheet**

In `lib/reader/reader_settings_sheet.dart`, add three `Slider`s (Letter spacing 0–0.25, Word spacing 0–0.5, Paragraph spacing 0–2.0) under a "Dyslexia-friendly spacing" label, each calling `onChanged(current.copyWith(...))`. Mirror the existing slider rows; label each with `Semantics(label: ...)`. (Match the file's existing slider pattern exactly.)

- [ ] **Step 10: Wrap reader content in `ExcludeSemantics` while self-narrating**

In `lib/reader/reader_screen.dart`, import the policy:
```dart
import '../a11y/a11y_policy.dart';
```
In `build`, compute the flag and wrap the `ReadiumReaderWidget`:
```dart
    final screenReaderOn = MediaQuery.of(context).accessibleNavigation;
    final excludeContent = shouldExcludeContentSemantics(
      screenReaderOn: screenReaderOn,
      narrating: _active,
    );
```
Wrap the body:
```dart
      body: ExcludeSemantics(
        excluding: excludeContent,
        child: ReadiumReaderWidget(
          publication: pub,
          initialLocator: _initialLocator,
          loadingWidget: const Center(child: CircularProgressIndicator()),
          onTextSelected: _seekToSelection,
        ),
      ),
```

- [ ] **Step 11: Analyze + full suite + build**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: clean; green; APK builds.

- [ ] **Step 12: Commit**

```bash
git add lib/a11y/a11y_policy.dart lib/reader/reader_settings.dart lib/reader/reader_settings_sheet.dart lib/reader/reader_screen.dart test/a11y_policy_test.dart test/reader_settings_test.dart
git commit -m "Phase 4 Task 5: screen-reader policy + content-semantics exclusion + dyslexia spacing"
```

---

### Task 6: Onboarding, settings/about surface, empty/error states

**Why:** Complete the "stranger can use it without guidance" exit: a first-run intro, a place to reach voices/settings/about, and confirmed empty/error states.

**Files:**
- Create: `lib/onboarding/onboarding_store.dart` (`OnboardingStore` — seen flag)
- Create: `lib/onboarding/onboarding_screen.dart` (`OnboardingScreen`)
- Create: `lib/settings/settings_screen.dart` (`SettingsScreen`)
- Modify: `lib/app.dart` (show onboarding first-run, then library)
- Modify: `lib/library/library_screen.dart` (settings action in the app bar; confirm empty state)
- Test: `test/onboarding_store_test.dart`
- Test: `test/onboarding_screen_test.dart` (advances and calls onDone)

**Interfaces:**
- Consumes: `VoiceScreen` (Task 4), `ReaderSettingsStore`/`VoiceSettingsStore`.
- Produces:
  - `class OnboardingStore { Future<bool> seen(); Future<void> markSeen(); }` (injectable file).
  - `OnboardingScreen({required VoidCallback onDone})`, `SettingsScreen()`.

- [ ] **Step 1: Failing onboarding-store test**

```dart
// test/onboarding_store_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/onboarding/onboarding_store.dart';
import 'package:path/path.dart' as p;

void main() {
  test('seen flips after markSeen', () async {
    final tmp = Directory.systemTemp.createTempSync('ob');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = OnboardingStore(file: File(p.join(tmp.path, 'ob.json')));
    expect(await store.seen(), isFalse);
    await store.markSeen();
    expect(await store.seen(), isTrue);
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/onboarding_store_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement `OnboardingStore`**

```dart
// lib/onboarding/onboarding_store.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Tracks whether the first-run onboarding has been shown.
class OnboardingStore {
  OnboardingStore({File? file}) : _injected = file;
  final File? _injected;

  Future<File> _file() async =>
      _injected ??
      File(p.join((await getApplicationSupportDirectory()).path,
          'onboarding.json'));

  Future<bool> seen() async => (await _file()).exists();

  Future<void> markSeen() async {
    final f = await _file();
    await f.writeAsString('{"seen":true}');
  }
}
```

- [ ] **Step 4: Run the store test**

Run: `flutter test test/onboarding_store_test.dart`
Expected: PASS.

- [ ] **Step 5: Failing onboarding-screen test**

```dart
// test/onboarding_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('shows intro and fires onDone on Get started', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: () => done = true),
    ));
    expect(find.textContaining('Narrarr'), findsWidgets);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(done, isTrue);
  });
}
```

- [ ] **Step 6: Run to verify failure**

Run: `flutter test test/onboarding_screen_test.dart`
Expected: FAIL.

- [ ] **Step 7: Implement `OnboardingScreen`**

```dart
// lib/onboarding/onboarding_screen.dart
import 'package:flutter/material.dart';

/// First-run intro: what Narrarr is and the privacy promise. Single screen with
/// a clear primary action.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome to Narrarr', style: text.headlineMedium),
              const SizedBox(height: 16),
              Text(
                'Read your own EPUBs while an offline neural voice reads along, '
                'highlighting each sentence. Pocket your phone and just listen '
                'with lock-screen controls.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              Text(
                'Fully offline. No account. No telemetry. Nothing leaves your '
                'device.',
                style: text.bodyLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDone,
                  child: const Text('Get started'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Run the screen test**

Run: `flutter test test/onboarding_screen_test.dart`
Expected: PASS.

- [ ] **Step 9: Implement `SettingsScreen`**

```dart
// lib/settings/settings_screen.dart
import 'package:flutter/material.dart';

import '../narration/voice_manager.dart';
import '../narration/voice_screen.dart';
import '../narration/voice_settings.dart';

/// App settings / about. Entry point to voice management and the privacy note.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Voices'),
            subtitle: const Text('Download, choose, and remove offline voices'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VoiceScreen(
                manager: DownloadingVoiceManager(),
                settingsStore: VoiceSettingsStore(),
              ),
            )),
          ),
          const ListTile(
            leading: Icon(Icons.accessibility_new),
            title: Text('Accessibility'),
            subtitle: Text(
                'Atkinson Hyperlegible font and adjustable spacing are in the '
                'reader’s text settings. With TalkBack on, the page is not '
                'double-read while Narrarr narrates.'),
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'Narrarr',
            applicationVersion: '1.0.0',
            aboutBoxChildren: [
              Text(
                  'Immersion reading for your own EPUBs. Fully offline, no '
                  'account, no telemetry. Open source.'),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 10: Wire onboarding into `app.dart`**

Replace `lib/app.dart` `home:` with a first-run gate:
```dart
import 'package:flutter/material.dart';

import 'library/library_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'onboarding/onboarding_store.dart';
import 'ui/theme.dart';

class NarrarrApp extends StatelessWidget {
  const NarrarrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Narrarr',
      debugShowCheckedModeBanner: false,
      theme: narrarrLightTheme,
      darkTheme: narrarrDarkTheme,
      home: const _RootGate(),
    );
  }
}

/// Shows onboarding on first run, then the library.
class _RootGate extends StatefulWidget {
  const _RootGate();
  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  final _store = OnboardingStore();
  bool? _seen;

  @override
  void initState() {
    super.initState();
    _store.seen().then((v) => setState(() => _seen = v));
  }

  @override
  Widget build(BuildContext context) {
    if (_seen == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_seen == false) {
      return OnboardingScreen(onDone: () async {
        await _store.markSeen();
        if (mounted) setState(() => _seen = true);
      });
    }
    return const LibraryScreen();
  }
}
```

- [ ] **Step 11: Add a settings action to the library app bar + confirm empty state**

In `lib/library/library_screen.dart`, add an `IconButton` (gear) to the `AppBar.actions` that pushes `SettingsScreen`:
```dart
import '../settings/settings_screen.dart';
```
```dart
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
```
Confirm the empty-library state shows a friendly "Import your first book" message; if absent, add a centered prompt when the book list is empty. (Match the screen's existing build structure.)

- [ ] **Step 12: Analyze + full suite + build**

Run: `flutter analyze lib && flutter test && flutter build apk --debug`
Expected: clean; green; APK builds.

- [ ] **Step 13: Commit**

```bash
git add lib/onboarding/ lib/settings/ lib/app.dart lib/library/library_screen.dart test/onboarding_store_test.dart test/onboarding_screen_test.dart
git commit -m "Phase 4 Task 6: onboarding + settings/about surface + library settings entry"
```

---

### Task 7: Final Phase-4 verification

**Why:** Confirm the whole phase holds together before manual checks.

**Files:** none (verification only).

- [ ] **Step 1: Full analyze (lib + test)**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all green.

- [ ] **Step 3: Release-mode build sanity (debug is enough if release is slow)**

Run: `flutter build apk --debug`
Expected: APK builds.

- [ ] **Step 4: Commit any incidental fixes**

```bash
git add -A
git commit -m "Phase 4 Task 7: final verification (analyze clean, tests green, APK builds)"
```

---

## Phase 4 Definition of Done

- [ ] `VoiceConfig` bundled/downloadable; `VoiceCatalog` = amy-low (bundled) + 2 downloadable (Task 1).
- [ ] `DownloadingVoiceManager`: download, **SHA-256 verify**, extract, resume, delete, bundled delegation — unit-tested (Task 2).
- [ ] Active voice persists; `NeuralNarrator.setVoice` re-inits; engine uses `DownloadingVoiceManager`; timings keyed by active voice (Tasks 3–4).
- [ ] Voice screen: install / use / delete / progress / error+retry (Task 4).
- [ ] Screen-reader policy + `ExcludeSemantics` around content while self-narrating; dyslexia spacing options mapped to `EPUBPreferences` (Task 5).
- [ ] Onboarding first-run only; settings/about surface; library settings entry; empty/error states (Task 6).
- [ ] `flutter analyze` clean; all unit tests green; debug APK builds (Task 7).
- [ ] No regression to Phase 1–3.

## Manual checks (deferred — folded into the combined Phase 2/3/4 doc)
Real voice download over network + airplane-mode offline after; fill real catalog SHA-256 checksums; ensure catalog URLs point at packaged `.tar`s; TalkBack double-speak resolved + focus order; dyslexia spacing/font legibility on device; onboarding shows once; long-session thermal/battery/latency on a real mid-range Android (carryover #13).
