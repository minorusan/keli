/// A generic command pushed from the backend over Socket.IO. Every capability
/// event carries the common envelope `{ id, ts, ...fields }`; the capability's
/// own fields live in [data] (e.g. show_text → data['text'], data['title']).
class IncomingCommand {
  final String event;
  final String id;
  final Map<String, dynamic> data;
  final int ts;

  const IncomingCommand({
    required this.event,
    required this.id,
    required this.data,
    required this.ts,
  });

  factory IncomingCommand.from(String event, dynamic raw) {
    final m = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return IncomingCommand(
      event: event,
      id: '${m['id'] ?? DateTime.now().microsecondsSinceEpoch}',
      data: m,
      ts: (m['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// For persisting the open windows across app restarts.
  Map<String, dynamic> toJson() => {'event': event, 'id': id, 'data': data, 'ts': ts};

  factory IncomingCommand.fromJson(Map<String, dynamic> j) => IncomingCommand(
        event: '${j['event'] ?? ''}',
        id: '${j['id'] ?? ''}',
        data: j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : <String, dynamic>{},
        ts: (j['ts'] as num?)?.toInt() ?? 0,
      );

  /// Convenience string accessor for a payload field.
  String str(String key) => data[key] is String ? data[key] as String : '';
}
