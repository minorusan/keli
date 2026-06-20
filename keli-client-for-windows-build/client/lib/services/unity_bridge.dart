import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

import '../app_log.dart';

/// One skin/avatar the embedded Unity face can wear.
class SkinItem {
  final String real; // the real (file) name — sent back to Unity in set_skin
  final String display; // human-readable, derived via [UnityBridge.humanize]
  final String category;
  const SkinItem({required this.real, required this.display, required this.category});
}

/// The Flutter↔Unity message bridge. Wire [onUnityMessage] to `EmbedUnity.onMessageFromUnity`:
/// it logs every inbound message and parses the `skins` reply. Outbound: [requestSkins] / [setSkin]
/// (and the generic Bridge tool uses sendToUnity directly).
class UnityBridge extends ChangeNotifier {
  List<SkinItem> _skins = const [];
  bool _awaiting = false;

  List<SkinItem> get skins => _skins;
  bool get awaiting => _awaiting;

  // ── inbound (Unity → Flutter) ──
  void onUnityMessage(String raw) {
    AppLog.log('unity', raw);
    try {
      final env = jsonDecode(raw);
      if (env is Map && env['type'] == 'skins') {
        final inner = env['json'];
        final data = (inner is String && inner.isNotEmpty) ? jsonDecode(inner) : inner;
        final cats = (data is Map ? data['categories'] : null) as List? ?? const [];
        final items = <SkinItem>[];
        for (final c in cats) {
          if (c is! Map) continue;
          final cat = '${c['name'] ?? ''}';
          for (final s in (c['skins'] as List? ?? const [])) {
            final real = '$s';
            if (real.isEmpty) continue;
            items.add(SkinItem(real: real, display: humanize(real), category: cat));
          }
        }
        _skins = items;
        _awaiting = false;
        AppLog.log('bridge', 'skins received: ${items.length}');
        notifyListeners();
      }
    } catch (_) {
      /* not a JSON bridge message — already logged */
    }
  }

  // ── outbound (Flutter → Unity) ──
  void requestSkins() {
    _awaiting = true;
    notifyListeners();
    sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'get_skins'}));
    AppLog.log('bridge', '→unity: get_skins');
  }

  void setSkin(String real) {
    sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'set_skin', 'text': real}));
    AppLog.log('bridge', '→unity: set_skin $real');
  }

  /// Derive a human-readable display name from a real skin/file name, e.g.
  /// `Business_Female_04_facial` → `Business Female 04`, `f_businessSuit` → `F Business Suit`.
  static String humanize(String real) {
    var s = real;
    s = s.replaceAll(RegExp(r'\.(fbx|prefab|asset)$', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'[_\- ](facial|hipoly|lowpoly|lod\d*)$', caseSensitive: false), '');
    s = s.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}'); // camelCase
    s = s.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    final words = s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0].toUpperCase() + w.substring(1));
    final out = words.join(' ');
    return out.isEmpty ? real : out;
  }
}
