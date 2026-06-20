import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_log.dart';
import '../capabilities/registry.dart';
import '../config.dart';
import '../models/incoming_command.dart';

/// The one Socket.IO connection to the Keli backend.
///
/// Handles two streams of work, both deduped by id and acked on receipt:
///  - **push** windows (`show_text`, `show_image`) — persisted + restored across restarts;
///  - **interactive requests** (`input_string`, `take_photo`) — presented **one at a time** (a serial
///    queue, since "operations are queued"); each returns a `result` to the awaiting machine.
class KeliConnection extends ChangeNotifier {
  static const _storeKey = 'keli.windows';
  static const _deviceKey = 'keli.deviceId';

  late final io.Socket _socket;

  String _deviceId = 'roomba-phone';
  bool _connected = false;
  String _detail = 'connecting…';
  double? _pendingVolume; // last `set_volume` command value (consumed by KeliSettings via the proxy)
  double? get pendingVolume => _pendingVolume;
  final List<IncomingCommand> _commands = []; // push windows, newest first
  final List<IncomingCommand> _requests = []; // interactive requests, FIFO (active = first)

  bool get connected => _connected;
  String get detail => _detail;
  String get url => kKeliUrl;
  String get deviceId => _deviceId;

  Future<void> setDeviceId(String id) async {
    _deviceId = id.trim().isEmpty ? 'a-phone' : id.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_deviceKey, _deviceId);
  }

  /// User-initiated send to Maradel (via the Keli backend → /ingest). `attachments` are
  /// [{kind:'image'|'file', mime, data(base64), name?}]. Returns true on a 2xx.
  /// File a feature request from the phone → Keli backend → Maradel.
  Future<bool> requestFeature(String text) async {
    try {
      final res = await http
          .post(
            Uri.parse('$kKeliUrl/feature-request'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// File a user-initiated bug report (reason + this app's session log) → Keli backend → Maradel.
  Future<bool> reportBug(String reason) async {
    try {
      final res = await http
          .post(
            Uri.parse('$kKeliUrl/bug-report'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'reason': reason, 'appLogs': AppLog.text()}),
          )
          .timeout(const Duration(seconds: 30));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendToMaradel({String? text, List<Map<String, dynamic>>? attachments}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$kKeliUrl/send'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'deviceId': _deviceId, if (text != null) 'text': text, if (attachments != null) 'attachments': attachments}),
          )
          .timeout(const Duration(seconds: 20));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
  List<IncomingCommand> get commands => List.unmodifiable(_commands);

  /// The interactive request currently being presented (null if none). Serial — one at a time.
  IncomingCommand? get activeRequest => _requests.isEmpty ? null : _requests.first;

  KeliConnection() {
    _restore();
    _socket = io.io(
      kKeliUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .build(),
    );

    _socket.onConnect((_) {
      AppLog.log('conn', 'connected');
      _connected = true;
      _detail = 'connected';
      notifyListeners();
    });
    _socket.onDisconnect((r) {
      AppLog.log('conn', 'disconnected: $r');
      _connected = false;
      _detail = 'disconnected — retrying';
      notifyListeners();
    });
    _socket.onConnectError((e) {
      AppLog.log('conn', 'connect error: $e');
      _connected = false;
      _detail = 'connect error — retrying';
      notifyListeners();
    });

    for (final event in pushEvents()) {
      _socket.on(event, (data) => _onPush(event, data));
    }
    for (final event in requestEvents()) {
      _socket.on(event, (data) => _onRequest(event, data));
    }

    // Master-volume command (Maradel → set this Keli's volume). Applied by KeliSettings (which also
    // writes keli_config.json for the embedded Unity).
    _socket.on('set_volume', (data) {
      final raw = data is Map ? (data['volume'] ?? data['value']) : data;
      final v = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (v == null) return;
      _pendingVolume = v;
      AppLog.log('conn', 'set_volume → $v');
      notifyListeners();
    });

    _socket.connect();
  }

  // ── push windows ──
  void _onPush(String event, dynamic data) {
    final cmd = IncomingCommand.from(event, data);
    _socket.emit('ack', {'id': cmd.id}); // ack every delivery (incl. replays) so the queue can drop it
    if (_commands.any((c) => c.id == cmd.id)) return; // dedup
    _commands.insert(0, cmd);
    _persist();
    notifyListeners();
  }

  // ── interactive requests ──
  void _onRequest(String event, dynamic data) {
    final cmd = IncomingCommand.from(event, data);
    _socket.emit('ack', {'id': cmd.id});
    if (_requests.any((c) => c.id == cmd.id)) return; // dedup (replay of one already queued)
    _requests.add(cmd); // FIFO — presented in arrival order, one at a time
    notifyListeners();
  }

  /// A request view finished — send the result to the machine and advance the queue.
  void completeRequest(String reqId, {required bool ok, Map<String, dynamic>? data, String? reason}) {
    _socket.emit('result', {'reqId': reqId, 'ok': ok, 'data': data, 'reason': reason});
    _requests.removeWhere((c) => c.id == reqId);
    notifyListeners();
  }

  // ── persistence of push windows ──
  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dev = prefs.getString(_deviceKey);
      if (dev != null && dev.isNotEmpty) {
        _deviceId = dev;
        notifyListeners();
      }
      final raw = prefs.getString(_storeKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final restored = list.map(IncomingCommand.fromJson).toList();
      final seen = _commands.map((c) => c.id).toSet();
      _commands.addAll(restored.where((c) => seen.add(c.id)));
      _commands.sort((a, b) => b.ts.compareTo(a.ts));
      notifyListeners();
    } catch (_) {
      /* nothing persisted / unreadable */
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storeKey, jsonEncode(_commands.map((c) => c.toJson()).toList()));
    } catch (_) {
      /* best-effort */
    }
  }

  void dismiss(String id) {
    _commands.removeWhere((c) => c.id == id);
    _persist();
    notifyListeners();
  }

  void dismissAll() {
    _commands.clear();
    _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    _socket.dispose();
    super.dispose();
  }
}
