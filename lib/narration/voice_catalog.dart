import '../build_flavor.dart';
import 'voice_manager.dart';

/// Sentinel voice id for the device's built-in text-to-speech (#15): no
/// download, no [VoiceConfig] — narration routes to `SystemNarrator` instead of
/// the neural engine. Persisted in `VoiceSettings.activeVoiceId` and used to
/// key the timing cache like any other voice id.
const String kSystemVoiceId = 'system';

/// The voices Narrarr offers: a default voice + optional downloads.
///
/// Downloads point at the sherpa-onnx `tts-models` release tarballs — open, no
/// account, the same source as the bundled voice. Each is a bzip2-compressed
/// `.tar.bz2` whose top-level dir is the voice [id] and which contains the
/// `.onnx`, `tokens.txt`, and `espeak-ng-data/` the engine needs; the extractor
/// decompresses it transparently. `sha256` is verified against the downloaded
/// (compressed) bytes and `sizeBytes` is the download size — both measured from
/// the real release assets (2026-06-26; amy-low 2026-07-11).
class VoiceCatalog {
  VoiceCatalog._();

  static const _sherpaRelease =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

  /// The default Amy (low) voice, as it ships in the QA flavor: inside the
  /// app bundle, extracted on first use, no network ever needed.
  static const _amyLowBundled = VoiceConfig(
    id: 'vits-piper-en_US-amy-low',
    displayName: 'Amy (low) — bundled',
    asset: 'assets/voices/vits-piper-en_US-amy-low.tar',
    modelFile: 'en_US-amy-low.onnx',
    sizeBytes: 0,
  );

  /// The same default voice in the prod flavor: not bundled (keeps the app
  /// small), fetched on demand like every other voice.
  static const _amyLowDownload = VoiceConfig(
    id: 'vits-piper-en_US-amy-low',
    displayName: 'Amy (low)',
    modelFile: 'en_US-amy-low.onnx',
    url: '$_sherpaRelease/vits-piper-en_US-amy-low.tar.bz2',
    sha256: 'c70f5284a09a7fd4ed203b39b2ff51cac1432b422b852eb647b481dade3cf639',
    sizeBytes: 67095344,
  );

  /// The default voice. Same [VoiceConfig.id] in both flavors, so persisted
  /// voice settings and timing caches carry across flavors unchanged.
  static VoiceConfig get amyLow =>
      BuildFlavor.isQa ? _amyLowBundled : _amyLowDownload;

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

  static List<VoiceConfig> get all => [amyLow, ryanMedium, amyMedium];

  static VoiceConfig? byId(String id) {
    for (final v in all) {
      if (v.id == id) return v;
    }
    return null;
  }
}
