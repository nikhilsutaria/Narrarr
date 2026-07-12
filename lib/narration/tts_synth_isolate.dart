import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart'; // RootIsolateToken, BackgroundIsolateBinaryMessenger
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

/// Runs sherpa-onnx TTS synthesis on a **persistent background isolate**.
///
/// Why an isolate: `OfflineTts.generate()` is a blocking, CPU-bound FFI call.
/// On the UI isolate it freezes the app (janky scroll, laggy buttons) and —
/// worse for us — it forces synth and playback to happen serially, which is
/// what produced the 2–3s gap between sentences. Off the UI thread we can
/// synthesize the *next* sentence while the current one is still playing.
///
/// Native pointers can't cross a SendPort, so the `OfflineTts` is constructed
/// **inside** the isolate (it loads the model once); the main side only ships
/// text in and gets PCM samples back. Pattern adapted from the official
/// sherpa-onnx flutter-examples/tts `isolate_tts.dart`.
class TtsSynthIsolate {
  Isolate? _isolate;
  SendPort? _toIsolate;
  ReceivePort? _fromIsolate;
  final Completer<void> _ready = Completer<void>();
  Future<void>? _starting;
  final Map<int, Completer<(Float32List, int)>> _pending = {};
  int _nextId = 0;
  bool _disposed = false;

  /// Spawn the isolate and wait until it has built `OfflineTts` (or failed to).
  ///
  /// Single-flight and failure-aware (#30): concurrent callers share one
  /// in-flight future and none returns before the ready handshake, and a model
  /// that fails to load makes this **throw** instead of hanging forever. A
  /// failed instance stays failed — the narrator builds a fresh one per retry.
  Future<void> start({
    required String model,
    required String tokens,
    required String dataDir,
    int numThreads = 2,
  }) {
    return _starting ??= _start(
      model: model,
      tokens: tokens,
      dataDir: dataDir,
      numThreads: numThreads,
    );
  }

  Future<void> _start({
    required String model,
    required String tokens,
    required String dataDir,
    required int numThreads,
  }) async {
    if (_disposed) throw StateError('TtsSynthIsolate already disposed');
    _fromIsolate = ReceivePort()..listen(_onMessage);

    _isolate = await Isolate.spawn<_SpawnArgs>(
      _entry,
      _SpawnArgs(
        _fromIsolate!.sendPort,
        RootIsolateToken.instance, // null outside a Flutter app (tests)
        model,
        tokens,
        dataDir,
        numThreads,
      ),
      errorsAreFatal: false,
      debugName: 'TtsSynthIsolate',
    );

    await _ready.future; // resolves once the isolate built OfflineTts
  }

  /// Synthesize [text] off the UI thread. Multiple calls can be in flight; each
  /// resolves to its own result via an id-routed completer. Requests are served
  /// in arrival order by the single isolate.
  Future<(Float32List samples, int sampleRate)> synth(
    String text, {
    int sid = 0,
    double speed = 1.0,
  }) {
    if (_disposed || _toIsolate == null) {
      return Future.error(StateError('TtsSynthIsolate not started/disposed'));
    }
    final id = _nextId++;
    final c = Completer<(Float32List, int)>();
    _pending[id] = c;
    _toIsolate!.send(_Req(id, text, sid, speed));
    return c.future;
  }

  void _onMessage(dynamic msg) {
    if (msg is SendPort) {
      _toIsolate = msg;
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    if (msg is _StartupError) {
      // The isolate could not construct OfflineTts (missing/corrupt model).
      // Fail the awaiting start() instead of leaving it hanging forever (#30).
      if (!_ready.isCompleted) {
        _ready.completeError(
            StateError('TTS engine failed to start: ${msg.message}'));
      }
      return;
    }
    if (msg is _Resp) {
      final c = _pending.remove(msg.id);
      if (c == null) return;
      if (msg.error != null) {
        c.completeError(StateError(msg.error!));
      } else {
        c.complete((msg.samples, msg.sampleRate));
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Unblock a start() that is still waiting on the ready handshake.
    if (_starting != null && !_ready.isCompleted) {
      _ready.completeError(StateError('TtsSynthIsolate disposed during start'));
    }
    try {
      _toIsolate?.send('shutdown');
    } catch (_) {}
    _fromIsolate?.close();
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('disposed'));
    }
    _pending.clear();
  }

  // ---- runs in the background isolate ----
  static void _entry(_SpawnArgs args) {
    // Anything that fails before the handshake must be reported back — with
    // `errorsAreFatal: false` an uncaught throw here would otherwise leave the
    // main side awaiting the handshake forever (#30).
    final so.OfflineTts tts;
    try {
      final token = args.rootToken;
      if (token != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      }

      so.initBindings(); // FFI bindings are per-isolate

      final config = so.OfflineTtsConfig(
        model: so.OfflineTtsModelConfig(
          vits: so.OfflineTtsVitsModelConfig(
            model: args.model,
            tokens: args.tokens,
            dataDir: args.dataDir,
          ),
          numThreads: args.numThreads,
          debug: false,
          provider: 'cpu',
        ),
        maxNumSenetences: 1,
      );
      tts = so.OfflineTts(config);
    } catch (e) {
      args.mainSendPort.send(_StartupError(e.toString()));
      return;
    }

    final inbox = ReceivePort();
    args.mainSendPort.send(inbox.sendPort); // ready handshake

    inbox.listen((msg) {
      if (msg == 'shutdown') {
        tts.free();
        inbox.close();
        Isolate.exit();
      }
      if (msg is _Req) {
        try {
          final audio = tts.generate(text: msg.text, sid: msg.sid, speed: msg.speed);
          args.mainSendPort.send(_Resp(msg.id, audio.samples, audio.sampleRate, null));
        } catch (e) {
          args.mainSendPort.send(_Resp(msg.id, Float32List(0), 0, e.toString()));
        }
      }
    });
  }
}

class _SpawnArgs {
  final SendPort mainSendPort;
  final RootIsolateToken? rootToken;
  final String model;
  final String tokens;
  final String dataDir;
  final int numThreads;
  const _SpawnArgs(this.mainSendPort, this.rootToken, this.model, this.tokens,
      this.dataDir, this.numThreads);
}

/// Sent instead of the handshake `SendPort` when the isolate failed to build
/// `OfflineTts`, so the main side's `start()` can throw instead of hanging.
class _StartupError {
  final String message;
  const _StartupError(this.message);
}

class _Req {
  final int id;
  final String text;
  final int sid;
  final double speed;
  const _Req(this.id, this.text, this.sid, this.speed);
}

class _Resp {
  final int id;
  final Float32List samples;
  final int sampleRate;
  final String? error;
  const _Resp(this.id, this.samples, this.sampleRate, this.error);
}
