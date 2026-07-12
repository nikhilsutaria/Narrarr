import 'dart:convert';

/// Per-voice VITS inference parameters (#38), read from the `.onnx.json`
/// config that ships inside every Piper voice archive. Piper voice authors
/// tune these per voice (`inference` block: `noise_scale`, `length_scale`,
/// `noise_w`); ignoring them and running sherpa-onnx defaults is part of why
/// pacing sounds rushed. Absent/malformed configs fall back to the sherpa-onnx
/// defaults, so a voice tarball without a json still loads.
class PiperVoiceParams {
  const PiperVoiceParams({
    this.noiseScale = 0.667,
    this.lengthScale = 1.0,
    this.noiseW = 0.8,
  });

  final double noiseScale;
  final double lengthScale;
  final double noiseW;

  /// Parse a Piper `<model>.onnx.json` string. Any missing field keeps its
  /// default; a malformed document returns all defaults.
  factory PiperVoiceParams.fromJsonString(String jsonString) {
    try {
      final doc = jsonDecode(jsonString);
      if (doc is! Map) return const PiperVoiceParams();
      final inference = doc['inference'];
      if (inference is! Map) return const PiperVoiceParams();
      double read(String key, double fallback) {
        final v = inference[key];
        return v is num ? v.toDouble() : fallback;
      }

      return PiperVoiceParams(
        noiseScale: read('noise_scale', 0.667),
        lengthScale: read('length_scale', 1.0),
        noiseW: read('noise_w', 0.8),
      );
    } catch (_) {
      return const PiperVoiceParams();
    }
  }

  @override
  String toString() =>
      'PiperVoiceParams(noiseScale: $noiseScale, lengthScale: $lengthScale, '
      'noiseW: $noiseW)';
}
