import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_log.dart';
import '../config.dart';
import '../theme.dart';
import 'unity_bridge.dart';

/// Syncs the tablet to Maradel's **active persona** (see KELI_PERSONA_SKIN_HANDOFF.md):
///  - on boot AND on every `persona:changed` (Maradel `:9100` socket) → `GET /persona/active`;
///  - **recolor**: copy the persona's `keliColors` into the live [KeliTheme] palette (UI repaints);
///  - **avatar**: if the persona's `skin` is set and differs from the current one, apply it to Unity;
///  - when the **user** picks a skin on the tablet, `POST /persona/skin` so it sticks to the persona.
///
/// Uses its own light `:9100` socket (listening only to `persona:changed`) to stay decoupled from the
/// voice client. Endpoints live on Maradel (`kMaradelUrl`, :9100), per the handoff.
class Persona extends ChangeNotifier {
  io.Socket? _socket;
  UnityBridge? _bridge;
  String _id = '';
  String _name = '';
  String _skin = '';

  String get id => _id;
  String get name => _name;
  String get skin => _skin;

  /// Wire the Unity bridge (idempotent). On first attach, connect + do the initial load.
  void attach(UnityBridge bridge) {
    final first = _bridge == null;
    _bridge = bridge;
    bridge.onUserPickedSkin = _bindSkinToPersona; // user picks a skin → bind it to the active persona
    if (first) _connect();
  }

  void _connect() {
    _socket = io.io(
      kMaradelUrl,
      io.OptionBuilder().setTransports(['websocket']).enableReconnection().setReconnectionDelay(1000).build(),
    );
    _socket!.onConnect((_) {
      AppLog.log('persona', 'connected to Maradel (:9100)');
      _load(); // sync on (re)connect
    });
    _socket!.on('persona:changed', (_) {
      AppLog.log('persona', 'persona:changed → reloading');
      _load();
    });
    _socket!.connect();
    _load(); // also try immediately over REST (don't wait for the socket)
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$kMaradelUrl/persona/active')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body);
      final p = (j is Map) ? j['persona'] : null;
      if (p is! Map) return;
      _id = '${p['id'] ?? ''}';
      _name = '${p['name'] ?? ''}';

      // recolor the live palette from keliColors (defensive: missing/partial map just keeps defaults)
      final colors = p['keliColors'];
      if (colors is Map) KeliTheme.applyKeliColors(Map<String, dynamic>.from(colors));

      // set the avatar — "" means leave the current one; only switch if it actually differs
      final skin = '${p['skin'] ?? ''}'.trim();
      _skin = skin;
      if (skin.isNotEmpty && _bridge != null && _bridge!.currentSkin?.real != skin) {
        _bridge!.applySkinExternally(skin);
      }

      AppLog.log('persona',
          'active "$_name" ($_id) skin="${skin.isEmpty ? "(keep)" : skin}" colors=${colors is Map ? colors.length : 0}');
      notifyListeners();
    } catch (e) {
      AppLog.log('persona', 'load failed: $e');
    }
  }

  Future<void> _bindSkinToPersona(String real) async {
    try {
      await http
          .post(
            Uri.parse('$kMaradelUrl/persona/skin'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'skin': real}),
          )
          .timeout(const Duration(seconds: 10));
      _skin = real;
      AppLog.log('persona', 'bound skin "$real" to active persona');
    } catch (e) {
      AppLog.log('persona', 'bind skin failed: $e');
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}
