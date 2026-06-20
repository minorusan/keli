import 'package:flutter/foundation.dart';

import '../app_log.dart';
import 'face_protocol.dart';
import 'maradel_voice_client.dart';

/// The seam between Keli and the embedded Unity face. A real impl wraps `flutter_embed_unity`
/// (`sendToUnity` out, the `onMessage` callback in); until the Unity project lands we use
/// [LoggingUnitySink] so the whole Flutter half compiles, ships, and is testable without the Unity
/// binary. Swapping to the real sink is a one-line change in the provider wiring.
abstract class UnitySink {
  /// Send `message` to `method` on the Unity GameObject `gameObject` (UaaL string protocol).
  void send(String gameObject, String method, String message);

  /// Inbound envelopes from Unity (`SendToFlutter.Send`). Wire to flutter_embed_unity's onMessage.
  set onInbound(void Function(String raw)? handler);
}

/// No-op sink for the pre-Unity phase: logs what *would* be sent so you can verify the bridge live.
class LoggingUnitySink implements UnitySink {
  @override
  void send(String gameObject, String method, String message) =>
      AppLog.log('face', '→unity $gameObject.$method $message');

  @override
  set onInbound(void Function(String raw)? handler) {/* no Unity to receive from yet */}
}

/// Orchestrates the 3D face from the Flutter side (LIPSYNC.md §6):
/// - forwards Maradel's `voice:chunk` → Unity `playChunk`, `voice:speaking{off}` → `stop`;
/// - tracks face state from Unity's inbound `ready` / `speaking*` events;
/// - exposes that state to the UI (ChangeNotifier).
///
/// Unity OWNS the audio (fetches the WAV from Maradel and analyzes it with uLipSync) — Flutter only
/// tells it *which* chunk to play. This keeps lipsync perfectly in sync (no cross-process drift).
class UnityFaceBridge extends ChangeNotifier {
  final UnitySink _sink;
  final MaradelVoiceClient _voice;

  bool _voiceConnected = false;
  bool _faceReady = false;
  bool _speaking = false;
  int _chunksSent = 0;
  String? _lastError;

  bool get voiceConnected => _voiceConnected;
  bool get faceReady => _faceReady;
  bool get speaking => _speaking;
  int get chunksSent => _chunksSent;
  String? get lastError => _lastError;

  UnityFaceBridge({required UnitySink sink, MaradelVoiceClient? voice})
      : _sink = sink,
        _voice = voice ?? MaradelVoiceClient() {
    _sink.onInbound = _onUnityMessage;
    _voice.onConnected = (c) { _voiceConnected = c; notifyListeners(); };
    _voice.onChunk = _onVoiceChunk;
    _voice.onSpeaking = (on) { if (!on) _send(FaceProtocol.stop); };
    // Reply emotion → Unity face mood (facial + body). Logged so it shows in the shared log.
    _voice.onEmotion = (mood) { AppLog.log('unity', '→setMood $mood'); setMood(mood); };
  }

  // ── Maradel voice → Unity ──
  void _onVoiceChunk(VoiceChunk c) {
    _chunksSent++;
    _send(FaceProtocol.playChunk, {'url': c.absoluteUrl, 'index': c.index, 'durationSec': c.durationSec});
    notifyListeners();
  }

  void setMood(String mood) => _send(FaceProtocol.setMood, {'mood': mood});
  void stop() => _send(FaceProtocol.stop);

  void _send(String type, [Map<String, dynamic> payload = const {}]) =>
      _sink.send(FaceProtocol.gameObject, FaceProtocol.inboundMethod, FaceProtocol.encode(type, payload));

  // ── Unity → Flutter ──
  void _onUnityMessage(String raw) {
    final (:type, :payload) = FaceProtocol.decode(raw);
    switch (type) {
      case FaceProtocol.ready:
        _faceReady = true;
        AppLog.log('unity', 'face ready');
        break;
      case FaceProtocol.speakingStarted:
        _speaking = true;
        break;
      case FaceProtocol.speakingStopped:
        _speaking = false;
        break;
      case FaceProtocol.error:
        _lastError = '${payload['message'] ?? 'unknown'}';
        AppLog.log('unity', 'error: $_lastError');
        break;
      case FaceProtocol.log: // Unity console line forwarded over the bridge → shared keli log
        AppLog.log('unity', '${payload['level'] ?? ''}${payload['level'] != null ? ': ' : ''}${payload['msg'] ?? payload['message'] ?? ''}');
        return;
      case FaceProtocol.visemeFrame: // lipsync output — per-frame, too noisy to log (would flood the log)
        return;
      default:
        AppLog.log('unity', 'msg: $raw'); // never drop an inbound Unity message
        return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _voice.dispose();
    super.dispose();
  }
}
