import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/build_flavor.dart';
import 'package:narrarr/narration/voice_catalog.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('dvm'));
  tearDown(() => tmp.deleteSync(recursive: true));

  // Build a tar containing a fake model file; return (bytes, sha256-hex).
  (Uint8List, String) fakeVoiceTar(String voiceId, String modelFile) {
    final archive = Archive()
      ..addFile(ArchiveFile('$voiceId/$modelFile', 4, [1, 2, 3, 4]));
    final bytes = Uint8List.fromList(TarEncoder().encode(archive));
    return (bytes, sha256.convert(bytes).toString());
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
    final v = VoiceConfig(
      id: 'voiceX',
      displayName: 'Voice X',
      modelFile: 'voiceX.onnx',
      url: 'https://example.test/voiceX.tar',
      sha256: 'deadbeef',
      sizeBytes: 100,
    );
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

  test('handles a bz2-compressed tar (sherpa-onnx download format)', () async {
    // sherpa-onnx voice releases ship as .tar.bz2; the downloader must
    // decompress before untarring. Checksum is over the downloaded (bz2) bytes.
    final archive = Archive()
      ..addFile(ArchiveFile('voiceZ/voiceZ.onnx', 4, [1, 2, 3, 4]));
    final tar = Uint8List.fromList(TarEncoder().encode(archive));
    final bz2 = Uint8List.fromList(BZip2Encoder().encode(tar));
    final v = VoiceConfig(
      id: 'voiceZ',
      displayName: 'Voice Z',
      modelFile: 'voiceZ.onnx',
      url: 'https://example.test/voiceZ.tar.bz2',
      sha256: sha256.convert(bz2).toString(),
      sizeBytes: bz2.length,
    );
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      fetch: (uri, {offset = 0}) async => bz2.sublist(offset),
    );
    final dir = await m.ensureAvailable(v);
    expect(File(p.join(dir, 'voiceZ.onnx')).existsSync(), isTrue);
    expect(await m.isInstalled(v), isTrue);
  });

  test('refuses to download a voice with no sha256 pin', () async {
    // Defense in depth: a future catalog entry must not be able to silently
    // ship an unverified download.
    final (bytes, _) = fakeVoiceTar('voiceX', 'voiceX.onnx');
    const v = VoiceConfig(
      id: 'voiceX',
      displayName: 'Voice X',
      modelFile: 'voiceX.onnx',
      url: 'https://example.test/voiceX.tar',
    );
    var fetched = false;
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      fetch: (uri, {offset = 0}) async {
        fetched = true;
        return bytes.sublist(offset);
      },
    );
    await expectLater(m.ensureAvailable(v), throwsA(isA<StateError>()));
    expect(fetched, isFalse, reason: 'must refuse before fetching');
    expect(await m.isInstalled(v), isFalse);
  });

  test('extractVoiceTar rejects entries that escape the target dir', () async {
    // Zip-slip guard: `../` and absolute entry names must not write outside
    // the extraction dir, whatever the archive's provenance.
    for (final evil in ['../escape.txt', '/abs/escape.txt']) {
      final archive = Archive()..addFile(ArchiveFile(evil, 4, [1, 2, 3, 4]));
      final bytes = Uint8List.fromList(TarEncoder().encode(archive));
      final dest = Directory(p.join(tmp.path, 'out'))..createSync();
      await expectLater(
        extractVoiceTar(bytes, dest),
        throwsA(isA<FormatException>()),
        reason: '$evil must be rejected',
      );
      expect(File(p.join(tmp.path, 'escape.txt')).existsSync(), isFalse);
    }
  });

  test('bundled voice delegates to BundledVoiceManager', () async {
    // amy-low is only bundled in the qa flavor.
    BuildFlavor.debugOverride = 'qa';
    addTearDown(() => BuildFlavor.debugOverride = null);
    final (bytes, _) =
        fakeVoiceTar('vits-piper-en_US-amy-low', 'en_US-amy-low.onnx');
    final m = DownloadingVoiceManager(
      baseDir: tmp,
      loadAsset: (asset) async => bytes,
    );
    final dir = await m.ensureAvailable(VoiceCatalog.amyLow);
    expect(File(p.join(dir, 'en_US-amy-low.onnx')).existsSync(), isTrue);
  });
}
