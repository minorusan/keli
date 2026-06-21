import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../config.dart';
import '../services/unity_bridge.dart';
import '../theme.dart';

/// Avatar/skin selector.
///
/// PRIMARY source: Maradel's avatar gallery (`GET $kMaradelUrl/avatars`) — a VISUAL grid of body
/// photos + names + descriptions (the same gallery the dashboard picks from). Each entry's `skin` is
/// the Unity "real" name, so a pick goes straight through the existing bridge:
/// `UnityBridge.setSkin(skin)` (→ `set_skin` to Unity + persisted + bound to the active persona).
///
/// FALLBACK: if the gallery is unreachable/empty, we fall back to the skins Unity itself reports
/// (`UnityBridge.skins`), shown as a plain searchable list — so picking still works offline.
Future<void> showSkinPicker(BuildContext context) {
  context.read<UnityBridge>().requestSkins(); // fallback list + current-selection highlight
  return showDialog<void>(context: context, builder: (_) => const _SkinPicker());
}

class _GalleryAvatar {
  final String name; // gallery id, e.g. Female_Adult_01
  final String skin; // Unity real name, e.g. Female_Adult_01_facial
  final String category;
  final String description;
  final String url; // absolute image URL
  const _GalleryAvatar({required this.name, required this.skin, required this.category, required this.description, required this.url});
}

class _SkinPicker extends StatefulWidget {
  const _SkinPicker();

  @override
  State<_SkinPicker> createState() => _SkinPickerState();
}

class _SkinPickerState extends State<_SkinPicker> {
  String _q = '';
  double _zoom = 1; // thumbnail scale (transient, not persisted)
  List<_GalleryAvatar>? _gallery; // null = still loading; empty = loaded-but-none
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery() async {
    try {
      final r = await http.get(Uri.parse('$kMaradelUrl/avatars')).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = ((jsonDecode(r.body) as Map)['avatars'] as List? ?? const [])
          .whereType<Map>()
          .map((a) => _GalleryAvatar(
                name: '${a['name'] ?? ''}',
                skin: '${a['skin'] ?? ''}',
                category: '${a['category'] ?? ''}',
                description: '${a['description'] ?? ''}',
                url: '$kMaradelUrl${a['avatarUrl'] ?? ''}',
              ))
          .where((a) => a.skin.isNotEmpty)
          .toList();
      if (mounted) setState(() => _gallery = list);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _pick(BuildContext context, String real) {
    context.read<UnityBridge>().setSkin(real); // → Unity + persisted + bound to active persona
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = context.watch<UnityBridge>();
    final current = bridge.currentSkin?.real;
    final h = MediaQuery.of(context).size.height;
    final insets = MediaQuery.of(context).viewInsets.bottom;
    final q = _q.trim().toLowerCase();

    return Dialog(
      backgroundColor: KeliTheme.surface,
      insetPadding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: h * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(child: Text('Select an avatar', style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16))),
                if (_gallery != null) ...[
                  IconButton(icon: Icon(Icons.zoom_out, color: KeliTheme.muted), onPressed: () => setState(() => _zoom = (_zoom - 0.2).clamp(0.6, 2.4).toDouble())),
                  IconButton(icon: Icon(Icons.zoom_in, color: KeliTheme.muted), onPressed: () => setState(() => _zoom = (_zoom + 0.2).clamp(0.6, 2.4).toDouble())),
                ],
                IconButton(icon: Icon(Icons.close, color: KeliTheme.muted), onPressed: () => Navigator.of(context).pop()),
              ]),
              const SizedBox(height: 6),
              TextField(
                autofocus: true,
                style: TextStyle(color: KeliTheme.text),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, color: KeliTheme.muted),
                  hintText: 'search by name, category, look…',
                  hintStyle: TextStyle(color: KeliTheme.muted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.surface2)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.accent)),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(child: _body(context, bridge, current, q)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, UnityBridge bridge, String? current, String q) {
    // Gallery still loading (and not yet failed) → spinner.
    if (_gallery == null && !_failed) {
      return _center(const _Spinner('loading avatars…'));
    }
    // Gallery loaded with entries → the visual grid.
    if (_gallery != null && _gallery!.isNotEmpty) {
      final shown = q.isEmpty
          ? _gallery!
          : _gallery!.where((a) => '${a.name} ${a.category} ${a.description}'.toLowerCase().contains(q)).toList();
      if (shown.isEmpty) return _center(Text('No avatars match "$_q".', style: TextStyle(color: KeliTheme.muted, fontSize: 12)));
      return GridView.builder(
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130 * _zoom, childAspectRatio: 0.62, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final a = shown[i];
          final on = current != null && current == a.skin;
          return InkWell(
            onTap: () => _pick(context, a.skin),
            child: Container(
              decoration: BoxDecoration(
                color: on ? KeliTheme.surface2 : KeliTheme.bg,
                border: Border.all(color: on ? KeliTheme.accent : KeliTheme.surface2, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(a.url, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: KeliTheme.muted),
                        loadingBuilder: (_, child, p) => p == null ? child : Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent)))),
                  ),
                ),
                const SizedBox(height: 4),
                Text(UnityBridge.humanize(a.name), maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: on ? KeliTheme.accent : KeliTheme.text, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(a.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: KeliTheme.muted, fontSize: 9.5)),
              ]),
            ),
          );
        },
      );
    }
    // Gallery failed or empty → fall back to the Unity-reported skin list (plain, still works offline).
    final all = bridge.skins;
    if (all.isEmpty) {
      return _center(Text(
        bridge.awaiting ? 'loading skins from the face…' : 'No avatars from Maradel, and no skins reported by Unity.',
        style: TextStyle(color: KeliTheme.muted, fontSize: 12), textAlign: TextAlign.center));
    }
    final shown = q.isEmpty ? all : all.where((s) => '${s.display} ${s.category} ${s.real}'.toLowerCase().contains(q)).toList();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final s = shown[i];
        return ListTile(
          dense: true,
          title: Text(s.display, style: TextStyle(color: KeliTheme.text, fontWeight: FontWeight.w600)),
          subtitle: Text('${s.category} · ${s.real}', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
          trailing: Icon(Icons.chevron_right, color: KeliTheme.muted, size: 18),
          onTap: () => _pick(context, s.real),
        );
      },
    );
  }

  Widget _center(Widget child) => Padding(padding: const EdgeInsets.all(28), child: Center(child: child));
}

class _Spinner extends StatelessWidget {
  final String label;
  const _Spinner(this.label);
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
      ]);
}
