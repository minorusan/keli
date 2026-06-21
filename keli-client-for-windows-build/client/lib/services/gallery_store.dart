import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One saved drawing: the base64 image + the prompt it was drawn from + when.
class GalleryItem {
  final String image; // base64 PNG (as received in show_image data, data: prefix stripped)
  final String prompt;
  final int ts;
  const GalleryItem({required this.image, required this.prompt, required this.ts});

  Map<String, dynamic> toJson() => {'image': image, 'prompt': prompt, 'ts': ts};
  factory GalleryItem.fromJson(Map<String, dynamic> j) =>
      GalleryItem(image: '${j['image'] ?? ''}', prompt: '${j['prompt'] ?? ''}', ts: (j['ts'] as num?)?.toInt() ?? 0);
}

/// On-device gallery of the drawings `ascii_draw` shows (image + prompt). Persisted, newest first, capped.
class GalleryStore extends ChangeNotifier {
  static const _key = 'keli.gallery';
  static const _cap = 60; // bound storage (100x100 PNGs are tiny, but keep prefs sane)
  final List<GalleryItem> _items = [];

  List<GalleryItem> get items => List.unmodifiable(_items);

  GalleryStore() {
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _items
        ..clear()
        ..addAll(list.map(GalleryItem.fromJson));
      notifyListeners();
    } catch (_) {/* nothing / unreadable */}
  }

  Future<void> _persist() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(_items.map((e) => e.toJson()).toList()));
    } catch (_) {/* best-effort */}
  }

  /// Save a drawing (newest first). `image` is base64 (data: prefix stripped).
  void add({required String image, required String prompt, int? ts}) {
    if (image.trim().isEmpty) return;
    _items.insert(0, GalleryItem(image: image, prompt: prompt, ts: ts ?? DateTime.now().millisecondsSinceEpoch));
    if (_items.length > _cap) _items.removeRange(_cap, _items.length);
    _persist();
    notifyListeners();
  }

  void remove(int ts) {
    _items.removeWhere((i) => i.ts == ts);
    _persist();
    notifyListeners();
  }

  void clear() {
    _items.clear();
    _persist();
    notifyListeners();
  }
}
