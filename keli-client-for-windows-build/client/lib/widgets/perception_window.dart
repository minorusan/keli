import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/keli_connection.dart';
import '../theme.dart';
import 'draggable_window.dart';

/// Floating panel showing Maradel's latest ambient perception — what she sees on each camera, whether
/// a person is present, and her best guess of the roomba's location. Fed by the `perception` socket
/// event (pushed every ~5 min by the backend's vision loop). Anchored top-right; present every session.
class PerceptionWindow extends StatelessWidget {
  const PerceptionWindow({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<KeliConnection>().perception;
    return DraggableWindow(
      title: 'MARADEL SEES',
      icon: Icons.remove_red_eye_outlined,
      corner: WindowCorner.topRight,
      width: 300,
      height: 210,
      child: p == null
          ? const Center(
              child: Text('waiting for perception…', style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
            )
          : _Body(p),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.p);
  final Map<String, dynamic> p;

  static String _text(Object? m) {
    if (m is! Map) return '—';
    final t = (m['text'] as String?) ?? '';
    return t.isEmpty ? '—' : t;
  }

  @override
  Widget build(BuildContext context) {
    final loc = (p['location'] as String?) ?? 'unknown';
    final present = p['present'] == true;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 15, color: KeliTheme.accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text(loc,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: KeliTheme.text, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Icon(present ? Icons.person : Icons.person_off, size: 15, color: present ? KeliTheme.accent : KeliTheme.muted),
              const SizedBox(width: 3),
              Text(present ? 'person' : 'empty',
                  style: TextStyle(color: present ? KeliTheme.accent : KeliTheme.muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line('TAPO', _text(p['tapo'])),
                  const SizedBox(height: 6),
                  _line('USB', _text(p['usb'])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(String label, String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: KeliTheme.muted, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
          Text(text, style: const TextStyle(color: KeliTheme.text, fontSize: 12, height: 1.3)),
        ],
      );
}
