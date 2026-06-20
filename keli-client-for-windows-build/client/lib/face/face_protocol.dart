import 'dart:convert';

/// The Flutter↔Unity message contract for the 3D lipsync face — the EXACT mirror of the Unity-side
/// `FlutterFace.cs` (see ~/shared/LIPSYNC.md §5). Keep these constants in lockstep with that file:
/// it is the one protocol, two mirrors (like the rest of Maradel's events).
///
/// Transport (when the Unity project lands): Flutter→Unity is
/// `sendToUnity(kGameObject, kInboundMethod, <envelope json>)`; Unity→Flutter is
/// `SendToFlutter.Send(<envelope json>)`. The envelope is `{type, json}` where `json` is the
/// stringified payload — matching `FlutterFace.Envelope` / `JsonUtility`.
class FaceProtocol {
  /// The named GameObject + method `flutter_embed_unity` delivers inbound calls to.
  static const String gameObject = 'FlutterFace';
  static const String inboundMethod = 'OnMessage';

  // Flutter → Unity
  static const String playChunk = 'playChunk'; // {url, index, durationSec}
  static const String stop = 'stop';
  static const String setMood = 'setMood'; // {mood}
  static const String pushPcm = 'pushPcm'; // {b64, sampleRate, channels} (optional)

  // Unity → Flutter
  static const String ready = 'ready';
  static const String speakingStarted = 'speakingStarted';
  static const String speakingStopped = 'speakingStopped';
  static const String visemeFrame = 'visemeFrame'; // {dominant, volume}
  static const String error = 'error'; // {message}
  // Unity console → shared keli log. The Unity side forwards Application.logMessageReceived as
  // SendToFlutter.Send(envelope("log", {msg, level})); Flutter pipes it into AppLog('unity').
  static const String log = 'log'; // {msg, level}

  /// Build the `{type, json}` envelope string Unity's `FlutterFaceBridge.OnMessage` expects.
  static String encode(String type, [Map<String, dynamic> payload = const {}]) =>
      jsonEncode({'type': type, 'json': jsonEncode(payload)});

  /// Parse an inbound envelope from Unity into (type, payload).
  static ({String type, Map<String, dynamic> payload}) decode(String raw) {
    try {
      final env = jsonDecode(raw) as Map<String, dynamic>;
      final inner = env['json'];
      final payload = inner is String && inner.isNotEmpty
          ? (jsonDecode(inner) as Map<String, dynamic>)
          : (inner is Map ? Map<String, dynamic>.from(inner) : <String, dynamic>{});
      return (type: '${env['type'] ?? ''}', payload: payload);
    } catch (_) {
      return (type: '', payload: <String, dynamic>{});
    }
  }
}
