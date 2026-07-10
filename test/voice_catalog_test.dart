import 'package:flutter_test/flutter_test.dart';
import 'package:narrarr/build_flavor.dart';
import 'package:narrarr/narration/voice_catalog.dart';

void main() {
  tearDown(() => BuildFlavor.debugOverride = null);

  test('qa flavor: amy-low is the bundled default', () {
    BuildFlavor.debugOverride = 'qa';
    expect(VoiceCatalog.amyLow.isBundled, isTrue);
    expect(VoiceCatalog.amyLow.asset, isNotNull);
    expect(VoiceCatalog.amyLow.id, 'vits-piper-en_US-amy-low');
  });

  test('prod flavor (and unflavored builds): amy-low is a download', () {
    // No override: unflavored (tests, plain `flutter run`) behaves as prod.
    expect(BuildFlavor.isQa, isFalse);
    expect(VoiceCatalog.amyLow.isBundled, isFalse);
    expect(VoiceCatalog.amyLow.url, isNotNull);
    expect(VoiceCatalog.amyLow.id, 'vits-piper-en_US-amy-low');
  });

  test('the default voice keeps the same id in both flavors', () {
    // Voice settings and timing caches key off the id, so it must not change
    // between the bundled (qa) and downloadable (prod) variants.
    final prodId = VoiceCatalog.amyLow.id;
    BuildFlavor.debugOverride = 'qa';
    expect(VoiceCatalog.amyLow.id, prodId);
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
    // SHA-256 so the downloader actually verifies integrity. In prod the
    // default amy-low is a download too, so it must meet the same bar.
    for (final v in [
      VoiceCatalog.amyLow, // prod variant (no override in this test)
      VoiceCatalog.ryanMedium,
      VoiceCatalog.amyMedium,
    ]) {
      expect(v.url, endsWith('.tar.bz2'), reason: '${v.id} must be a tar');
      expect(v.sha256, isNotNull, reason: '${v.id} must have a checksum');
      expect(v.sha256!.length, 64, reason: '${v.id} sha256 must be 64 hex');
      expect(v.sizeBytes, greaterThan(0), reason: '${v.id} must have a size');
    }
  });

  test('all contains the catalog and byId resolves', () {
    expect(VoiceCatalog.all, contains(VoiceCatalog.amyLow));
    expect(VoiceCatalog.byId('vits-piper-en_US-amy-low'), VoiceCatalog.amyLow);
    expect(VoiceCatalog.byId('nope'), isNull);
  });
}
