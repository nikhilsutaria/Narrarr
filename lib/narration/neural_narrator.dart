import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'pcm_playback.dart';
import 'piper_voice_params.dart';
import 'tts_engine.dart';
import 'tts_synth_isolate.dart';
import 'voice_catalog.dart';
import 'voice_manager.dart';

export 'voice_manager.dart' show VoiceConfig;

/// On-device neural TTS via sherpa-onnx + Piper, played as a gapless PCM
/// stream (#33): synthesized samples are pushed straight into a
/// [PcmPlayback] buffer stream — chunk hand-offs inside a sentence are
/// sample-continuous, playback starts on the first synthesized chunk instead
/// of waiting for the whole sentence, and there are no temp files or
/// per-clip player loads. Look-ahead pre-synthesis on a persistent isolate is
/// retained from the POC; the two-player ping-pong and WAV round-trip it
/// existed to serve are gone.
///
/// Sync note: this engine is completion-driven ([speak] resolves on real
/// audio-end). The position-driven sync layer is a Phase-3 task; this engine
/// still serves as the source of truth for measured clip durations there.
class NeuralNarrator implements TtsEngine {
  NeuralNarrator({
    VoiceConfig? voice,
    VoiceManager? voiceManager,
    TtsSynthIsolate Function()? synthFactory,
    PcmPlayback? playback,
  })  : voice = voice ?? VoiceCatalog.amyLow,
        // Downloading manager by default: it serves bundled voices too, and in
        // the prod flavor the default voice is download-only.
        _voiceManager = voiceManager ?? DownloadingVoiceManager(),
        _synthFactory = synthFactory ?? TtsSynthIsolate.new,
        _playback = playback ?? SoLoudPcmPlayback();

  VoiceConfig voice;
  final VoiceManager _voiceManager;

  // A fresh isolate per (re)init — TtsSynthIsolate is one-shot (its dispose is
  // permanent), so reusing an instance across init/setVoice cycles is exactly
  // the wedge #30 describes. The factory is injectable for tests.
  final TtsSynthIsolate Function() _synthFactory;
  TtsSynthIsolate? _synth;

  // Playback is lazy: merely constructing the engine — or stopping/switching
  // voice before anything ever played — must not touch the audio engine
  // (keeps it unit-testable and off the cold-start path).
  final PcmPlayback _playback;
  bool _playbackReady = false;

  bool _inited = false;
  Future<void>? _initing;
  bool _stopRequested = false;
  // Desired pause state, tracked independently of the platform player. On the
  // very first cold-launch utterance a pause() can race ahead of playback
  // start and be dropped — see #11. The utterance start (and every buffer
  // push) re-asserts this flag so the pause always sticks.
  bool _paused = false;
  PcmUtterance? _current;
  double _volume = 1.0;
  double _speed = 1.0;
  int _lastUtteranceMs = 0;

  @override
  int get lastUtteranceMs => _lastUtteranceMs;

  @override
  void Function(bool isBuffering)? onBuffering;
  Timer? _bufferingTimer;
  bool _bufferingRaised = false;

  // Look-ahead cache: upcoming sentences pre-synthesized, keyed by text.
  // Keeps the pipeline ahead of playback. Cleared on voice or speed change
  // (entries are synthesized at a specific speed).
  final Map<String, Future<_PreparedPcm>> _cache = {};
  static const int _maxCache = 8;

  // Piper's stochastic duration predictor rushes very long single utterances,
  // so synthesize in chunks no larger than this. The POC measured 122 chars
  // pacing normally and 278 not; 180 keeps the large majority of prose
  // sentences whole (fewer prosody resets, #39) while staying well under the
  // measured failure point. Chunk seams no longer have a player cost (#33),
  // so this trades only rush-risk against intonation continuity — exactly
  // what the v1.2 A/B listening test (#41) measures.
  static const int _maxSynthChars = 180;

  @override
  String get name => 'Neural (${voice.id})';

  /// Single-flight (#30): concurrent callers (double-tapped Listen, an engine
  /// switch racing a play) share one attempt instead of interleaving downloads
  /// and isolate spawns. On failure every trace of the attempt is discarded so
  /// the next call starts clean — a failed init must never leave the engine
  /// half-alive until an app restart.
  @override
  Future<void> init() {
    if (_inited) return Future.value();
    return _initing ??= _doInit().whenComplete(() => _initing = null);
  }

