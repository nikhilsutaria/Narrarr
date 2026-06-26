import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tts_engine.dart';
import 'tts_synth_isolate.dart';
import 'voice_catalog.dart';
import 'voice_manager.dart';

export 'voice_manager.dart' show VoiceConfig;

/// On-device neural TTS via sherpa-onnx + Piper, with gapless continuous
/// playback. Ported from the original proof-of-concept; the
/// four stacked fixes — long-sentence chunking, look-ahead pre-synthesis on a
/// persistent isolate, two-player preload, and chunk-streaming — are retained.
///
/// Sync note: this engine is completion-driven ([speak] resolves on real
/// audio-end). The position-driven sync layer is a Phase-3 task; this engine
/// still serves as the source of truth for measured clip durations there.
class NeuralNarrator implements TtsEngine {
  NeuralNarrator({this.voice = VoiceCatalog.amyLow, VoiceManager? voiceManager})
      : _voiceManager = voiceManager ?? BundledVoiceManager();

  VoiceConfig voice;
  final VoiceManager _voiceManager;

  final TtsSynthIsolate _synth = TtsSynthIsolate();
  // Two players ping-pong: while one plays the current clip, the next clip's
  // source is pre-loaded on the other, so starting it is instant (~250ms saved
  // per clip on the POC emulator).
  // Lazy so merely constructing the engine doesn't touch the audioplayers
  // platform channel (keeps it unit-testable and off the cold-start path);
  // the two players are created on first init/use.
  late final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  int _cur = 0;
  String? _armed;
  _Prepared? _armedPrep;
  late Directory _tmpDir;

  bool _inited = false;
  bool _stopRequested = false;
  // Desired pause state, tracked independently of the platform player. On the
  // very first cold-launch utterance a pause() can race ahead of the player's
  // resume() and be dropped by audioplayers (the player ends up playing while
  // the UI shows "paused") — see #11. The speak loop re-asserts this flag right
  // after each resume() so the pause always sticks, warm players or not.
  bool _paused = false;
  Completer<void>? _playing;
  int _seq = 0;
  int _lastUtteranceMs = 0;

  @override
  int get lastUtteranceMs => _lastUtteranceMs;

  // Look-ahead cache: upcoming sentences pre-synthesized AND pre-written to WAV,
  // keyed by text. Keeps the pipeline ahead of playback.
  final Map<String, Future<_Prepared>> _cache = {};
  static const int _maxCache = 8;

  // Piper's stochastic duration predictor rushes very long single utterances,
  // so synthesize in chunks no larger than this. 120 is the POC's measured-safe
  // threshold (122 chars paced normally; 278 did not).
  static const int _maxSynthChars = 120;

  AudioPlayer get _curPlayer => _players[_cur];
  AudioPlayer get _nextPlayer => _players[_cur ^ 1];

  @override
  String get name => 'Neural (${voice.id})';

  @override
  Future<void> init() async {
    if (_inited) return;
    final modelDir = await _voiceManager.ensureAvailable(voice);
    await _synth.start(
      model: p.join(modelDir, voice.modelFile),
      tokens: p.join(modelDir, 'tokens.txt'),
      dataDir: p.join(modelDir, 'espeak-ng-data'),
      // Cap synth threads so look-ahead can't peg every core and starve the
      // audio-output thread mid-clip.
      numThreads: 2,
    );
    _tmpDir = await getTemporaryDirectory();
    // Warm up the ONNX graph: the first generate() is a slow cold-start.
    try {
      await _synth.synth('Ready.');
    } catch (_) {}
    _inited = true;
  }

  /// Switch the active voice. If the engine was already initialised, re-init the
  /// synth isolate against the new model; otherwise just record the selection
  /// (the lazy [init] will pick it up). Safe to call while idle.
  Future<void> setVoice(VoiceConfig next) async {
    if (next.id == voice.id) return;
    voice = next;
    if (_inited) {
      await stop();
      _synth.dispose();
      _inited = false;
      _cache.clear();
      await init();
    }
  }

