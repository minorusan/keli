import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_log.dart';
import '../config.dart';

/// Streams the tablet microphone to Maradel — the robot's "ears".
///
/// Pipeline (matches the backend `vadwatch/keliMic.ts` → `handleKeliAudioWs`):
///   device mic → `record` (raw s16le / 16 kHz / mono PCM)
///             → a **WebSocket** to `ws://192.168.0.229:9100/keli/audio?deviceId=<id>`,
///               each chunk a **binary** message  (this is the transport the backend documents as
///               "what the Keli app uses"; the HTTP POST body is only a curl-test fallback)
///             → backend pipes the bytes into a FIFO → existing ffmpeg/VAD/Whisper loop → reply + TTS.
///
/// **Wire contract:** raw signed-16 little-endian PCM, 16000 Hz, mono, no header. Continuous (silence
/// included) — the server-side VAD owns speech boundaries; NOT push-to-talk.
///
/// **Echo guard:** while Maradel is speaking we send **silence** so her voice (played on the tablet /
/// room speaker) can't re-trigger the VAD. The speaking flag is fed via [setSpeaking] from the
/// `:9100` `voice:speaking` event (see VoicePlayer) — NOT the Keli `:9120` socket, which never carries it.
class MicStreamer extends ChangeNotifier {
  static const _enabledKey = 'keli.ears.enabled';
  static const _deviceKey = 'keli.deviceId'; // same key KeliConnection persists

  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Uint8List>? _audioSub;
  WebSocket? _ws;
  bool _enabled = false;
  bool _connected = false;
  bool _connecting = false;
  bool _maradelSpeaking = false;
  bool _starting = false;
  bool _disposed = false;
  bool _gotAudio = false;
  Timer? _watchdog;
  int _backoffMs = 1000;
  int _consecutiveFails = 0;
  double _level = 0;
  int _chunksSent = 0;
  String _detail = 'off';

  /// Live input level (0..1) of the most recent chunk — drives the VU meter (ValueNotifier so only the
  /// meter repaints).
  final ValueNotifier<double> levelVN = ValueNotifier<double>(0);

  /// Count of PCM chunks pushed this session — drives the "chunks sent" readout.
  final ValueNotifier<int> chunksVN = ValueNotifier<int>(0);

  bool get enabled => _enabled;
  bool get connected => _connected;
  bool get speaking => _maradelSpeaking;
  double get level => _level;
  String get detail => _detail;
  String get target => kMaradelAudioWsUrl;