  Future<void> _doInit() async {
    final synth = _synthFactory();
    try {
      final modelDir = await _voiceManager.ensureAvailable(voice);
      final params = await _loadVoiceParams(modelDir);
      await synth.start(
        model: p.join(modelDir, voice.modelFile),
        tokens: p.join(modelDir, 'tokens.txt'),
        dataDir: p.join(modelDir, 'espeak-ng-data'),
        // Cap synth threads so look-ahead can't peg every core and starve the
        // audio-output thread mid-clip.
        numThreads: 2,
        noiseScale: params.noiseScale,
        lengthScale: params.lengthScale,
        noiseW: params.noiseW,
      );
      // Warm up the ONNX graph: the first generate() is a slow cold-start.
      // A warm-up failure is non-fatal — start() already proved the model
      // loaded; per-sentence failures surface loudly from speak().
      try {
        await synth.synth('Ready.');
      } catch (e) {
        debugPrint('[narrator] warm-up synth failed: $e');
      }
      _synth = synth;
      _inited = true;
    } catch (e) {
      synth.dispose();
      rethrow;
    }
  }

  /// The voice author's own prosody tuning from `<model>.onnx.json` (#38);
  /// defaults when the file is absent or unreadable.
  Future<PiperVoiceParams> _loadVoiceParams(String modelDir) async {
    try {
      final f = File(p.join(modelDir, '${voice.modelFile}.json'));
      if (!await f.exists()) return const PiperVoiceParams();
      final params = PiperVoiceParams.fromJsonString(await f.readAsString());
      debugPrint('[narrator] ${voice.id} $params');
      return params;
    } catch (e) {
      debugPrint('[narrator] voice config unreadable, using defaults: $e');
      return const PiperVoiceParams();
    }
  }

