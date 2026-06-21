import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_log.dart';

/// One skin/avatar the embedded Unity face can wear.
class SkinItem {
  final String real; // the real (file) name — sent back to Unity in set_skin
  final String display; // human-readable, derived via [UnityBridge.humanize]
  final String category;
  const SkinItem({required this.real, required this.display, required this.category});
}

/// The Flutter↔Unity message bridge. Wire [onUnityMessage] to `EmbedUnity.onMessageFromUnity`.
///
/// Avatars are Unity "skins": [requestSkins] asks Unity for the list (`get_skins`), which arrives as a
/// `skins` envelope flattened into one ordered [skins] ring. FLUTTER OWNS THE INDEX — [nextSkin] /
/// [prevSkin] step it and [setSkin] applies it (`set_skin`), and the selection is persisted so the
/// face matches the shown label after a cold start. Unity also (optionally) echoes the live avatar via
/// an `avatar` message, which we use to keep [index] in sync with Unity-initiated changes.
class UnityBridge extends ChangeNotifier {
  static const _prefKey = 'keli.avatarReal';

  List<SkinItem> _skins = const [];
  bool _awaiting = false;
  int _idx = 0; // Flutter-owned current position in [_skins]
  String? _savedReal; // restored from prefs on launch
  String? _unityReal; // last avatar Unity reported (so we can avoid a redundant reload)
  bool _restored = false; // applied the saved selection once (on the first skins reply)
  DateTime? _lastSkinReq; // throttle for the "ask again until the list arrives" retry

  List<SkinItem> get skins => _skins;
  bool get awaiting => _awaiting;
  int get index => _idx;
  int get total => _skins.length;

  // A skin swap is in flight: set when we ask Unity to load a skin, cleared when Unity echoes the live
  // `avatar` (load+wire done) or after a safety timeout. Drives the face's loading overlay so the
  // ◀/▶ + picker don't feel dead during the (sometimes multi-second) remote download + instantiate.
  bool _loading = false;
  Timer? _loadTimeout;
  bool get loading => _loading;

  void _beginLoading() {
    _loadTimeout?.cancel();
    // Generous cap — a cold (uncached) Rocketbox avatar can take several seconds to download + wire.
    _loadTimeout = Timer(const Duration(seconds: 25), () {
      if (_loading) {
        _loading = false;
        notifyListeners();
      }
    });
    if (!_loading) {
      _loading = true;
      notifyListeners();
    }
  }

