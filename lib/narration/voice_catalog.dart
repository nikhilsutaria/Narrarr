import 'voice_manager.dart';

/// The voices Narrarr offers: one bundled default + optional downloads.
///
/// Downloads point at the sherpa-onnx `tts-models` release tarballs — open, no
/// account, the same source as the bundled voice. Each is a bzip2-compressed
/// `.tar.bz2` whose top-level dir is the voice [id] and which contains the
/// `.onnx`, `tokens.txt`, and `espeak-ng-data/` the engine needs; the extractor
/// decompresses it transparently. `sha256` is verified against the downloaded
/// (compressed) bytes and `sizeBytes` is the download size — both measured from
/// the real release assets on 2026-06-26.
class VoiceCatalog {
  VoiceCatalog._();

  static const _sherpaRelease =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

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
    url: '$_sherpaRelease/vits-piper-en_US-ryan-medium.tar.bz2',
    sha256: 'c546af78b6395b4e7c4ce1ed899438b64426a362f5d4ec5fecd090ded9ad7505',
    sizeBytes: 67213100,
  );

  static const amyMedium = VoiceConfig(
    id: 'vits-piper-en_US-amy-medium',
    displayName: 'Amy (medium)',
    modelFile: 'en_US-amy-medium.onnx',
    url: '$_sherpaRelease/vits-piper-en_US-amy-medium.tar.bz2',
    sha256: '9a5d1fc497f85e8022b785bff5f8105203b1e33099ee6265203efc70b0cb0264',
    sizeBytes: 67223746,
  );

  static const List<VoiceConfig> all = [amyLow, ryanMedium, amyMedium];

  static VoiceConfig? byId(String id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }
}
