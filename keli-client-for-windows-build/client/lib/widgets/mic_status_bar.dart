import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../app_log.dart';
import '../config.dart';
import '../services/keli_settings.dart';
import '../services/mic_streamer.dart';
import '../theme.dart';

/// Bottom status bar for the "ears" pipeline. Collapsed: a live voice VU meter, the connection state,
/// the chunks-sent counter, and the last log line. Tap to expand into a console: a mic-test recorder
/// (hold to record → play / send), a copy-logs button, and the scrolling live log.
class MicStatusBar extends StatefulWidget {
  const MicStatusBar({super.key});

  @override
  State<MicStatusBar> createState() => _MicStatusBarState();
}

class _MicStatusBarState extends State<MicStatusBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final mic = context.watch<MicStreamer>();
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_expanded) const _ConsolePanel(),
          _bar(context, mic),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, MicStreamer mic) {
    final on = mic.enabled;
    final connected = mic.connected;
    final stateColor = !on ? KeliTheme.muted : (connected ? KeliTheme.accent : KeliTheme.danger);
    final stateText = !on
        ? 'ears off'
        : (mic.speaking ? 'muted (Maradel speaking)' : (connected ? 'connected' : mic.detail));

    return Material(
      color: KeliTheme.surface,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: KeliTheme.surface2))),
          child: Row(
            children: [
              Icon(on ? Icons.mic : Icons.mic_off, size: 18, color: stateColor),
              const SizedBox(width: 8),
              _VuMeter(level: mic.levelVN, active: on),
              const SizedBox(width: 10),
              Container(width: 8, height: 8, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(stateText, style: TextStyle(color: stateColor, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              if (on) _ChunkCounter(chunks: mic.chunksVN),
              const SizedBox(width: 10),
              const _VoiceLevelReadout(),
              const SizedBox(width: 10),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: AppLog.revision,
                  builder: (_, _, _) => Text(
                    AppLog.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: KeliTheme.muted, fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ),
              Icon(_expanded ? Icons.expand_more : Icons.expand_less, size: 20, color: KeliTheme.muted),
              const SizedBox(width: 76), // keep clear of the FAB
            ],
          ),
        ),
      ),
    );
  }
}

/// A row of segments that light up with the mic level — the "ticking" of your voice.
class _VuMeter extends StatelessWidget {
  const _VuMeter({required this.level, required this.active});
  final ValueListenable<double> level;
  final bool active;

