import 'package:flutter/material.dart';

/// Keli's look — **Maradel's fel aesthetic, frost-shifted**: the same obsidian void and
/// glowing acid accent, but the fel-green is pulled toward a cold spectral teal/blue so
/// Keli reads as Maradel's cooler twin. Glow is kept everywhere (see [glow] / [backdrop]).
class KeliTheme {
  // ── fel-frost palette (Maradel's fel, blue-shifted) ──
  static const Color accent = Color(0xFF3DF2C8); // primary — spectral fel-teal (was acid green)
  static const Color accentBright = Color(0xFF9BFFE9); // highlight / readable accent text
  static const Color accentDeep = Color(0xFF12B894); // saturated
  static const Color accentDim = Color(0xFF5E908A); // muted accent labels
  static const Color corrupt = Color(0xFF6C7BFF); // blue-violet counter-glow (was fel purple)

  static const Color bg = Color(0xFF04070C); // obsidian void (blue-black)
  static const Color surface = Color(0xFF0A1218); // panels
  static const Color surface2 = Color(0xFF101E28); // inputs / raised
  static const Color edge = Color(0xFF1E3A44); // borders
  static const Color text = Color(0xFFD3F2F0); // primary text (blue-white "bone")
  static const Color muted = Color(0xFF6E8B92); // muted labels
  static const Color danger = Color(0xFFFF6A6A);

  /// Fel-frost glow shadow (mirrors Maradel's AppTheme.glow).
  static List<BoxShadow> glow({Color color = accent, double blur = 12, double alpha = 0.5}) =>
      [BoxShadow(color: color.withValues(alpha: alpha), blurRadius: blur)];

  /// Atmospheric background: void with frost-fel light bleeding from the top-right corner.
  static BoxDecoration get backdrop => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.85, -0.9),
          radius: 1.4,
          colors: [Color(0x223DF2C8), Color(0x00000000)],
          stops: [0.0, 0.55],
        ),
      );

  /// Second corner bleed: blue-violet from the bottom-left.
  static BoxDecoration get backdrop2 => const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.9, 1.0),
          radius: 1.3,
          colors: [Color(0x186C7BFF), Color(0x00000000)],
          stops: [0.0, 0.5],
        ),
      );

  static ThemeData dark() {
    final scheme = const ColorScheme.dark(
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
      appBarTheme: const AppBarTheme(backgroundColor: surface, foregroundColor: text, elevation: 0),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: text, fontSize: 15.5, height: 1.55),
        bodyMedium: TextStyle(color: text, fontSize: 14, height: 1.5),
        bodySmall: TextStyle(color: muted, fontSize: 12.5),
        headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: accent),
      ),
      iconTheme: const IconThemeData(color: accentDim),
      snackBarTheme: const SnackBarThemeData(backgroundColor: surface2, contentTextStyle: TextStyle(color: text)),
      dividerColor: surface2,
    );
  }
}
