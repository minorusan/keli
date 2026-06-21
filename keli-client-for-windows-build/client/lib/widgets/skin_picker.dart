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

  /// Gender derived from the name (Rocketbox encodes it). NB: "female" CONTAINS "male", so test female
  /// first. Returns 'female' | 'male' | '' (unknown).
  String get gender {
    final n = name.toLowerCase();
    if (n.contains('female')) return 'female';
    if (n.contains('male')) return 'male';
    return '';
  }
}

class _SkinPicker extends StatefulWidget {
  const _SkinPicker();

  @override
  State<_SkinPicker> createState() => _SkinPickerState();
}

class _SkinPickerState extends State<_SkinPicker> {
  String _q = '';
  double _zoom = 1; // thumbnail scale (transient, not persisted)
  String? _cat; // category filter (null = all)
  String? _gender; // gender filter: 'female' | 'male' | null (all)
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

  // ── filtering ──
  List<_GalleryAvatar> _applyFilters(List<_GalleryAvatar> all) {
    final q = _q.trim().toLowerCase();
    return all.where((a) {
      if (_cat != null && a.category != _cat) return false;
      if (_gender != null && a.gender != _gender) return false;
      if (q.isNotEmpty && !'${a.name} ${a.category} ${a.description}'.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  /// Ordered category list (with counts) for the filter chips, biggest first.
  List<MapEntry<String, int>> _categories(List<_GalleryAvatar> all) {
    final counts = <String, int>{};
    for (final a in all) {
      if (a.category.isEmpty) continue;
      counts[a.category] = (counts[a.category] ?? 0) + 1;
    }
    final entries = counts.entries.toList()..sort((x, y) => y.value.compareTo(x.value));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final bridge = context.watch<UnityBridge>();
    final current = bridge.currentSkin?.real;
    final h = MediaQuery.of(context).size.height;
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return Dialog(
      backgroundColor: KeliTheme.surface,
      insetPadding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720, maxHeight: h * 0.88),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _gallery != null && _gallery!.isNotEmpty
              ? _galleryView(context, current)
              : _loadingOrFallback(context, bridge, current),
        ),
      ),
    );
  }

  // ── the rich gallery view: search + category chips + gender toggle + grid ──
  Widget _galleryView(BuildContext context, String? current) {
    final all = _gallery!;
    final shown = _applyFilters(all);
    final cats = _categories(all);
    final hasBothGenders = all.any((a) => a.gender == 'female') && all.any((a) => a.gender == 'male');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text('Select a model · ${shown.length}/${all.length}',
                style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          IconButton(tooltip: 'Smaller', icon: Icon(Icons.zoom_out, color: KeliTheme.muted), onPressed: () => setState(() => _zoom = (_zoom - 0.2).clamp(0.6, 2.4).toDouble())),
          IconButton(tooltip: 'Bigger', icon: Icon(Icons.zoom_in, color: KeliTheme.muted), onPressed: () => setState(() => _zoom = (_zoom + 0.2).clamp(0.6, 2.4).toDouble())),
          IconButton(tooltip: 'Close', icon: Icon(Icons.close, color: KeliTheme.muted), onPressed: () => Navigator.of(context).pop()),
        ]),
        const SizedBox(height: 6),
        // search
        TextField(
          autofocus: true,
          style: TextStyle(color: KeliTheme.text),
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, color: KeliTheme.muted),
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(icon: Icon(Icons.clear, color: KeliTheme.muted, size: 18), onPressed: () => setState(() => _q = '')),
            hintText: 'search by name, category, look…',
            hintStyle: TextStyle(color: KeliTheme.muted),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.surface2)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.accent)),
          ),
        ),
        const SizedBox(height: 10),
        // category + gender filter chips (one horizontally-scrolling row)
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _Chip(label: 'All', count: all.length, on: _cat == null, onTap: () => setState(() => _cat = null)),
              for (final c in cats)
                _Chip(label: c.key, count: c.value, on: _cat == c.key, onTap: () => setState(() => _cat = c.key)),
              if (hasBothGenders) ...[
                _Divider(),
                _Chip(icon: Icons.wc, label: 'All', on: _gender == null, onTap: () => setState(() => _gender = null)),
                _Chip(icon: Icons.female, label: 'Women', on: _gender == 'female', onTap: () => setState(() => _gender = 'female')),
                _Chip(icon: Icons.male, label: 'Men', on: _gender == 'male', onTap: () => setState(() => _gender = 'male')),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Flexible(child: _grid(context, shown, current)),
      ],
    );
  }

  Widget _grid(BuildContext context, List<_GalleryAvatar> shown, String? current) {
    if (shown.isEmpty) {
      return _center(Column(mainAxisSize: MainAxisSize.min, children: [
        Text('No models match these filters.', style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => setState(() { _q = ''; _cat = null; _gender = null; }),
          child: Text('Clear filters', style: TextStyle(color: KeliTheme.accent)),
        ),
      ]));
    }
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 130 * _zoom, childAspectRatio: 0.62, crossAxisSpacing: 8, mainAxisSpacing: 8),
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final a = shown[i];
        final on = current != null && current == a.skin;
        return InkWell(
          onTap: () => _pick(context, a.skin),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              color: on ? KeliTheme.surface2 : KeliTheme.bg,
              border: Border.all(color: on ? KeliTheme.accent : KeliTheme.surface2, width: 2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: on ? KeliTheme.glow(blur: 10, alpha: 0.25) : null,
            ),
            padding: const EdgeInsets.all(5),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(a.url, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(Icons.broken_image, color: KeliTheme.muted),
                          loadingBuilder: (_, child, p) => p == null
                              ? child
                              : Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent)))),
                    ),
                    if (on)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(color: KeliTheme.accent, shape: BoxShape.circle),
                          child: Icon(Icons.check, size: 13, color: KeliTheme.bg),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(UnityBridge.humanize(a.name),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on ? KeliTheme.accent : KeliTheme.text, fontSize: 11, fontWeight: FontWeight.w600)),
              Text(a.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: KeliTheme.muted, fontSize: 9.5)),
            ]),
          ),
        );
      },
    );
  }

  // ── loading spinner / offline fallback (plain searchable list of Unity-reported skins) ──
  Widget _loadingOrFallback(BuildContext context, UnityBridge bridge, String? current) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Select a model', style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16))),
          IconButton(icon: Icon(Icons.close, color: KeliTheme.muted), onPressed: () => Navigator.of(context).pop()),
        ]),
        const SizedBox(height: 6),
        // Gallery still loading (and not yet failed) → spinner.
        if (_gallery == null && !_failed)
          _center(const _Spinner('loading models…'))
        else
          _fallbackList(context, bridge, current),
      ],
    );
  }

  Widget _fallbackList(BuildContext context, UnityBridge bridge, String? current) {
    final all = bridge.skins;
    if (all.isEmpty) {
      return _center(Text(
          bridge.awaiting ? 'loading models from the face…' : 'No models from Maradel, and none reported by Unity.',
          style: TextStyle(color: KeliTheme.muted, fontSize: 12), textAlign: TextAlign.center));
    }
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty ? all : all.where((s) => '${s.display} ${s.category} ${s.real}'.toLowerCase().contains(q)).toList();
    return Flexible(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            style: TextStyle(color: KeliTheme.text),
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, color: KeliTheme.muted),
              hintText: 'search models…',
              hintStyle: TextStyle(color: KeliTheme.muted),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.surface2)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.accent)),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shown.length,
              itemBuilder: (_, i) {
                final s = shown[i];
                final on = current == s.real;
                return ListTile(
                  dense: true,
                  leading: on ? Icon(Icons.check_circle, color: KeliTheme.accent, size: 18) : null,
                  title: Text(s.display, style: TextStyle(color: on ? KeliTheme.accent : KeliTheme.text, fontWeight: FontWeight.w600)),
                  subtitle: Text('${s.category} · ${s.real}', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
                  trailing: Icon(Icons.chevron_right, color: KeliTheme.muted, size: 18),
                  onTap: () => _pick(context, s.real),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _center(Widget child) => Padding(padding: const EdgeInsets.all(28), child: Center(child: child));
}

/// A compact pill chip for the category / gender filters.
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap, this.count, this.icon});
  final String label;
  final int? count;
  final IconData? icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? KeliTheme.accent : KeliTheme.muted;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? KeliTheme.accent.withValues(alpha: 0.16) : KeliTheme.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? KeliTheme.accent.withValues(alpha: 0.7) : KeliTheme.edge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
              Text(label, style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
              if (count != null) ...[
                const SizedBox(width: 5),
                Text('$count', style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin vertical separator between the category chips and the gender chips.
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8), color: KeliTheme.edge);
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