  void _endLoading() {
    _loadTimeout?.cancel();
    _loadTimeout = null;
    if (_loading) {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  /// The avatar currently shown (the skin at [index]) — drives the ◀/▶ name + category label.
  SkinItem? get currentSkin => (_idx >= 0 && _idx < _skins.length) ? _skins[_idx] : null;

  /// Fired when the USER picks a skin on the tablet (picker / ◀▶) — NOT on persona-driven changes.
  /// `Persona` uses this to bind the chosen avatar to the active persona (POST /persona/skin).
  void Function(String real)? onUserPickedSkin;

  /// Load the persisted selection and ask Unity for the skin list. Call once at startup.
  Future<void> init() async {
    try {
      _savedReal = (await SharedPreferences.getInstance()).getString(_prefKey);
    } catch (_) {/* nothing persisted */}
    requestSkins();
  }

  /// Ask Unity for the skin list IF we still don't have it — retried (throttled) on each inbound
  /// Unity message. The startup [requestSkins] in [init] can be lost when it fires before the Unity
  /// runtime is listening, and Unity only finishes discovering its (remote) avatars a moment after it
  /// boots; so we keep asking — driven by Unity's own log/`avatar` chatter — until a non-empty list
  /// arrives, then stop. This is what makes the ◀/▶ buttons work without a manual picker open.
  void _maybeRequestSkins() {
    if (_skins.isNotEmpty) return;
    final now = DateTime.now();
    if (_lastSkinReq != null && now.difference(_lastSkinReq!) < const Duration(seconds: 3)) return;
    _lastSkinReq = now;
    requestSkins();
  }

  // ── inbound (Unity → Flutter) ──
  void onUnityMessage(String raw) {
    _maybeRequestSkins(); // any message proves Unity is alive → (re)ask for skins until we have them
    // Pipe a forwarded Unity console line (Application.logMessageReceived → SendToFlutter "log")
    // CLEANLY into the shared keli log; everything else is logged raw so nothing is ever lost.
    try {
      final env = jsonDecode(raw);
      if (env is Map && env['type'] == 'log') {
        final inner = env['json'];
        final data = (inner is String && inner.isNotEmpty) ? jsonDecode(inner) : inner;
        final msg = (data is Map ? (data['msg'] ?? data['message'] ?? '') : data ?? '').toString();
        final lvl = (data is Map ? (data['level'] ?? data['type'] ?? '') : '').toString();
        AppLog.log('unity', lvl.isEmpty ? msg : '$lvl: $msg');
        return;
      }
    } catch (_) {/* not a JSON envelope — fall through to raw */}
    AppLog.log('unity', raw);
    try {
      final env = jsonDecode(raw);
      // Unity echoes the live avatar (optional nice-to-have) → sync our index to it.
      if (env is Map && env['type'] == 'avatar') {
        final inner = env['json'];
        final d = (inner is String && inner.isNotEmpty) ? jsonDecode(inner) : inner;
        if (d is Map) {
          _unityReal = '${d['file'] ?? d['name'] ?? ''}';
          final i = _skins.indexWhere((s) => s.real == _unityReal);
          if (i >= 0) _idx = i;
          _endLoading(); // the live avatar changed → the swap finished; drop the loading overlay
          notifyListeners();
        }
        return;
      }
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
        _restoreSelection();
        notifyListeners();
      }
    } catch (_) {
      /* not a JSON bridge message — already logged */
    }
  }

  /// On the first skin list, point [index] at the persisted avatar and re-apply it so the face
  /// matches the restored label — unless Unity already restored the same one (avoids a needless load).
  void _restoreSelection() {
    if (_restored || _skins.isEmpty) return;
    _restored = true;
    if (_savedReal != null && _savedReal!.isNotEmpty) {
      final i = _skins.indexWhere((s) => s.real == _savedReal);
      if (i >= 0) {
        _idx = i;
        if (_unityReal != _savedReal) {
          _send(_savedReal!); // Unity isn't already on it → load it
          AppLog.log('bridge', 'restored avatar "$_savedReal" (idx $i)');
        }
        return;
      }
    }
    // No usable saved pref → adopt whatever Unity restored, if known.
    if (_unityReal != null) {
      final i = _skins.indexWhere((s) => s.real == _unityReal);
      if (i >= 0) _idx = i;
    }
  }

  // ── outbound (Flutter → Unity) ──
  void requestSkins() {
    _awaiting = true;
    notifyListeners();
    sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'get_skins'}));
    AppLog.log('bridge', '→unity: get_skins');
  }

  void _send(String real) {
    sendToUnity('FlutterFace', 'OnMessage', jsonEncode({'type': 'set_skin', 'text': real}));
    AppLog.log('bridge', '→unity: set_skin $real');
  }

  Future<void> _persist(String real) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_prefKey, real);
    } catch (_) {/* best-effort */}
  }

  /// Apply a skin by its real name from a USER action (picker or ◀/▶): syncs [index], persists it,
  /// and notifies [onUserPickedSkin] so it gets bound to the active persona.
  void setSkin(String real) {
    _applySkin(real);
    onUserPickedSkin?.call(real);
  }

  /// Apply a skin chosen by the active PERSONA (no `onUserPickedSkin` → no bind-back POST loop).
  void applySkinExternally(String real) => _applySkin(real);

  void _applySkin(String real) {
    _send(real);
    final i = _skins.indexWhere((s) => s.real == real);
    if (i >= 0) _idx = i;
    _persist(real);
    _beginLoading(); // show the face loading overlay until Unity echoes the live `avatar`
    notifyListeners();
  }

  /// Step to the next avatar in the ring (◀/▶). No-op until the skin list has loaded.
  void nextSkin() {
    if (_skins.isEmpty) return;
    _idx = (_idx + 1) % _skins.length;
    setSkin(_skins[_idx].real);
  }

  void prevSkin() {
    if (_skins.isEmpty) return;
    _idx = (_idx - 1 + _skins.length) % _skins.length;
    setSkin(_skins[_idx].real);
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