  MicStreamer() {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_enabledKey) == true) await setEnabled(true);
    } catch (_) {/* nothing persisted */}
  }

  /// Fed from `:9100` `voice:speaking` (via the provider wiring). While true we stream silence.
  void setSpeaking(bool on) {
    if (on == _maradelSpeaking) return;
    _maradelSpeaking = on;
    notifyListeners();
  }

  /// Turn the ears on/off. Persisted across restarts.
  Future<void> setEnabled(bool on) async {
    if (on == _enabled) return;
    _enabled = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, on);
    } catch (_) {/* best-effort */}
    if (on) {
      await _start();
    } else {
      await _stop();
    }
    notifyListeners();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    _detail = 'starting…';
    notifyListeners();

    // Explicit permission (reliable prompt on old Android), then record's own check as a backstop.
    bool granted = false;
    try {
      var ps = await Permission.microphone.status;
      if (!ps.isGranted) ps = await Permission.microphone.request();
      AppLog.log('mic', 'mic permission: $ps');
      granted = ps.isGranted;
      if (granted) {
        try {
          granted = await _recorder.hasPermission();
        } catch (_) {}
      } else if (ps.isPermanentlyDenied) {
        AppLog.log('mic', 'permission permanently denied — enable Microphone in Android Settings → Apps → Keli');
      }
    } catch (e) {
      granted = false;
      AppLog.log('mic', 'permission check failed: $e');
    }
    if (!granted) {
      _enabled = false;
      _starting = false;
      _detail = 'mic permission denied';
      AppLog.log('mic', 'permission denied — ears stay off');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_enabledKey, false);
      } catch (_) {}
      notifyListeners();
      return;
    }

    try {
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits, // raw s16le — exactly what the backend expects
        sampleRate: 16000,
        numChannels: 1,
        // Force the raw MIC source: the default source returns SILENCE / empty capture on some OEM
        // devices (e.g. LG/Huawei) even with permission granted.
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
      ));
      _gotAudio = false;
      _audioSub = stream.listen(_onPcm, onError: (e) => AppLog.log('mic', 'capture stream error: $e'));
      AppLog.log('mic', 'capture started (s16le 16k mono) — waiting for audio…');
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 3), () {
        if (_enabled && !_gotAudio) {
          AppLog.log('mic', 'NO audio after 3s — permission ok but mic delivered no PCM (another app using the mic? device blocked it?)');
          _detail = 'mic gave no audio';
          notifyListeners();
        }
      });
    } catch (e) {
      _enabled = false;
      _starting = false;
      _detail = 'recorder error';
      AppLog.log('mic', 'startStream failed: $e');
      notifyListeners();
      return;
    }

    _starting = false;
    unawaited(_ensureSocket());
  }

  Future<void> _stop() async {
    _detail = 'off';
    _watchdog?.cancel();
    _gotAudio = false;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      await _ws?.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
    _connecting = false;
    _level = 0;
    levelVN.value = 0;
    _chunksSent = 0;
    chunksVN.value = 0;
    AppLog.log('mic', 'ears off');
    notifyListeners();
  }

  // ── mic → WebSocket ──
  void _onPcm(Uint8List bytes) {
    if (!_enabled) return;
    if (!_gotAudio) {
      _gotAudio = true;
      _watchdog?.cancel();
      AppLog.log('mic', 'mic live: first chunk ${bytes.length} bytes');
    }
    _level = _rms(bytes);
    levelVN.value = _level;
    final ws = _ws;
    if (ws == null) return; // not connected yet → drop this slice
    final out = _maradelSpeaking ? Uint8List(bytes.length) : bytes; // silence while Maradel talks
    try {
      ws.add(out); // binary frame
      _chunksSent++;
      chunksVN.value = _chunksSent;
    } catch (e) {
      AppLog.log('mic', 'ws write failed: $e');
      _dropSocket();
    }
  }

  // ── WebSocket lifecycle (connect + reconnect w/ backoff) ──
  Future<void> _ensureSocket() async {
    if (!_enabled || _disposed || _ws != null || _connecting) return;
    _connecting = true;
    _detail = 'connecting…';
    notifyListeners();
    try {
      final dev = await _deviceId();
      final url = '$kMaradelAudioWsUrl?deviceId=${Uri.encodeQueryComponent(dev)}';
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 8));
      _ws = ws;
      _connected = true;
      _connecting = false;
      _backoffMs = 1000;
      if (_consecutiveFails > 0) AppLog.log('mic', 'reconnected');
      _consecutiveFails = 0;
      _detail = 'streaming → $target';
      AppLog.log('mic', 'ws connected → $url');
      notifyListeners();
      ws.listen((_) {}, onError: (_) => _dropSocket(), onDone: _dropSocket, cancelOnError: true);
    } catch (e) {
      _connecting = false;
      _connected = false;
      _consecutiveFails++;
      if (_consecutiveFails == 1) {
        AppLog.log('mic', 'cannot reach $target: $e — retrying quietly');
      } else if (_consecutiveFails % 12 == 0) {
        AppLog.log('mic', 'still no $target after $_consecutiveFails tries — is the backend up?');
      }
      _scheduleReconnect();
    }
  }

  void _dropSocket() {
    final had = _ws != null;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
    _connected = false;
    _connecting = false;
    if (had && _enabled && !_disposed) {
      _detail = 'reconnecting…';
      notifyListeners();
    }
    if (_enabled && !_disposed) _scheduleReconnect();
  }

  void _scheduleReconnect() {
    final ms = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(1000, 5000);
    Future.delayed(Duration(milliseconds: ms), () {
      if (_enabled && !_disposed && _ws == null) unawaited(_ensureSocket());
    });
  }

  Future<String> _deviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final d = prefs.getString(_deviceKey);
      if (d != null && d.trim().isNotEmpty) return d.trim();
    } catch (_) {}
    return 'roomba-phone';
  }

  double _rms(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final samples = Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.length ~/ 2);
    var sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }
    final meanSquare = sum / samples.length;
    if (meanSquare <= 0) return 0;
    return (math.sqrt(meanSquare) / 32768.0).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _audioSub?.cancel();
    try {
      _recorder.dispose();
    } catch (_) {}
    try {
      _ws?.close();
    } catch (_) {}
    levelVN.dispose();
    chunksVN.dispose();
    super.dispose();
  }
}
