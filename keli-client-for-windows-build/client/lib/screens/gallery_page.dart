import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/gallery_store.dart';
import '../theme.dart';

/// The on-device gallery of drawings `ascii_draw` showed on this tablet (image + the prompt it was
/// drawn from, newest first). Tap a tile to view it full-screen; long-press to delete.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final gallery = context.watch<GalleryStore>();
    final items = gallery.items;
    return Scaffold(
      backgroundColor: KeliTheme.bg,
      appBar: AppBar(
        backgroundColor: KeliTheme.surface,
        title: Text('Gallery', style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w700)),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: KeliTheme.muted),
              tooltip: 'Clear all',
              onPressed: () => _confirmClear(context, gallery),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Text("nothing drawn yet — ask Maradel to draw something",
                  style: TextStyle(color: KeliTheme.muted, fontSize: 13)),
            )
          : GridView.builder(
              padding: EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _Tile(item: items[i], gallery: gallery),
            ),
    );
  }

  void _confirmClear(BuildContext context, GalleryStore gallery) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: KeliTheme.surface,
        title: Text('Clear gallery?', style: TextStyle(color: KeliTheme.text)),
        content: Text('Delete all saved drawings on this tablet.', style: TextStyle(color: KeliTheme.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
          TextButton(
            onPressed: () {
              gallery.clear();
              Navigator.of(context).pop();
            },
            child: Text('Clear', style: TextStyle(color: KeliTheme.danger)),
          ),
        ],
      ),
    );
  }
}

Uint8List? _decode(String b64) {
  final s = b64.contains(',') ? b64.substring(b64.indexOf(',') + 1) : b64; // strip any data: URI prefix
  try {
    return base64Decode(s.trim());
  } catch (_) {
    return null;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.gallery});
  final GalleryItem item;
  final GalleryStore gallery;

  @override
  Widget build(BuildContext context) {
    final bytes = _decode(item.image);
    return GestureDetector(
      onTap: bytes == null ? null : () => _openFullscreen(context, bytes, item.prompt),
      onLongPress: () => gallery.remove(item.ts),
      child: Container(
        decoration: BoxDecoration(
          color: KeliTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: KeliTheme.surface2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.none)
                  : Center(child: Icon(Icons.broken_image_outlined, color: KeliTheme.muted)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                item.prompt.isEmpty ? '(no prompt)' : item.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: KeliTheme.text, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, Uint8List bytes, String prompt) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(prompt.isEmpty ? 'Drawing' : prompt, style: TextStyle(fontSize: 15)),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.none),
          ),
        ),
      ),
    ));
  }
}
