import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dynamic_views.dart';
import '../theme.dart';

/// The "Widgets" dashboard — the control centre for the dynamic views. Lists every view with its
/// current placement and lets you Pin it (centerpiece, one at a time), Float it (draggable window),
/// or Close it (parked here). This is also where closed views live, ready to re-open.
Future<void> showWidgetsDashboard(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: KeliTheme.surface,
    isScrollControlled: true,
    builder: (_) => const _Dashboard(),
  );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Consumer<DynamicViewController>(
        builder: (_, views, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.dashboard_customize_outlined, color: KeliTheme.accent, size: 20),
                  const SizedBox(width: 8),
                  Text('Widgets',
                      style: TextStyle(color: KeliTheme.text, fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Pin one to the centre, float the rest, or close what you don\'t need.',
                  style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
              const SizedBox(height: 14),
              for (final id in ViewIds.all) _ViewRow(id: id, mode: views.modeOf(id)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({required this.id, required this.mode});
  final String id;
  final ViewMode mode;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<DynamicViewController>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: KeliTheme.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: KeliTheme.edge),
      ),
      child: Row(
        children: [
          Icon(ViewIds.icon(id), color: KeliTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(ViewIds.title(id),
                style: TextStyle(color: KeliTheme.text, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
          ),
          _ModeChip(icon: Icons.push_pin, label: 'Pin', on: mode == ViewMode.pinned, onTap: () => ctrl.pin(id)),
          const SizedBox(width: 6),
          _ModeChip(icon: Icons.picture_in_picture_alt, label: 'Float', on: mode == ViewMode.floating, onTap: () => ctrl.float(id)),
          const SizedBox(width: 6),
          _ModeChip(icon: Icons.close, label: 'Close', on: mode == ViewMode.closed, onTap: () => ctrl.close(id)),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? KeliTheme.accent : KeliTheme.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: on ? KeliTheme.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: on ? KeliTheme.accent.withValues(alpha: 0.6) : KeliTheme.edge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
