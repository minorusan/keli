import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_log.dart';
import '../config.dart';

/// One voice synthesized sentence Maradel is about to speak (the `voice:chunk` event). The face
/// plays/analyzes the WAV at [absoluteUrl]; [index] orders the queue; [durationSec] is its length.
class VoiceChunk {
  final String url; // path as sent by Maradel, e.g. /voice/file/<sid>/<n>.wav
  final int index;
  final double durationSec;
  const VoiceChunk({required this.url, required this.index, required this.durationSec});

  /// Absolute URL for Unity's UnityWebRequest / a player (Maradel serves the WAV).
  String get absoluteUrl => url.startsWith('http') ? url : '$kMaradelUrl$url';

  factory VoiceChunk.fromJson(Map<String, dynamic> j) => VoiceChunk(
        url: '${j['url'] ?? ''}',
        index: (j['index'] as num?)?.toInt() ?? 0,
        durationSec: (j['durationSec'] as num?)?.toDouble() ?? 0,
      );
}

/// A minimal, voice-only Socket.IO connection to the **Maradel backend** (:9100). Keli's main traffic
/// goes to the Keli backend (:9120); the 3D face needs Maradel's speech events, so this opens a second,
/// read-only socket just for `voice:chunk` and `voice:speaking`. Owned by [UnityFaceBridge].
class MaradelVoiceClient {
  late final io.Socket _socket;
  void Function(VoiceChunk chunk)? onChunk;
  void Function(bool speaking)? onSpeaking;
  void Function(bool connected)? onConnected;
  void Function(String emotion)? onEmotion;

  MaradelVoiceClient() {
    _socket = io.io(
      kMaradelUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );
    _socket.onConnect((_) {
      AppLog.log('voice', 'maradel voice socket connected');
      onConnected?.call(true);
    });
    _socket.onDisconnect((_) => onConnected?.call(false));
    _socket.on('voice:chunk', (d) {
      if (d is Map) onChunk?.call(VoiceChunk.fromJson(Map<String, dynamic>.from(d)));
    });
    _socket.on('voice:speaking', (d) {
      if (d is Map) onSpeaking?.call(d['on'] == true);
    });
    // Reply emotion → drives the Unity face mood (facial + body).
    _socket.on('voice:emotion', (d) {
      if (d is Map) {
        final e = '${d['emotion'] ?? ''}'.trim();
        if (e.isNotEmpty) onEmotion?.call(e);
      }
    });
  }

  void dispose() {
    _socket.dispose();
  }
}
