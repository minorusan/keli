import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/keli_connection.dart';
import '../theme.dart';

/// The reminders Maradel is tracking (synced from the backend, soonest first). Upcoming ones show a
/// countdown; fired ones are dimmed. Read-only — Maradel owns the list (set them by asking her).
class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final items = context.watch<KeliConnection>().reminders;
    return Scaffold(
      backgroundColor: KeliTheme.bg,
      appBar: AppBar(
        backgroundColor: KeliTheme.surface,
        title: Text('Reminders', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
      ),
      body: items.isEmpty
          ? Center(
              child: Text('no reminders — ask Maradel to "remind me to…"',
                  style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
            )
          : ListView.separated(
              padding: EdgeInsets.all(12),
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(height: 8),
              itemBuilder: (_, i) => _Tile(r: items[i]),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.r});
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final fired = r['fired'] == true;
    final fireAt = (r['fireAt'] as num?)?.toInt() ?? 0;
    final when = DateTime.fromMillisecondsSinceEpoch(fireAt);
    final text = '${r['text'] ?? ''}';
    return Material(
      color: KeliTheme.surface,
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: KeliTheme.surface2),
        ),
        leading: Icon(fired ? Icons.notifications_off_outlined : Icons.alarm,
            color: fired ? KeliTheme.muted : KeliTheme.accent),
        title: Text(text,
            style: TextStyle(
                color: fired ? KeliTheme.muted : KeliTheme.text,
                fontSize: 14,
                decoration: fired ? TextDecoration.lineThrough : null)),
        subtitle: Text(fired ? 'fired · ${_fmt(when)}' : '${_fmt(when)} · ${_countdown(when)}',
            style: TextStyle(color: KeliTheme.muted, fontSize: 11.5)),
      ),
    );
  }

  String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _countdown(DateTime when) {
    final diff = when.difference(DateTime.now());
    if (diff.isNegative) return 'due';
    if (diff.inMinutes < 1) return 'in <1 min';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'in ${diff.inDays}d';
  }
}
