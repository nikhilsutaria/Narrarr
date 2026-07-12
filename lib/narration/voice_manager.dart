import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

/// Resolves a [VoiceConfig] to an on-disk, ready-to-load model directory.
///
/// This is the seam for download-on-demand (MVP spec #11): the engine asks for
/// a voice and gets back a directory, without caring whether it was bundled,
/// downloaded, or already cached. Phase 2 ships [BundledVoiceManager] only; a
/// downloading implementation (verify checksum / resume / evict) is Phase 4.
abstract class VoiceManager {
  /// Ensure [voice] is available locally and return its extracted model
  /// directory (the folder containing [VoiceConfig.modelFile]).
  Future<String> ensureAvailable(VoiceConfig voice);
}

/// Extracts a voice bundled as a `.tar` asset into app-support storage on first
/// use. [baseDir] and [loadAsset] are injectable for tests; in production they
/// default to the app-support directory and the Flutter asset bundle.
class BundledVoiceManager implements VoiceManager {
  BundledVoiceManager({
    Directory? baseDir,
    Future<Uint8List> Function(String asset)? loadAsset,
  })  : _baseDir = baseDir,
        _loadAsset = loadAsset ?? _rootBundleLoad;

  final Directory? _baseDir;
  final Future<Uint8List> Function(String asset) _loadAsset;

  Future<Directory> _base() async =>
      _baseDir ?? await getApplicationSupportDirectory();

  @override
  Future<String> ensureAvailable(VoiceConfig voice) async {
    final support = await _base();
    final modelDir = p.join(support.path, voice.id);
    if (await File(p.join(modelDir, voice.modelFile)).exists()) {
      return modelDir; // already extracted
    }
    final bytes = await _loadAsset(voice.asset!);
    await extractVoiceTar(bytes, support);
    return modelDir;
  }
}

/// Extract a voice archive (model + tokens + espeak-ng-data) into [support].
/// Shared by [BundledVoiceManager] and [DownloadingVoiceManager]. Accepts a
/// plain `.tar` (the bundled voice) or a bzip2-compressed `.tar.bz2` (the
/// sherpa-onnx download format), detected by the bzip2 magic header.
Future<void> extractVoiceTar(Uint8List bytes, Directory support) async {
  final List<int> tarBytes =
      _isBzip2(bytes) ? BZip2Decoder().decodeBytes(bytes) : bytes;
  final root = p.normalize(p.absolute(support.path));
  for (final entry in TarDecoder().decodeBytes(tarBytes)) {
    final outPath = p.normalize(p.join(root, entry.name));
    // Zip-slip guard: an entry named `../x` or an absolute path must never
    // write outside the extraction dir (defense in depth behind the sha256
    // pin on downloads and the signed APK on bundled assets).
    if (!p.isWithin(root, outPath)) {
      throw FormatException(
          'Voice archive entry escapes extraction dir: ${entry.name}');
    }
    if (entry.isFile) {
      await Directory(p.dirname(outPath)).create(recursive: true);
      await File(outPath).writeAsBytes(entry.content as List<int>);
    } else {
      await Directory(outPath).create(recursive: true);
    }
  }
}

/// Whether [b] begins with the bzip2 magic header (`BZh`).
bool _isBzip2(List<int> b) =>
    b.length >= 3 && b[0] == 0x42 && b[1] == 0x5A && b[2] == 0x68;

Future<Uint8List> _rootBundleLoad(String asset) async {
  final data = await rootBundle.load(asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Fetches the bytes for [url] starting at [offset] (for resume). Injected for
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

  // In-flight installs by voice id. Concurrent calls for the same voice (e.g.
  // the reader's lazy init racing a tap on the Voices screen) must share one
  // download — two writers appending to the same .part file corrupt it (#30).
  final Map<String, Future<String>> _inFlight = {};

  Future<Directory> _base() async =>
      _baseDir ?? await getApplicationSupportDirectory();

  String _modelDirPath(Directory support, VoiceConfig v) =>
      p.join(support.path, v.id);

  @override
  Future<String> ensureAvailable(VoiceConfig voice,
      {void Function(double)? onProgress}) {
    return _inFlight[voice.id] ??=
        _ensure(voice, onProgress: onProgress).whenComplete(() {
      // Success or failure, clear the slot: the fast on-disk check makes a
      // repeat call cheap, and a failed download must be retryable.
      _inFlight.remove(voice.id);
    });
  }

  Future<String> _ensure(VoiceConfig voice,
      {void Function(double)? onProgress}) async {
    if (voice.isBundled) return _bundled.ensureAvailable(voice);

    final support = await _base();
    final modelDir = _modelDirPath(support, voice);
    if (await File(p.join(modelDir, voice.modelFile)).exists()) {
      return modelDir; // already installed
    }

    // Every download must be integrity-pinned; refuse before fetching a byte
    // so a future catalog entry can't silently ship unverified.
    final expected = voice.sha256;
    if (expected == null) {
      throw StateError(
          'Voice ${voice.id} has no sha256 pin; refusing unverified download');
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
    if (sha256.convert(bytes).toString() != expected) {
      await partFile.delete();
      throw Exception('Voice ${voice.id} failed checksum verification');
    }

    await extractVoiceTar(Uint8List.fromList(bytes), support);
    await partFile.delete();
    return modelDir;
  }

  /// Whether [voice]'s model is present on disk.
  Future<bool> isInstalled(VoiceConfig voice) async {
    final support = await _base();
    return File(p.join(_modelDirPath(support, voice), voice.modelFile)).exists();
  }

  /// Remove a downloaded voice's extracted files.
  Future<void> delete(VoiceConfig voice) async {
    final support = await _base();
    final dir = Directory(_modelDirPath(support, voice));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Total bytes used by everything under app-support (rough storage figure).
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
    // A resumed fetch must get 206 — a server that ignores Range would return
    // the whole file and corrupt the appended .part (the checksum would catch
    // it, but as a confusing retry loop). A fresh fetch must get a plain 200.
    final expectStatus =
        offset > 0 ? HttpStatus.partialContent : HttpStatus.ok;
    if (resp.statusCode != expectStatus) {
      throw HttpException(
          'Voice download got HTTP ${resp.statusCode} (expected $expectStatus)',
          uri: url);
    }
    final out = <int>[];
    await for (final chunk in resp) {
      out.addAll(chunk);
    }
    return out;
  } finally {
    client.close();
  }
}
