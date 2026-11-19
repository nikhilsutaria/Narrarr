import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

/// The playback seam for [NeuralNarrator] (#33): synthesized PCM is pushed
/// straight into an audio buffer stream — no WAV files, no per-clip player
/// loads, so chunk hand-offs inside a sentence are sample-continuous instead
/// of masked with a second player. Injectable so engine tests exercise the
/// full speak loop without native audio (the repo-wide "tests avoid native
/// code" rule); production uses [SoLoudPcmPlayback].
abstract class PcmPlayback {
  /// Start the audio engine. Idempotent; called lazily on first playback so
  /// merely constructing the narrator stays off the platform.
  Future<void> init();

  /// Open a new utterance stream at [sampleRate] (mono float PCM). The
  /// utterance plays as data is [PcmUtterance.add]ed and finishes after
  /// [PcmUtterance.end] once all pushed audio has been heard.
  Future<PcmUtterance> start({required int sampleRate, double volume = 1.0});

  /// Release the audio engine.
  Future<void> dispose();
}

/// One playing utterance: a push-based PCM stream with transport control.
abstract class PcmUtterance {
  /// Append mono float samples. Playback starts on the first push.
  Future<void> add(Float32List samples);

  /// No more data will be pushed; the utterance ends when playback drains.
  void end();

  /// Completes when the audio has finished playing (naturally or via [stop]).
  Future<void> get done;

  Future<void> pause();
  Future<void> resume();

  /// Abort playback; [done] completes.
  Future<void> stop();

  Future<void> setVolume(double volume);
}

/// Production [PcmPlayback] backed by flutter_soloud's buffer-stream API —
/// purpose-built for "feed PCM chunks as TTS generates them".
class SoLoudPcmPlayback implements PcmPlayback {
  SoLoud get _soloud => SoLoud.instance;

  @override
  Future<void> init() async {
    if (!_soloud.isInitialized) await _soloud.init();
  }

  @override
  Future<PcmUtterance> start(
      {required int sampleRate, double volume = 1.0}) async {
    final source = _soloud.setBufferStream(
      sampleRate: sampleRate,
      channels: Channels.mono,
      format: BufferType.f32le,
      // Un-pause as soon as a quarter-second is buffered: the synth look-ahead
      // keeps the stream fed, and a long pre-roll would just be start latency.
      bufferingTimeNeeds: 0.25,
      // A sentence is seconds long; minutes of headroom costs nothing (this is
      // a cap, not an allocation).
      maxBufferSizeDuration: const Duration(minutes: 10),
    );
    return _SoLoudUtterance(_soloud, source, volume);
  }

  @override
  Future<void> dispose() async {
    if (_soloud.isInitialized) _soloud.deinit();
  }
}

class _SoLoudUtterance implements PcmUtterance {
  _SoLoudUtterance(this._soloud, this._source, this._volume) {
    _finishedSub = _source.allInstancesFinished.listen((_) => _finish());
  }

  final SoLoud _soloud;
  final AudioSource _source;
  double _volume;

  StreamSubscription<void>? _finishedSub;
  SoundHandle? _handle;
  final Completer<void> _done = Completer<void>();
  bool _stopped = false;
  bool _pauseWanted = false;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> add(Float32List samples) async {
    if (_stopped || samples.isEmpty) return;
    _soloud.addAudioDataStream(
      _source,
      samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes),
    );
    if (_handle == null) {
      final h = _handle = await _soloud.play(_source, volume: _volume);
      // A pause (or a stop) may have landed while play() was in flight on the
      // native side — same race as the narrator's #11 fix. Re-assert it.
      if (_stopped) {
        await _soloud.stop(h);
        _finish();
      } else if (_pauseWanted) {
        _soloud.setPause(h, true);
      }
    } else if (_pauseWanted) {
      // SoLoud auto-unpauses a stream it paused for buffering when new data
      // arrives; make sure a user pause survives the push.
      _soloud.setPause(_handle!, true);
    }
  }

  @override
  void end() {
    if (_stopped) return;
    _soloud.setDataIsEnded(_source);
  }

  @override
  Future<void> pause() async {
    _pauseWanted = true;
    final h = _handle;
    if (h != null && !_stopped) _soloud.setPause(h, true);
  }

  @override
  Future<void> resume() async {
    _pauseWanted = false;
    final h = _handle;
    if (h != null && !_stopped) _soloud.setPause(h, false);
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    final h = _handle;
    if (h != null) await _soloud.stop(h);
    _finish();
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    final h = _handle;
    if (h != null && !_stopped) _soloud.setVolume(h, volume);
  }

  void _finish() {
    _finishedSub?.cancel();
    _finishedSub = null;
    if (!_done.isCompleted) _done.complete();
    // Buffer streams are one-shot; release the native buffer.
    unawaited(_soloud.disposeSource(_source));
  }
}
