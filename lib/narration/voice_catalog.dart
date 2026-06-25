import 'voice_manager.dart';

/// The voices Narrarr offers: one bundled default + optional downloads.
///
/// Download URLs are Hugging Face `rhasspy/piper-voices` direct files (open, no
/// account). `sha256` is filled when the real tars are checksummed on a
/// networked machine; until then download proceeds unverified (logged). The
/// download/verify/extract *mechanism* is the Phase-4 deliverable; the concrete
/// URLs must point at packaged `.tar`s before shipping (see manual checks).
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
