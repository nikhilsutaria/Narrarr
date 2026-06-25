import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  const voice = VoiceConfig(
    id: 'test-voice',
    displayName: 'Test Voice',
    asset: 'a.tar',
    modelFile: 'model.onnx',
  );

  Uint8List fixtureTar() {
    final model = utf8.encode('fake-onnx-bytes');
    final archive = Archive()
      ..addFile(ArchiveFile('test-voice/model.onnx', model.length, model))
      ..addFile(ArchiveFile('test-voice/tokens.txt', 3, utf8.encode('abc')));
    return Uint8List.fromList(TarEncoder().encode(archive));
  }

  test('ensureAvailable extracts the model and returns its directory', () async {
    final tmp = await Directory.systemTemp.createTemp('voice_test');
    final mgr =
        BundledVoiceManager(baseDir: tmp, loadAsset: (_) async => fixtureTar());

    final dir = await mgr.ensureAvailable(voice);

    expect(File(p.join(dir, 'model.onnx')).existsSync(), true);
    expect(File(p.join(dir, 'tokens.txt')).existsSync(), true);
    await tmp.delete(recursive: true);
  });

  test('second call is idempotent (no re-extract)', () async {
    final tmp = await Directory.systemTemp.createTemp('voice_test');
    var loads = 0;
    final mgr = BundledVoiceManager(
      baseDir: tmp,
      loadAsset: (_) async {
        loads++;
        return fixtureTar();
      },
    );

    await mgr.ensureAvailable(voice);
    await mgr.ensureAvailable(voice);

    expect(loads, 1); // asset loaded once; cached extraction reused
    await tmp.delete(recursive: true);
  });
}