  @override
  void precache(String text) {
    if (!_inited) return;
    final s = text.trim();
    if (s.isEmpty || _cache.containsKey(s)) return;
    _cache[s] = _prepare(s).catchError((e) {
      debugPrint('[narrator] precache error: $e');
      return const _Prepared([], 0);
    });
    while (_cache.length > _maxCache) {
      _cache.remove(_cache.keys.first);
    }
  }

  @override
  Future<void> speak(String text) async {
    assert(_inited);
    _stopRequested = false;
    final s = text.trim();
    if (s.isEmpty) return;

    // Fast path: the spare player was pre-armed with this sentence's first clip.
    final bool preloaded = s == _armed && _armedPrep != null;
    final _Prepared prep;
    if (preloaded) {
      _cur ^= 1;
      prep = _armedPrep!;
      _armed = null;
      _armedPrep = null;
    } else {
      prep = await (_cache.remove(s) ?? _prepare(s));
      if (_stopRequested || prep.isEmpty) return;
    }
    if (_stopRequested) return;
    _lastUtteranceMs = prep.audioMs;

    final player = _curPlayer;
    // Play the sentence's chunk-clips back-to-back. Short clips avoid the
    // emulator's long-clip completion stall; between sentences the next one's
    // first clip is pre-armed on the spare player for a gapless hand-off.
    for (var ci = 0; ci < prep.clips.length; ci++) {
      if (_stopRequested) return;
      if (!(preloaded && ci == 0)) {
        await player.setSource(DeviceFileSource(prep.clips[ci]));
        if (_stopRequested) return;
      }
      final completer = Completer<void>();
      _playing = completer;
      final sub = player.onPlayerComplete.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });
      await player.resume();
      // Re-assert a pause that arrived while resume() was still landing on the
      // native player (#11). The clip stays parked here until resume() flips
      // _paused back, so onPlayerComplete won't fire and we don't advance.
      if (_paused && !_stopRequested) await player.pause();
      await completer.future;
      await sub.cancel();
    }
    _playing = null;
  }

  @override
  void preloadNext(String text) {
    if (!_inited) return;
    final s = text.trim();
    if (s.isEmpty || s == _armed) return;
    _armPlayer(s);
  }

  Future<void> _armPlayer(String s) async {
    final prep = await (_cache[s] ??= _prepare(s).catchError((e) {
      debugPrint('[narrator] precache error: $e');
      return const _Prepared([], 0);
    }));
    if (prep.isEmpty || s == _armed || _stopRequested) return;
    try {
      await _nextPlayer.setSource(DeviceFileSource(prep.clips.first));
      _armed = s;
      _armedPrep = prep;
    } catch (e) {
      debugPrint('[narrator] preload error: $e');
    }
  }

  /// Synthesize [s] into one or more short WAV clips (one per clause-chunk),
  /// written to disk and ready to play in sequence.
  Future<_Prepared> _prepare(String s) async {
    final chunks = _chunkForSynthesis(s);
    final parts = (await Future.wait(chunks.map((c) => _synth.synth(c))))
        .where((part) => part.$1.isNotEmpty)
        .toList();
    if (parts.isEmpty) return const _Prepared([], 0);

    final sampleRate = parts.first.$2;
    final clips = <String>[];
    final clipMs = <int>[];
    var totalMs = 0;
    for (final part in parts) {
      final trimmed = _trimSilence(part.$1, sampleRate);
      if (trimmed.isEmpty) continue;
      final ms = (trimmed.length * 1000 / sampleRate).round();
      final path = p.join(_tmpDir.path, 'tts_${_seq++ % 20}.wav');
      await File(path)
          .writeAsBytes(_wavFromFloat(trimmed, sampleRate), flush: true);
      clips.add(path);
      clipMs.add(ms);
      totalMs += ms;
    }
    if (clips.isEmpty) return const _Prepared([], 0);
    return _Prepared(clips, totalMs, clipMs);
  }

  /// Trim contiguous near-silence from clip edges, keeping a small margin.
  Float32List _trimSilence(Float32List s, int sr) {
    const thresh = 0.02;
    var lead = 0;
    while (lead < s.length && s[lead].abs() < thresh) {
      lead++;
    }
    var trail = 0;
    while (trail < s.length - lead && s[s.length - 1 - trail].abs() < thresh) {
      trail++;
    }
    final leadMargin = (sr * 0.03).round();
    final trailMargin = (sr * 0.06).round();
    final start = (lead - leadMargin).clamp(0, s.length);
    final end = (s.length - trail + trailMargin).clamp(0, s.length);
    if (end <= start) return s;
    return Float32List.sublistView(s, start, end);
  }

  /// Break [text] into ≤[_maxSynthChars] segments at clause punctuation
  /// (`, ; :` / em-dash), falling back to word boundaries.
  List<String> _chunkForSynthesis(String text) {
    final t = text.trim();
    if (t.length <= _maxSynthChars) return [t];
    final clauses = RegExp(r'[^,;:—]+[,;:—]*')
        .allMatches(t)
        .map((m) => m.group(0)!.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    final out = <String>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
    }

    for (final clause in clauses) {
      if (clause.length > _maxSynthChars) {
        flush();
        out.addAll(_splitByWords(clause));
        continue;
      }
      if (buf.isNotEmpty && buf.length + 1 + clause.length > _maxSynthChars) {
        flush();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(clause);
    }
    flush();
    return out;
  }

  List<String> _splitByWords(String text) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final w in text.split(RegExp(r'\s+'))) {
      if (buf.isNotEmpty && buf.length + 1 + w.length > _maxSynthChars) {
        out.add(buf.toString());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(w);
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  @override
  Future<void> setVoiceIfNeeded(Object voice) async {
    if (voice is VoiceConfig) await setVoice(voice);
  }

  @override
  Future<void> setVolume(double volume) async {
    final v = volume.clamp(0.0, 1.0);
    for (final pl in _players) {
      await pl.setVolume(v);
    }
  }

  @override
  Future<void> pause() async {
    // Pause the active clip in place. The chunk-playback loop stays parked on
    // the unresolved completer (the clip's onPlayerComplete won't fire while
    // paused), so resume() continues exactly where it left off. The flag lets
    // the speak loop re-apply this if it raced the first resume() (#11).
    _paused = true;
    await _curPlayer.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    await _curPlayer.resume();
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    _paused = false;
    _armed = null;
    _armedPrep = null;
    await _curPlayer.stop();
    if (_playing != null && !_playing!.isCompleted) _playing!.complete();
  }

  @override
  Future<void> dispose() async {
    for (final pl in _players) {
      await pl.stop();
      await pl.dispose();
    }
    _synth.dispose();
  }

  /// Encode mono Float32 samples ([-1, 1]) as 16-bit PCM WAV bytes.
  Uint8List _wavFromFloat(Float32List samples, int sampleRate) {
    final n = samples.length;
    final dataSize = n * 2;
    final buf = ByteData(44 + dataSize);
    var o = 0;
    void putStr(String s) {
      for (final c in s.codeUnits) {
        buf.setUint8(o++, c);
      }
    }

    putStr('RIFF');
    buf.setUint32(o, 36 + dataSize, Endian.little);
    o += 4;
    putStr('WAVE');
    putStr('fmt ');
    buf.setUint32(o, 16, Endian.little);
    o += 4;
    buf.setUint16(o, 1, Endian.little);
    o += 2;
    buf.setUint16(o, 1, Endian.little);
    o += 2;
    buf.setUint32(o, sampleRate, Endian.little);
    o += 4;
    buf.setUint32(o, sampleRate * 2, Endian.little);
    o += 4;
    buf.setUint16(o, 2, Endian.little);
    o += 2;
    buf.setUint16(o, 16, Endian.little);
    o += 2;
    putStr('data');
    buf.setUint32(o, dataSize, Endian.little);
    o += 4;
    for (var i = 0; i < n; i++) {
      final v = (samples[i] * 32767.0).round().clamp(-32768, 32767);
      buf.setInt16(o, v, Endian.little);
      o += 2;
    }
    return buf.buffer.asUint8List();
  }
}

/// A synthesized sentence ready to play: one or more short WAV clips.
class _Prepared {
  final List<String> clips;
  final List<int> clipMs;
  final int audioMs;
  const _Prepared(this.clips, this.audioMs, [this.clipMs = const []]);
  bool get isEmpty => clips.isEmpty;
}