  static const _segments = 14;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: level,
      builder: (_, raw, _) {
        final disp = active ? (raw * 9).clamp(0.0, 1.0) : 0.0;
        final lit = (disp * _segments).round();
        return Row(
          children: List.generate(_segments, (i) {
            final isLit = i < lit;
            Color c;
            if (i >= _segments - 2) {
              c = KeliTheme.danger;
            } else if (i >= _segments - 5) {
              c = const Color(0xFFFFB300);
            } else {
              c = KeliTheme.accent;
            }
            return Container(
              width: 4,
              height: 6.0 + i * 1.1,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isLit ? c : KeliTheme.surface2,
                borderRadius: BorderRadius.circular(1),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Maradel's current master voice level (how loud she speaks here) — driven by the ambient-volume
/// brain (presence + time of day) via the `set_volume` command. Always shown so the user can see at
/// a glance how loud the tablet will speak right now.
class _VoiceLevelReadout extends StatelessWidget {
  const _VoiceLevelReadout();

  @override
  Widget build(BuildContext context) {
    final vol = context.watch<KeliSettings>().volume;
    final pct = (vol * 100).round();
    final icon = vol <= 0.001
        ? Icons.volume_off
        : (vol < 0.5 ? Icons.volume_down : Icons.volume_up);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: KeliTheme.muted),
        const SizedBox(width: 3),
        Text('$pct%',
            style: const TextStyle(
                color: KeliTheme.text, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}

class _ChunkCounter extends StatelessWidget {
  const _ChunkCounter({required this.chunks});
  final ValueListenable<int> chunks;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: chunks,
      builder: (_, n, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.north_rounded, size: 13, color: KeliTheme.accent),
          const SizedBox(width: 2),
          Text('$n', style: const TextStyle(color: KeliTheme.text, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

/// The expanded console: a mic-test toolbar on top, the scrolling live log below.
class _ConsolePanel extends StatelessWidget {
  const _ConsolePanel();

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Container(
      height: (h * 0.5).clamp(160.0, 380.0),
      width: double.infinity,
      color: KeliTheme.bg,
      child: Column(
        children: [
          const _MicTestBar(),
          const Divider(height: 1, color: KeliTheme.surface2),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: AppLog.revision,
              builder: (_, _, _) {
                final lines = AppLog.tail(400);
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  itemCount: lines.length,
                  itemBuilder: (_, i) {
                    final line = lines[lines.length - 1 - i];
                    final isErr = line.contains('failed') ||
                        line.contains('error') ||
                        line.contains('denied') ||
                        line.contains('NO audio');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: isErr ? KeliTheme.danger : KeliTheme.muted,
                          fontSize: 11,
                          fontFamily: 'monospace',
                          height: 1.3,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Mic diagnostics: **hold** to record a clip (independent of the streaming pipeline), then **play**
/// it back or **send** it to Maradel. Plus **copy logs** to the clipboard. This isolates whether the
/// microphone captures audio at all from whether the streaming works.
class _MicTestBar extends StatefulWidget {
  const _MicTestBar();

  @override
  State<_MicTestBar> createState() => _MicTestBarState();
}

class _MicTestBarState extends State<_MicTestBar> {
  final AudioRecorder _rec = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _recording = false;
  String? _clipPath;
  int _clipBytes = 0;
  bool _busy = false;
  MicStreamer? _pausedEars; // Ears stream paused for the duration of a test recording (one mic at a time)

  @override
  void dispose() {
    _rec.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<String> _path() async {
    final dir = await getTemporaryDirectory();
    return '${dir.path}/keli-mic-test.wav';
  }

  Future<void> _startHold() async {
    if (_recording || _busy) return;
    _busy = true;
    final mic = context.read<MicStreamer>();
    try {
      var ps = await Permission.microphone.status;
      if (!ps.isGranted) ps = await Permission.microphone.request();
      AppLog.log('mictest', 'mic permission: $ps');
      if (!ps.isGranted) {
        AppLog.log('mictest', ps.isPermanentlyDenied
            ? 'permission permanently denied — enable Microphone in Android Settings → Apps → Keli'
            : 'permission denied');
        _busy = false;
        return;
      }
      // Android allows only ONE mic capture at a time — pause the live Ears stream so the test
      // recorder can actually open the mic (otherwise it captures nothing → 44-byte empty WAV).
      if (mic.enabled) {
        _pausedEars = mic;
        AppLog.log('mictest', 'pausing Ears stream to free the mic for the test');
        await mic.setEnabled(false);
        await Future.delayed(const Duration(milliseconds: 300)); // let AudioRecord fully release
      }
      final path = await _path();
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          // Force raw MIC — default source captures nothing on some OEM devices (44-byte empty WAV).
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
        ),
        path: path,
      );
      setState(() => _recording = true);
      AppLog.log('mictest', 'recording… (hold)');
    } catch (e) {
      AppLog.log('mictest', 'start failed: $e (mic busy? turn Ears off and retry)');
    }
    _busy = false;
  }

  Future<void> _stopHold() async {
    if (!_recording) return;
    try {
      final path = await _rec.stop();
      _clipPath = path;
      _clipBytes = (path != null && File(path).existsSync()) ? await File(path).length() : 0;
      AppLog.log('mictest', 'recorded $_clipBytes bytes → ${path ?? "?"}'
          '${_clipBytes < 2000 ? "  ⚠ tiny/empty — mic likely captured NOTHING" : ""}');
    } catch (e) {
      AppLog.log('mictest', 'stop failed: $e');
    }
    if (mounted) setState(() => _recording = false);
    // resume the Ears stream if we paused it for the test
    final m = _pausedEars;
    _pausedEars = null;
    if (m != null) {
      AppLog.log('mictest', 'resuming Ears stream');
      await m.setEnabled(true);
    }
  }

  Future<void> _play() async {
    final p = _clipPath;
    if (p == null) return;
    try {
      AppLog.log('mictest', 'playing clip ($_clipBytes bytes)');
      await _player.stop();
      await _player.play(DeviceFileSource(p));
    } catch (e) {
      AppLog.log('mictest', 'play failed: $e');
    }
  }

  Future<void> _send() async {
    final p = _clipPath;
    if (p == null) return;
    // Upload to the lab share as a plain file (PUT /api/shared/<name>) — NOT into Maradel's chat, so
    // he doesn't read it as text or respond. Open/play it from the watcher.
    final name = 'keli-mic-test-${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      final bytes = await File(p).readAsBytes();
      final res = await http
          .put(Uri.parse('$kShareBaseUrl/$name'), headers: const {'content-type': 'audio/wav'}, body: bytes)
          .timeout(const Duration(seconds: 30));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      AppLog.log('mictest', ok ? 'uploaded clip → share/$name' : 'upload failed: HTTP ${res.statusCode}');
      _toast(ok ? 'Sent to share: $name' : 'Upload failed (${res.statusCode})');
    } catch (e) {
      AppLog.log('mictest', 'upload failed: $e');
      _toast('Upload failed');
    }
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: AppLog.text()));
    _toast('Logs copied to clipboard');
  }

  /// Upload this session's log to the lab share as a plain file (same PUT path as the mic-test clip),
  /// so it can be read on nukshare/the watcher without going through Maradel's chat.
  Future<void> _shareLogs() async {
    final name = 'keli-log-${DateTime.now().millisecondsSinceEpoch}.log';
    try {
      final res = await http
          .put(Uri.parse('$kShareBaseUrl/$name'), headers: const {'content-type': 'text/plain; charset=utf-8'}, body: AppLog.text())
          .timeout(const Duration(seconds: 30));
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      AppLog.log('logs', ok ? 'shared logs → share/$name' : 'share failed: HTTP ${res.statusCode}');
      _toast(ok ? 'Logs shared: $name' : 'Share failed (${res.statusCode})');
    } catch (e) {
      AppLog.log('logs', 'share failed: $e');
      _toast('Share failed');
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final hasClip = _clipPath != null && _clipBytes > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: KeliTheme.surface,
      child: Row(
        children: [
          // Hold-to-record. Use a raw Listener (not GestureDetector tap callbacks): a tap can be
          // cancelled by the gesture arena mid-hold (slop/scroll competition), which cut recordings
          // short (~2 s on some devices). Pointer events fire for the exact press duration.
          Listener(
            onPointerDown: (_) => _startHold(),
            onPointerUp: (_) => _stopHold(),
            onPointerCancel: (_) => _stopHold(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _recording ? KeliTheme.danger : KeliTheme.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _recording ? KeliTheme.danger : KeliTheme.accent.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_recording ? Icons.fiber_manual_record : Icons.mic, size: 16, color: _recording ? Colors.white : KeliTheme.accent),
                  const SizedBox(width: 6),
                  Text(_recording ? 'REC — release to stop' : 'Hold to record',
                      style: TextStyle(color: _recording ? Colors.white : KeliTheme.text, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _miniBtn(Icons.play_arrow, 'Play', hasClip ? _play : null),
          const SizedBox(width: 6),
          _miniBtn(Icons.send, 'Send', hasClip ? _send : null),
          if (hasClip) ...[
            const SizedBox(width: 8),
            Text('$_clipBytes B', style: const TextStyle(color: KeliTheme.muted, fontSize: 11)),
          ],
          const Spacer(),
          _miniBtn(Icons.copy, 'Copy logs', _copyLogs),
          const SizedBox(width: 6),
          _miniBtn(Icons.ios_share, 'Share logs', _shareLogs),
        ],
      ),
    );
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback? onTap) {
    final enabled = onTap != null;
    final color = enabled ? KeliTheme.accent : KeliTheme.muted;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
