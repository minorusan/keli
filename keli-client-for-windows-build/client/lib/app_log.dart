import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Verbose, session-based, file-backed app log (one session = one launch). Bug reports send [text]
/// so the backend attaches the phone app's own logs. Keep it chatty — connection, commands, errors.
class AppLog {
  static const int _cap = 4000;
  static final List<String> _buf = [];
  static IOSink? _sink;

  /// Bumped on every [log] so the UI (e.g. the status bar) can refresh reactively.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// The most recent line ('' if none yet).
  static String get last => _buf.isEmpty ? '' : _buf.last;

  /// The newest [n] lines, oldest first.
  static List<String> tail([int n = 200]) =>
      _buf.length <= n ? List.unmodifiable(_buf) : _buf.sublist(_buf.length - n);

  /// Total number of lines ever logged this session (monotonic cursor for batch shipping).
  static int get count => revision.value;

  /// Lines logged since the caller last shipped [sentCount] of them (capped by the ring buffer).
  static List<String> newLinesSince(int sentCount) {
    final total = revision.value;
    if (sentCount >= total) return const [];
    final missed = total - sentCount;
    final take = missed < _buf.length ? missed : _buf.length;
    return _buf.sublist(_buf.length - take);
  }

  static Future<void> init(String version) async {
    _buf.clear();
    log('app', 'session start · v$version');
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/keli-session.log');
      _sink = f.openWrite(mode: FileMode.write);
      _sink!.writeln(_buf.join('\n'));
    } catch (e) {
      log('app', 'file log unavailable: $e');
    }
  }

  static void log(String tag, String msg) {
    final line = '${DateTime.now().toIso8601String()} [$tag] $msg';
    _buf.add(line);
    if (_buf.length > _cap) _buf.removeRange(0, _buf.length - _cap);
    try {
      _sink?.writeln(line);
    } catch (_) {/* best-effort */}
    if (kDebugMode) debugPrint(line);
    revision.value++;
  }

  static String text() => _buf.join('\n');
}
