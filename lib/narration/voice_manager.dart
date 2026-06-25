import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

/// Extract a voice `.tar` (model + tokens + espeak-ng-data) into [support].
/// Shared by [BundledVoiceManager] and [DownloadingVoiceManager].
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

Future<Uint8List> _rootBundleLoad(String asset) async {
  final data = await rootBundle.load(asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}
