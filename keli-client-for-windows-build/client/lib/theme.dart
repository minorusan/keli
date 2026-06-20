import 'package:flutter/material.dart';

/// Keli's look — **Maradel's fel aesthetic, frost-shifted**: the same obsidian void and
/// glowing acid accent, but the fel-green is pulled toward a cold spectral teal/blue so
/// Keli reads as Maradel's cooler twin. Glow is kept everywhere (see [glow] / [backdrop]).
///
/// The palette is **live**: it is seeded with the fel-frost defaults below and can be recolored at
/// runtime from the active Maradel persona's `keliColors` via [applyKeliColors] (see `Persona`). The
/// colors are plain `static` (not `const`) so they can change; [revision] bumps on every recolor so
/// the app can rebuild (the root wraps `MaterialApp` in a `ValueListenableBuilder` on it).
class KeliTheme {
  // ── fel-frost palette (Maradel's fel, blue-shifted) — runtime-mutable ──
  static Color accent = const Color(0xFF3DF2C8); // primary — spectral fel-teal (was acid green)
  static Color accentBright = const Color(0xFF9BFFE9); // highlight / readable accent text
  static Color accentDeep = const Color(0xFF12B894); // saturated
  static Color accentDim = const Color(0xFF5E908A); // muted accent labels
  static Color corrupt = const Color(0xFF6C7BFF); // blue-violet counter-glow (was fel purple)

  static Color bg = const Color(0xFF04070C); // obsidian void (blue-black)
  static Color surface = const Color(0xFF0A1218); // panels
  static Color surface2 = const Color(0xFF101E28); // inputs / raised
  static Color edge = const Color(0xFF1E3A44); // borders
  static Color text = const Color(0xFFD3F2F0); // primary text (blue-white "bone")
  static Color muted = const Color(0xFF6E8B92); // muted labels
  static Color danger = const Color(0xFFFF6A6A);

  /// Bumped whenever the palette changes — drives a full UI repaint.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Recolor the live palette from a persona's `keliColors` map (keys map 1:1 to the fields above:
  /// accent, accentBright, accentDeep, accentDim, corrupt, bg, surface, surface2, edge, text, muted,
  /// danger). Unknown keys / unparseable values are ignored, so a partial map just updates what it can.
  static void applyKeliColors(Map<String, dynamic>? colors) {
    if (colors == null || colors.isEmpty) return;
    var changed = false;
    void set(String key, void Function(Color) assign) {
      final c = _parseHex(colors[key]);
      if (c != null) {
        assign(c);
        changed = true;
      }
    }

    set('accent', (c) => accent = c);
    set('accentBright', (c) => accentBright = c);
    set('accentDeep', (c) => accentDeep = c);
    set('accentDim', (c) => accentDim = c);
    set('corrupt', (c) => corrupt = c);
    set('bg', (c) => bg = c);
    set('surface', (c) => surface = c);
    set('surface2', (c) => surface2 = c);
    set('edge', (c) => edge = c);
    set('text', (c) => text = c);
    set('muted', (c) => muted = c);
    set('danger', (c) => danger = c);

    if (changed) revision.value++;
  }

  /// Parse `#RRGGBB` / `#AARRGGBB` (or without the leading `#`) → [Color]; null if unparseable.
  static Color? _parseHex(dynamic v) {
    if (v is! String) return null;
    var s = v.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 6) s = 'FF$s'; // assume opaque
    if (s.length != 8) return null;
    final n = int.tryParse(s, radix: 16);
    return n == null ? null : Color(n);
  }

  /// Fel-frost glow shadow (mirrors Maradel's AppTheme.glow). [color] defaults to the live [accent].
  static List<BoxShadow> glow({Color? color, double blur = 12, double alpha = 0.5}) =>
      [BoxShadow(color: (color ?? accent).withValues(alpha: alpha), blurRadius: blur)];

  /// Atmospheric background: void with frost-fel light bleeding from the top-right corner.
  static BoxDecoration get backdrop => BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.85, -0.9),
          radius: 1.4,
          colors: [accent.withValues(alpha: 0.13), const Color(0x00000000)],
          stops: const [0.0, 0.55],
        ),
      );

  /// Second corner bleed: blue-violet from the bottom-left.
  static BoxDecoration get backdrop2 => BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.9, 1.0),
          radius: 1.3,
          colors: [corrupt.withValues(alpha: 0.09), const Color(0x00000000)],
          stops: const [0.0, 0.5],
        ),
      );

  static ThemeData dark() {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: bg,
      secondary: corrupt,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: surface2,
      error: danger,
      onError: bg,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      appBarTheme: AppBarTheme(backgroundColor: surface, foregroundColor: text, elevation: 0),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: text, fontSize: 15.5, height: 1.55),
        bodyMedium: TextStyle(color: text, fontSize: 14, height: 1.5),
        bodySmall: TextStyle(color: muted, fontSize: 12.5),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accent),
      ),
      iconTheme: IconThemeData(color: accentDim),
      snackBarTheme: SnackBarThemeData(backgroundColor: surface2, contentTextStyle: TextStyle(color: text)),
      dividerColor: surface2,
    );
  }
}
