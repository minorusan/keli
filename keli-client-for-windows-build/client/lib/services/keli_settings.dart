import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_log.dart';
import '../config.dart';

/// Per-Keli identity, config and log shipping (see configs_handoff.md). Talks to the Maradel backend
/// on :9100:
///   - `POST /keli/register`         once (first launch / device-swap) -> persisted [guid]
///   - `GET  /keli/<guid>/config`    polled every 60 s -> cached to [configPath], exposes [volume]
///   - `POST /keli/<guid>/logs`      batched flush every 10 s (Maradel prunes >2-day logs itself)
///
/// The config file is written to the app's external files dir, which on Android is the SAME directory
/// as Unity's `Application.persistentDataPath` (both = /storage/emulated/0/Android/data/<pkg>/files),
/// so the embedded Unity face reads the same `keli_config.json` for its own volume.
class KeliSettings extends ChangeNotifier {
  static const _guidKey = 'keli.guid';
  static const _loginKey = 'keli.login';
  static const _nameKey = 'keli.instanceName';
  static const _descKey = 'keli.instanceDesc';
  static const configFileName = 'keli_config.json';

  String? _guid;
  String _name = '';
  String _desc = '';
  String _login = '';
  double _volume = 1.0;
  String? _configPath;
  bool _ready = false;
  int _sentLogCount = 0;
  Timer? _configTimer;
  Timer? _logTimer;

  String? get guid => _guid;
  bool get registered => _guid != null;
  bool get ready => _ready; // prefs loaded — safe to decide whether to show the popup
  double get volume => _volume;
  String get instanceName => _name;
  String get instanceDesc => _desc;
  String get login => _login;
  String? get configPath => _configPath;

  KeliSettings() {
    _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _guid = prefs.getString(_guidKey);
      _name = prefs.getString(_nameKey) ?? '';
      _desc = prefs.getString(_descKey) ?? '';
      _login = prefs.getString(_loginKey) ?? '';
      _configPath = await _resolveConfigPath();
      if (_guid != null) _start();
    } catch (e) {
      AppLog.log('keli', 'settings init failed: $e');
    }
    _ready = true;
    notifyListeners();
  }

  Future<String> _resolveConfigPath() async {
    Directory? dir;
    try {
      dir = await getExternalStorageDirectory(); // app external files dir (== Unity persistentDataPath)
    } catch (_) {}
    dir ??= await getApplicationSupportDirectory();
    return '${dir.path}/$configFileName';
  }

  /// Register the instance (first launch or device-swap). Returns null on success, else an error.
  Future<String?> register({
    required String name,
    required String description,
    required String login,
    required String password,
  }) async {
    if (name.trim().isEmpty || login.trim().isEmpty || password.isEmpty) {
      return 'Name, login and password are required';
    }
    try {
      final res = await http
          .post(
            Uri.parse('$kMaradelUrl/keli/register'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'name': name.trim(),
              'description': description.trim(),
              'login': login.trim(),
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 401) return 'Wrong password for this login';
      if (res.statusCode != 200) return 'Registration failed (HTTP ${res.statusCode})';

      final j = jsonDecode(res.body) as Map<String, dynamic>;
      _guid = '${j['guid']}';
      _name = name.trim();
      _desc = description.trim();
      _login = login.trim();
      if (j['config'] is Map) _applyConfig(Map<String, dynamic>.from(j['config'] as Map), cacheBody: jsonEncode(j['config']));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_guidKey, _guid!);
      await prefs.setString(_loginKey, _login);
      await prefs.setString(_nameKey, _name);
      await prefs.setString(_descKey, _desc);

      AppLog.log('keli', 'registered guid=$_guid isNew=${j['isNew']}');
      _sentLogCount = AppLog.count; // don't backfill the whole session on first flush
      _start();
      notifyListeners();
      return null;
    } catch (e) {
      return 'Registration error: $e';
    }
  }

  void _start() {
    _configTimer?.cancel();
    _logTimer?.cancel();
    unawaited(_pollConfig()); // immediate
    _configTimer = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_pollConfig()));
    _logTimer = Timer.periodic(const Duration(seconds: 10), (_) => unawaited(_flushLogs()));
  }

  Future<void> _pollConfig() async {
    final g = _guid;
    if (g == null) return;
    try {
      final res = await http.get(Uri.parse('$kMaradelUrl/keli/$g/config')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      _applyConfig(jsonDecode(res.body) as Map<String, dynamic>, cacheBody: res.body);
    } catch (_) {
      /* offline — keep the last cached config */
    }
  }

  void _applyConfig(Map<String, dynamic> j, {String? cacheBody}) {
    final v = (j['volume'] as num?)?.toDouble();
    if (v != null) {
      final clamped = v.clamp(0.0, 1.0);
      if (clamped != _volume) {
        _volume = clamped;
        AppLog.log('keli', 'volume -> $_volume');
        notifyListeners();
      }
    }
    // Cache to the shared file (Flutter applies above; Unity reads the same file).
    final p = _configPath;
    if (p != null && cacheBody != null) {
      File(p).writeAsString(cacheBody, flush: true).catchError((e) {
        AppLog.log('keli', 'config cache write failed: $e');
        return File(p);
      });
    }
  }

  Future<void> _flushLogs() async {
    final g = _guid;
    if (g == null) return;
    final lines = AppLog.newLinesSince(_sentLogCount);
    if (lines.isEmpty) return;
    final upto = AppLog.count;
    try {
      final res = await http
          .post(
            Uri.parse('$kMaradelUrl/keli/$g/logs'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({'lines': lines}),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) _sentLogCount = upto;
    } catch (_) {
      /* keep the cursor; retry next tick */
    }
  }

  /// Manual "Upload logs": PUT the full session log as a browsable file to the egregor share, under
  /// `keli/logs/` (same folder the Unity side uses). Returns null on success, else an error.
  Future<String?> uploadLogsToShare() async {
    final who = (_name.isNotEmpty ? _name : (_guid ?? 'keli')).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final ts = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final rel = 'keli/logs/$who-flutter-$ts.log';
    try {
      final res = await http
          .put(Uri.parse('$kShareBaseUrl/$rel'), headers: const {'content-type': 'text/plain'}, body: AppLog.text())
          .timeout(const Duration(seconds: 30));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        AppLog.log('keli', 'uploaded logs -> share/$rel');
        return null;
      }
      return 'Upload failed (HTTP ${res.statusCode})';
    } catch (e) {
      return 'Upload error: $e';
    }
  }

  @override
  void dispose() {
    _configTimer?.cancel();
    _logTimer?.cancel();
    super.dispose();
  }
}
