import 'package:flutter/material.dart';

import '../face/unity_face_bridge.dart';
import '../theme.dart';

/// **Face** — Maradel's 3D lipsync face (LIPSYNC.md). PRE-UNITY phase: this hosts a live placeholder
/// that proves the Flutter half works — it opens the Maradel voice socket through [UnityFaceBridge]
/// and reacts to real `voice:chunk` / `voice:speaking` events (the sigil pulses when she speaks,
/// chunks are counted as they'd be forwarded to Unity).
///
/// WHEN THE UNITY PROJECT LANDS (drop-in, per LIPSYNC.md §6):
///   1. add `flutter_embed_unity` to pubspec,
///   2. replace `LoggingUnitySink` with an `EmbedUnitySink` wrapping `sendToUnity` + the onMessage cb,
///   3. swap the `_Placeholder` below for the `EmbedUnity` widget.
/// Nothing else changes — the bridge/protocol/voice wiring already speaks the Unity contract.
class FaceScreen extends StatefulWidget {
  const FaceScreen({super.key});

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen> {
  late final UnityFaceBridge _bridge = UnityFaceBridge(sink: LoggingUnitySink());

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KeliTheme.bg,
      appBar: AppBar(
        backgroundColor: KeliTheme.surface,
        title: const Text('Face', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: DecoratedBox(decoration: KeliTheme.backdrop)),
          ListenableBuilder(
            listenable: _bridge,
            builder: (context, _) => _Placeholder(bridge: _bridge),
          ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.bridge});
  final UnityFaceBridge bridge;

  @override
  Widget build(BuildContext context) {
    final speaking = bridge.speaking;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Stand-in for the Unity face: the sigil, glowing brighter while speech is flowing.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: KeliTheme.glow(blur: speaking ? 60 : 30, alpha: speaking ? 0.6 : 0.3),
            ),
            child: Image.asset('assets/icon/maradel_icon.png', width: 150, height: 150),
          ),
          const SizedBox(height: 28),
          Text(
            speaking ? 'speaking…' : 'idle',
            style: TextStyle(
              color: speaking ? KeliTheme.accent : KeliTheme.muted,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 24),
          _row('Maradel voice link', bridge.voiceConnected ? 'connected' : 'connecting…', bridge.voiceConnected),
          _row('Unity face', bridge.faceReady ? 'ready' : 'awaiting Unity project', bridge.faceReady),
          _row('chunks forwarded', '${bridge.chunksSent}', bridge.chunksSent > 0),
          if (bridge.lastError != null) _row('last error', bridge.lastError!, false),
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 36),
            child: Text(
              'The 3D Unity face mounts here. The bridge is already live — it forwards Maradel\'s '
              'voice:chunk → playChunk and tracks speaking state. Have Maradel talk and watch it react.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KeliTheme.muted, fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                size: 15, color: ok ? KeliTheme.accent : KeliTheme.muted),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(color: KeliTheme.muted, fontSize: 13)),
            Text(value, style: const TextStyle(color: KeliTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
