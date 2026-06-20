import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app_log.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'services/keli_connection.dart';
import 'services/keli_settings.dart';
import 'services/maradel_session.dart';
import 'services/mic_streamer.dart';
import 'services/unity_bridge.dart';
import 'services/voice_player.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppLog.init(kAppVersion);
  // Keli is a landscape device tool (runs on a big wall-mounted Android tablet). Lock to landscape
  // both ways so it stays horizontal however the tablet is set down.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const KeliApp());
}

class KeliApp extends StatelessWidget {
  const KeliApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => KeliConnection()),
        // Per-Keli identity/config (registration, 60s config poll, 10s log batching, master volume).
        // Proxied on KeliConnection so a `set_volume` command is applied immediately.
        ChangeNotifierProxyProvider<KeliConnection, KeliSettings>(
          create: (_) => KeliSettings(),
          update: (_, conn, s) => (s ?? KeliSettings())..onVolumeCommand(conn.pendingVolume),
        ),
        // Flutter↔Unity bridge (skin list + set_skin + avatar index). init() restores the persisted
        // avatar and asks Unity for the skin list at startup.
        ChangeNotifierProvider(create: (_) => UnityBridge()..init()),
        // Read-only mirror of the live Maradel session (floating chat window). Binds to the SAME
        // backend socket as KeliConnection and pulls GET /session for the initial load.
        ChangeNotifierProxyProvider<KeliConnection, MaradelSession>(
          create: (_) => MaradelSession(),
          update: (_, conn, s) => (s ?? MaradelSession())..bind(conn.socket),
        ),
        // The robot's "mouth": plays Maradel's reply on the tablet (:9100 voice:chunk) and exposes
        // the real `voice:speaking` flag. Master volume comes from the per-Keli config.
        ChangeNotifierProxyProvider<KeliSettings, VoicePlayer>(
          create: (_) => VoicePlayer(),
          update: (_, settings, vp) => (vp ?? VoicePlayer())..setVolume(settings.volume),
        ),
        // The robot's "ears": captures the mic and streams it continuously to Maradel while on.
        // Muted while Maradel's voice actually occupies the speaker (VoicePlayer.busy = voice:speaking
        // OR audio still playing/queued) — not just voice:speaking — so the reply tail can't re-trigger.
        ChangeNotifierProxyProvider<VoicePlayer, MicStreamer>(
          create: (_) => MicStreamer(),
          update: (_, voice, mic) => (mic ?? MicStreamer())..setSpeaking(voice.busy),
        ),
      ],
      child: MaterialApp(
        title: 'Keli',
        debugShowCheckedModeBanner: false,
        theme: KeliTheme.dark(),
        home: const HomeScreen(),
      ),
    );
  }
}
