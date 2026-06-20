import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/unity_bridge.dart';
import '../theme.dart';

/// Skin selector: asks Unity for the skin list, shows a searchable list (human-readable names + the
/// real name), and on pick sends `set_skin <real>` to Unity and closes.
Future<void> showSkinPicker(BuildContext context) {
  context.read<UnityBridge>().requestSkins();
  return showDialog<void>(context: context, builder: (_) => _SkinPicker());
}

class _SkinPicker extends StatefulWidget {
  const _SkinPicker();

  @override
  State<_SkinPicker> createState() => _SkinPickerState();
}

class _SkinPickerState extends State<_SkinPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final bridge = context.watch<UnityBridge>();
    final all = bridge.skins;
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all.where((s) => s.display.toLowerCase().contains(q) || s.real.toLowerCase().contains(q)).toList();

    final insets = MediaQuery.of(context).viewInsets.bottom;
    final h = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: KeliTheme.surface,
      insetPadding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: h * 0.8),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Select a skin', style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  Text('${shown.length}', style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
                  IconButton(icon: Icon(Icons.close, color: KeliTheme.muted), onPressed: () => Navigator.of(context).pop()),
                ],
              ),
              SizedBox(height: 6),
              TextField(
                autofocus: true,
                style: TextStyle(color: KeliTheme.text),
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, color: KeliTheme.muted),
                  hintText: 'search by name…',
                  hintStyle: TextStyle(color: KeliTheme.muted),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.surface2)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: KeliTheme.accent)),
                ),
              ),
              SizedBox(height: 8),
              Flexible(
                child: (all.isEmpty && bridge.awaiting)
                    ? Padding(
                        padding: EdgeInsets.all(28),
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(strokeWidth: 2, color: KeliTheme.accent),
                            SizedBox(height: 12),
                            Text('loading skins from the face…', style: TextStyle(color: KeliTheme.muted, fontSize: 12)),
                          ]),
                        ),
                      )
                    : all.isEmpty
                        ? Padding(
                            padding: EdgeInsets.all(28),
                            child: Text('No skins reported by Unity. Is the face running?',
                                style: TextStyle(color: KeliTheme.muted, fontSize: 12), textAlign: TextAlign.center),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: shown.length,
                            itemBuilder: (_, i) {
                              final s = shown[i];
                              return ListTile(
                                dense: true,
                                title: Text(s.display, style: TextStyle(color: KeliTheme.text, fontWeight: FontWeight.w600)),
                                subtitle: Text('${s.category} · ${s.real}', style: TextStyle(color: KeliTheme.muted, fontSize: 11)),
                                trailing: Icon(Icons.chevron_right, color: KeliTheme.muted, size: 18),
                                onTap: () {
                                  context.read<UnityBridge>().setSkin(s.real); // real name → Unity
                                  Navigator.of(context).pop();
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
