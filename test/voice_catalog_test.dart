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

  test('all contains the catalog and byId resolves', () {
    expect(VoiceCatalog.all, contains(VoiceCatalog.amyLow));
    expect(VoiceCatalog.byId('vits-piper-en_US-amy-low'), VoiceCatalog.amyLow);
    expect(VoiceCatalog.byId('nope'), isNull);
  });
}