  /// Switch the active voice. If the engine was already initialised, tear down
  /// the current synth isolate and re-init against the new model (a **fresh**
  /// isolate — the old one's dispose is permanent, #30); otherwise just record
  /// the selection (the lazy [init] will pick it up). Safe to call while idle.
  Future<void> setVoice(VoiceConfig next) async {
    if (next.id == voice.id) return;
    voice = next;
    if (_inited) {
      await stop();
      _synth?.dispose();
      _synth = null;
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
    // Cache the raw future, errors and all: a failed synthesis must surface
    // when speak() consumes it, not silently become an empty clip the play
    // loop skips over (that's the chapter-skipping in #30). ignore() only
    // silences the unhandled-error zone warning if no one ever awaits it.
    _cache[s] = _prepare(s)..ignore();
    while (_cache.length > _maxCache) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// With PCM streaming there is nothing left to "arm" — a cached sentence
  /// starts instantly from RAM — so this is just a precache hint.
  @override
  void preloadNext(String text) => precache(text);

  @override
  Future<void> speak(String text) async {
    // A real check, not an assert: asserts vanish in release builds, and
    // speaking through an uninitialised engine is exactly the silent failure
    // mode of #30. A synthesis failure below also throws — the controller
    // stops playback and surfaces it instead of sprinting through sentences.
    if (!_inited) {
      throw StateError('NeuralNarrator.speak() called before init()');
    }
    _stopRequested = false;
    final s = text.trim();
    if (s.isEmpty) return;

    // If audio isn't flowing shortly, tell the UI we're buffering (#40).
    _bufferingWatch();
    try {
      final cached = _cache.remove(s);
      if (cached != null) {
        await _speakPrepared(await cached);
      } else {
        await _speakStreaming(s);
      }
    } finally {
      _bufferingDone();
      _current = null;
    }
  }

  /// Cached path: every chunk is already synthesized — push them all and play.
  Future<void> _speakPrepared(_PreparedPcm prep) async {
    if (_stopRequested || prep.isEmpty) return;
    final utter = await _startUtterance(prep.sampleRate);
    if (_stopRequested) {
      await utter.stop();
      return;
    }
    _current = utter;
    _bufferingDone();
    for (final chunk in prep.chunks) {
      await utter.add(chunk);
    }
    utter.end();
    _lastUtteranceMs = prep.audioMs;
    await utter.done;
  }

  /// Cold path: stream chunk-by-chunk — playback starts on the first chunk
  /// while the rest are still synthesizing (the isolate serves requests in
  /// order, so pushes arrive in sentence order).
  Future<void> _speakStreaming(String s) async {
    final synth = _synth;
    if (synth == null) throw StateError('narrator not initialised');
    final texts = _chunkForSynthesis(s);
    final parts = [for (final c in texts) synth.synth(c, speed: _speed)];
    PcmUtterance? utter;
    var totalMs = 0;
    for (var i = 0; i < parts.length; i++) {
      final (samples, sampleRate) = await parts[i];
      if (_stopRequested) {
        await utter?.stop();
        return;
      }
      if (samples.isEmpty) continue;
      final shaped = _shape(samples, sampleRate,
          lastChunk: i == parts.length - 1);
      if (shaped.isEmpty) continue;
      totalMs += (shaped.length * 1000 / sampleRate).round();
      if (utter == null) {
        utter = await _startUtterance(sampleRate);
        if (_stopRequested) {
          await utter.stop();
          return;
        }
        _current = utter;
        _bufferingDone();
      }
      await utter.add(shaped);
    }
    if (utter == null) return; // nothing narratable synthesized
    utter.end();
    _lastUtteranceMs = totalMs;
    await utter.done;
  }

  Future<PcmUtterance> _startUtterance(int sampleRate) async {
    if (!_playbackReady) {
      await _playback.init();
      _playbackReady = true;
    }
    final utter =
        await _playback.start(sampleRate: sampleRate, volume: _volume);
    // Re-assert a pause that arrived before playback was live (#11).
    if (_paused) await utter.pause();
    return utter;
  }

  // ---- buffering signal (#40) ----

  void _bufferingWatch() {
    _bufferingTimer?.cancel();
    _bufferingTimer = Timer(const Duration(milliseconds: 250), () {
      _bufferingRaised = true;
      onBuffering?.call(true);
    });
  }

  void _bufferingDone() {
    _bufferingTimer?.cancel();
    _bufferingTimer = null;
    if (_bufferingRaised) {
      _bufferingRaised = false;
      onBuffering?.call(false);
    }
  }

  /// Synthesize [s] fully (all chunks) for the look-ahead cache.
  Future<_PreparedPcm> _prepare(String s) async {
    final synth = _synth;
    if (synth == null) throw StateError('narrator not initialised');
    final texts = _chunkForSynthesis(s);
    final parts =
        await Future.wait(texts.map((c) => synth.synth(c, speed: _speed)));

    final chunks = <Float32List>[];
    var sampleRate = 0;
    var totalMs = 0;
    for (var i = 0; i < parts.length; i++) {
      final (samples, sr) = parts[i];
      if (samples.isEmpty) continue;
      final shaped = _shape(samples, sr, lastChunk: i == parts.length - 1);
      if (shaped.isEmpty) continue;
      sampleRate = sr;
      totalMs += (shaped.length * 1000 / sr).round();
      chunks.add(shaped);
    }
    return _PreparedPcm(chunks, sampleRate, totalMs);
  }

  /// Trim excess edge silence and, between clause-chunks, restore a natural
  /// breath: chunks are synthesized as separate utterances, so their edges
  /// carry model lead-in/lead-out that would otherwise butt together
  /// unnaturally. Margins are deliberately gentler than the old WAV path
  /// (which clipped Piper's sentence tails to 60 ms).
  Float32List _shape(Float32List samples, int sampleRate,
      {required bool lastChunk}) {
    final trimmed = _trimSilence(samples, sampleRate);
    if (trimmed.isEmpty || lastChunk) return trimmed;
    // Clause pad: ~100 ms of true silence at a `, ; : —` join.
    final pad = (sampleRate * 0.1).round();
    final out = Float32List(trimmed.length + pad);
    out.setRange(0, trimmed.length, trimmed);
    return out;
  }

  /// Trim contiguous near-silence from clip edges, keeping a small margin
  /// (lead 40 ms / trail 120 ms).
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
    final leadMargin = (sr * 0.04).round();
    final trailMargin = (sr * 0.12).round();
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
    _volume = volume.clamp(0.0, 1.0);
    await _current?.setVolume(_volume);
  }

  /// Narration speed (#34): re-times synthesis through the VITS duration
  /// predictor (sherpa-onnx divides the voice's length scale by this), which
  /// keeps pitch and articulation natural. Cached audio was synthesized at
  /// the old speed, so the look-ahead is discarded; takes effect from the
  /// next un-cached sentence.
  @override
  Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.5, 3.0).toDouble();
    if (v == _speed) return;
    _speed = v;
    _cache.clear();
  }

  @override
  Future<void> pause() async {
    // Park the active utterance in place. The speak loop stays parked on the
    // utterance's `done` future, so resume() continues exactly where it left
    // off. The flag lets utterance start re-apply this if it raced the first
    // playback start (#11).
    _paused = true;
    await _current?.pause();
  }

  @override
  Future<void> resume() async {
    _paused = false;
    await _current?.resume();
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    _paused = false;
    final u = _current;
    _current = null;
    if (u != null) await u.stop(); // completes its `done`, unblocking speak()
  }

  @override
  Future<void> dispose() async {
    await stop();
    _bufferingTimer?.cancel();
    _synth?.dispose();
    _synth = null;
    _inited = false;
    if (_playbackReady) {
      _playbackReady = false;
      await _playback.dispose();
    }
  }
}

/// A synthesized sentence ready to play: shaped PCM chunks in RAM.
class _PreparedPcm {
  final List<Float32List> chunks;
  final int sampleRate;
  final int audioMs;
  const _PreparedPcm(this.chunks, this.sampleRate, this.audioMs);
  bool get isEmpty => chunks.isEmpty;
}
