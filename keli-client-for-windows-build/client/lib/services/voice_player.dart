import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

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
  final List<VoiceChunk> _queue = [];
  Timer? _advanceTimer; // fallback to advance the queue if onPlayerComplete never fires
  bool _playing = false;
  bool _connected = false;
  bool _speaking = false;
  int _played = 0;
  double _volume = 1.0;

  /// True between `voice:speaking{on:true/false}` — drives the mic echo-guard.
  bool get speaking => _speaking;

  /// Whether Maradel's voice is ACTUALLY occupying the speaker right now — the backend's
  /// `voice:speaking` flag OR audio still playing/queued locally. The mic echo-guard uses THIS (not
  /// `speaking`) so the mic stays muted until the device finishes draining the reply, not just until
  /// the backend stops synthesizing — otherwise the tail leaks back into the mic and self-triggers.
  bool get busy => _speaking || _playing || _queue.isNotEmpty;

  /// Whether the `:9100` voice socket is connected.
  bool get connected => _connected;

  String _attention = 'idle'; // voice:attention — idle|listening|capturing|processing
  /// Maradel is hearing you right now (wake/speech onset) — show the "listening" indicator.
  bool get hearing => _attention == 'capturing';
  /// Maradel is thinking (deaf, generating the reply) — show the "thinking" indicator.
  bool get thinking => _attention == 'processing';

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
      _queue.add(chunk);
      unawaited(_drain());
    };
    // Reply emotion (:9100 voice:emotion) → drive the embedded Unity face's mood. The main screen has
    // no UnityFaceBridge, so we forward straight to the live bridge (FlutterControlBridge.OnMessage).
    _voice.onEmotion = (mood) {
      AppLog.log('unity', '→setMood $mood');
      try {
        sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'setMood', 'text': mood}));
      } catch (e) {
        AppLog.log('voice', 'setMood send failed: $e');
      }
    };
    // Ears/attention state → the on-screen indicator + the face mood. capturing = "hearing you",
    // processing = "thinking". When she falls back to idle/listening we let the reply emotion own the mood.
    _voice.onAttention = (state) {
      if (state == _attention) return;
      _attention = state;
      final mood = switch (state) { 'capturing' => 'listening', 'processing' => 'thinking', _ => '' };
      if (mood.isNotEmpty) {
        try {
          sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'setMood', 'text': mood}));
        } catch (e) {
          AppLog.log('voice', 'setMood(attention) send failed: $e');
        }
      }
      notifyListeners();
    };
    _player.onPlayerComplete.listen((_) => _advance());
  }

  /// Move to the next queued chunk. Called by BOTH `onPlayerComplete` and the duration fallback timer —
  /// whichever fires first wins (the other is canceled), so a missed `onPlayerComplete` (audioplayers
  /// drops it on rapid stop/play) can never wedge the queue with `_playing` stuck true.
  void _advance() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _playing = false;
    notifyListeners(); // so `busy` flips false when the queue has fully drained (drives mic un-mute)
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_playing || _queue.isEmpty) return;
    _playing = true;
    final chunk = _queue.removeAt(0);
    final url = chunk.absoluteUrl;
    try {
      await _player.stop();
      await _player.setVolume(_volume);
      await _player.play(UrlSource(url));
      _played++;
      AppLog.log('voice', 'playing reply chunk #$_played ($url)');
      notifyListeners();
      // Fallback: advance after the clip's own length (+margin) in case onPlayerComplete never arrives.
      // Without this a single dropped completion event freezes ALL subsequent audio (build <=51 bug).
      _advanceTimer?.cancel();
      final ms = (((chunk.durationSec > 0 ? chunk.durationSec : 2.0) * 1000) + 800).round();
      _advanceTimer = Timer(Duration(milliseconds: ms), () {
        if (_playing) {
          AppLog.log('voice', 'advance (duration fallback, onComplete missed)');
          _advance();
        }
      });
    } catch (e) {
      AppLog.log('voice', 'play failed: $e');
      _advance(); // skip the bad chunk, keep going
    }
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _voice.dispose();
    _player.dispose();
    super.dispose();
  }
}
