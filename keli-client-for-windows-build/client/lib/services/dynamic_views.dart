import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where a dynamic view currently lives.
enum ViewMode {
  /// The single centered centerpiece (like the Unity face used to be). Only ONE view is pinned at a
  /// time; pinning persists across restarts.
  pinned,

  /// A draggable floating window (like the Tapo cam used to be).
  floating,

  /// Parked — not on screen, listed in the Widgets dashboard to re-open.
  closed,
}

/// Stable ids + display metadata for the dynamic views. Kept widget-free so the controller can persist.
class ViewIds {
  static const unity = 'unity';
  static const tapoCam = 'tapocam';
  static const tapoMap = 'tapomap';

  /// Display order (dashboard + iteration).
  static const all = [unity, tapoCam, tapoMap];

  static String title(String id) => switch (id) {
        unity => 'MARADEL FACE',
        tapoCam => 'TAPO CAM',
        tapoMap => 'ROOMBA MAP',
        _ => id.toUpperCase(),
      };

  static IconData icon(String id) => switch (id) {
        unity => Icons.face_retouching_natural,
        tapoCam => Icons.videocam_outlined,
        tapoMap => Icons.map_outlined,
        _ => Icons.widgets_outlined,
      };
}

/// Owns where each dynamic view lives — [ViewMode.pinned] (one centerpiece at a time, persistent),
/// [ViewMode.floating] (draggable window), or [ViewMode.closed] (parked in the Widgets dashboard).
/// The layout (home_screen) reads this to place the views; the dashboard + window headers mutate it.
class DynamicViewController extends ChangeNotifier {
  static const _prefKey = 'keli.viewModes';

  // Defaults: the face is the centerpiece, the cam floats, the (often-dead) map is parked.
  final Map<String, ViewMode> _modes = {
    ViewIds.unity: ViewMode.pinned,
    ViewIds.tapoCam: ViewMode.floating,
    ViewIds.tapoMap: ViewMode.closed,
  };

  DynamicViewController() {
    _restore();
  }

  ViewMode modeOf(String id) => _modes[id] ?? ViewMode.closed;
  bool isPinned(String id) => modeOf(id) == ViewMode.pinned;
  bool isFloating(String id) => modeOf(id) == ViewMode.floating;
  bool isClosed(String id) => modeOf(id) == ViewMode.closed;

  /// The currently-pinned view id (null if none is pinned).
  String? get pinnedId {
    for (final id in ViewIds.all) {
      if (_modes[id] == ViewMode.pinned) return id;
    }
    return null;
  }

  /// Views currently floating (in display order).
  List<String> get floatingIds => [for (final id in ViewIds.all) if (isFloating(id)) id];

  /// Pin a view as the centerpiece. Any previously-pinned view drops to FLOATING (so it stays visible).
  void pin(String id) {
    if (isPinned(id)) return;
    final prev = pinnedId;
    if (prev != null && prev != id) _modes[prev] = ViewMode.floating;
    _modes[id] = ViewMode.pinned;
    _commit();
  }

  /// Detach a view into a floating window (a pinned view becomes "unpinned" — nothing pinned is fine).
  void float(String id) {
    if (isFloating(id)) return;
    _modes[id] = ViewMode.floating;
    _commit();
  }

  /// Park a view (off screen, re-openable from the dashboard).
  void close(String id) {
    if (isClosed(id)) return;
    _modes[id] = ViewMode.closed;
    _commit();
  }

  /// Apply a chosen mode (used by the dashboard's segmented control).
  void setMode(String id, ViewMode mode) {
    switch (mode) {
      case ViewMode.pinned:
        pin(id);
      case ViewMode.floating:
        float(id);
      case ViewMode.closed:
        close(id);
    }
  }

  void _commit() {
    _save();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final raw = ViewIds.all.map((id) => '$id:${modeOf(id).name}').join(',');
      await (await SharedPreferences.getInstance()).setString(_prefKey, raw);
    } catch (_) {/* best-effort */}
  }

  Future<void> _restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      for (final part in raw.split(',')) {
        final kv = part.split(':');
        if (kv.length != 2 || !ViewIds.all.contains(kv[0])) continue;
        final mode = ViewMode.values.where((v) => v.name == kv[1]);
        if (mode.isNotEmpty) _modes[kv[0]] = mode.first;
      }
      // Enforce the invariant: at most one pinned.
      var seenPinned = false;
      for (final id in ViewIds.all) {
        if (_modes[id] == ViewMode.pinned) {
          if (seenPinned) _modes[id] = ViewMode.floating;
          seenPinned = true;
        }
      }
      notifyListeners();
    } catch (_) {/* nothing persisted */}
  }
}
