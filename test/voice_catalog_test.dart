import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/narration/voice_catalog.dart';

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

  test('downloadable voices are shippable: packaged tar + integrity checksum',
      () {
    // Guards against regressing to the unverified placeholder URLs: each
    // download must point at a packaged tar (not a bare .onnx) and carry a
    // SHA-256 so the downloader actually verifies integrity.
    for (final v in [VoiceCatalog.ryanMedium, VoiceCatalog.amyMedium]) {
      expect(v.url, endsWith('.tar.bz2'), reason: '${v.id} must be a tar');
      expect(v.sha256, isNotNull, reason: '${v.id} must have a checksum');
      expect(v.sha256!.length, 64, reason: '${v.id} sha256 must be 64 hex');
    }
  });

  test('all contains the catalog and byId resolves', () {
    expect(VoiceCatalog.all, contains(VoiceCatalog.amyLow));
    expect(VoiceCatalog.byId('vits-piper-en_US-amy-low'), VoiceCatalog.amyLow);
    expect(VoiceCatalog.byId('nope'), isNull);
  });
}
