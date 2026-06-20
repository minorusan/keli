import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../app_log.dart';
import '../config.dart';

/// Who produced a message in the read-only session view.
enum SessionRole { user, assistant, system }

SessionRole _roleFrom(String? s) => switch (s) {
      'user' => SessionRole.user,
      'system' => SessionRole.system,
      _ => SessionRole.assistant,
    };

/// One tool call under an assistant turn (name + input + live status/notes + collapsible output).
class ToolCall {
  final int id;
  final String name;
  final String input;
  final String status; // running | succeeded | failed
  final String notes; // progress narration (grows as it works)
  final String output;
  final int ts;
  const ToolCall({
    required this.id,
    required this.name,
    required this.input,
    required this.status,
    required this.notes,
    required this.output,
    required this.ts,
  });

  factory ToolCall.fromJson(Map j) => ToolCall(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: '${j['name'] ?? 'tool'}',
        input: '${j['input'] ?? ''}',
        status: '${j['status'] ?? 'running'}',
        notes: '${j['notes'] ?? ''}',
        output: '${j['output'] ?? ''}',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );
}

/// One message in the transcript (user/assistant/system) with any tool calls under it.
class SessionMessage {
  final int id;
  final SessionRole role;
  final String content;
  final int ts;
  final List<ToolCall> tools;
  const SessionMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.ts,
    required this.tools,
  });

  factory SessionMessage.fromJson(Map j) => SessionMessage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        role: _roleFrom(j['role'] as String?),
        content: '${j['content'] ?? ''}',
        ts: (j['ts'] as num?)?.toInt() ?? 0,
        tools: ((j['tools'] as List?) ?? const [])
            .whereType<Map>()
            .map(ToolCall.fromJson)
            .toList(),
      );
}

/// Read-only mirror of the current Maradel session — what we say, what Maradel says, and her tool
/// calls in between — shown in the floating chat window. Consumes the Keli backend contract:
///   • `GET /session` (:9120) for the initial load / re-sync, and
///   • `session:reset|message|tool|token` on the EXISTING backend socket (passed via [bind]).
/// Strictly read-only — sending stays on the FAB → `/send` path.
class MaradelSession extends ChangeNotifier {
  final List<SessionMessage> _messages = [];
  // Tools for the in-progress assistant turn that arrive BEFORE its final `session:message`.
  final List<ToolCall> _pendingTools = [];
  String? _sessionId;
  String? _title;
  bool _bound = false;

  List<SessionMessage> get messages => List.unmodifiable(_messages);
  List<ToolCall> get pendingTools => List.unmodifiable(_pendingTools);
  String? get title => _title;
  bool get isEmpty => _messages.isEmpty && _pendingTools.isEmpty;

  /// Attach to the shared backend socket (idempotent) and do the initial load. Re-syncs on every
  /// (re)connect so the view recovers after a drop.
  void bind(io.Socket socket) {
    if (_bound) return;
    _bound = true;
    socket.on('session:reset', _onReset);
    socket.on('session:message', _onMessage);
    socket.on('session:tool', _onTool);
    socket.on('session:token', _onToken); // optional live typing — safe to ignore
    socket.on('connect', (_) => _load()); // resync after a reconnect
    _load();
  }

  bool _forCurrent(dynamic data) {
    if (data is! Map) return false;
    final sid = data['sessionId'] as String?;
    // Accept if we don't yet know the session, else drop stale turns from a previous one.
    return _sessionId == null || sid == null || sid == _sessionId;
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('$kKeliUrl/session')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return;
      final j = jsonDecode(res.body);
      if (j is! Map || j['ok'] != true) return;
      _sessionId = j['sessionId'] as String?;
      _title = j['title'] as String?;
      _messages
        ..clear()
        ..addAll(((j['messages'] as List?) ?? const []).whereType<Map>().map(SessionMessage.fromJson));
      _pendingTools.clear();
      AppLog.log('session', 'loaded ${_messages.length} messages (session $_sessionId)');
      notifyListeners();
    } catch (e) {
      AppLog.log('session', 'load failed: $e');
    }
  }

  void _onReset(dynamic data) {
    if (data is! Map) return;
    _sessionId = data['sessionId'] as String?;
    _title = data['title'] as String?;
    _messages.clear();
    _pendingTools.clear();
    notifyListeners();
    _load(); // pull the fresh session's history
  }

  void _onMessage(dynamic data) {
    if (!_forCurrent(data) || data is! Map) return;
    final m = data['message'];
    if (m is! Map) return;
    final msg = SessionMessage.fromJson(m);
    // Attach any tools that streamed in before this turn's final message.
    final merged = msg.role == SessionRole.assistant && _pendingTools.isNotEmpty
        ? SessionMessage(id: msg.id, role: msg.role, content: msg.content, ts: msg.ts, tools: [..._pendingTools, ...msg.tools])
        : msg;
    if (msg.role == SessionRole.assistant) _pendingTools.clear();
    final i = _messages.indexWhere((e) => e.id == merged.id);
    if (i >= 0) {
      _messages[i] = merged; // upsert (final text replaces a draft of the same id)
    } else {
      _messages.add(merged);
    }
    notifyListeners();
  }

  void _onTool(dynamic data) {
    if (!_forCurrent(data) || data is! Map) return;
    final t = data['tool'];
    if (t is! Map) return;
    final tool = ToolCall.fromJson(t);
    // Update in place if this tool id already lives under a finalized message…
    for (var mi = 0; mi < _messages.length; mi++) {
      final ti = _messages[mi].tools.indexWhere((x) => x.id == tool.id);
      if (ti >= 0) {
        final tools = [..._messages[mi].tools]..[ti] = tool;
        final mm = _messages[mi];
        _messages[mi] = SessionMessage(id: mm.id, role: mm.role, content: mm.content, ts: mm.ts, tools: tools);
        notifyListeners();
        return;
      }
    }
    // …otherwise it belongs to the in-progress turn → upsert into pending.
    final pi = _pendingTools.indexWhere((x) => x.id == tool.id);
    if (pi >= 0) {
      _pendingTools[pi] = tool;
    } else {
      _pendingTools.add(tool);
    }
    notifyListeners();
  }

  // Optional live-typing stream. The final text always arrives via `session:message`, so this is
  // safe to ignore for now; the hook is here for a future draft-bubble.
  void _onToken(dynamic data) {}
}
