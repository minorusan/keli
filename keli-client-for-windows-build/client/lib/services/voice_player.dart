import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../app_log.dart';
import '../face/maradel_voice_client.dart';

/// Plays Maradel's spoken reply **on the tablet** — the missing "reply path" so the robot answers out
/// loud where you're standing (see Sound_api.md: the mic→voice-turn path otherwise only reaches the
/// room speaker + the `:9100` socket, never the tablet).
///
/// It subscribes to the Maradel backend's `:9100` Socket.IO (via [MaradelVoiceClient]) and plays each
/// `voice:chunk` WAV in arrival order through the device speaker (audioplayers — the reliable mobile
/// path: finite WAVs, not the endless MP3). It also exposes [speaking] (`voice:speaking`), which the
/// mic streamer uses to mute itself so the tablet doesn't hear its own voice.
class VoicePlayer extends ChangeNotifier {
  final MaradelVoiceClient _voice = MaradelVoiceClient();
  final AudioPlayer _player = AudioPlayer();
  final List<String> _queue = [];
  bool _playing = false;
  bool _connected = false;
  bool _speaking = false;
  int _played = 0;
  double _volume = 1.0;

  /// True between `voice:speaking{on:true/false}` — drives the mic echo-guard.
  bool get speaking => _speaking;

  /// Whether the `:9100` voice socket is connected.
  bool get connected => _connected;

  /// Count of reply chunks played this session.
  int get played => _played;

  /// Master output gain (0..1), from the per-Keli config. Applied to the player immediately and to
  /// every subsequent chunk.
  void setVolume(double v) {
    final clamped = v.clamp(0.0, 1.0);
    if (clamped == _volume) return;
    _volume = clamped;
    _player.setVolume(_volume);
  }

  VoicePlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
    _voice.onConnected = (c) {
      _connected = c;
      AppLog.log('voice', c ? 'reply socket connected (:9100)' : 'reply socket disconnected');
      notifyListeners();
    };
    _voice.onSpeaking = (on) {
      _speaking = on;
      notifyListeners();
    };
    _voice.onChunk = (chunk) {
      _queue.add(chunk.absoluteUrl);
      unawaited(_drain());
    };
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      unawaited(_drain());
    });
  }

  Future<void> _drain() async {
    if (_playing || _queue.isEmpty) return;
    _playing = true;
    final url = _queue.removeAt(0);
    try {
      await _player.stop();
      await _player.setVolume(_volume);
      await _player.play(UrlSource(url));
      _played++;
      AppLog.log('voice', 'playing reply chunk #$_played ($url)');
      notifyListeners();
    } catch (e) {
      AppLog.log('voice', 'play failed: $e');
      _playing = false;
      unawaited(_drain()); // skip the bad chunk, keep going
    }
  }

  @override
  void dispose() {
    _voice.dispose();
    _player.dispose();
    super.dispose();
  }
}
