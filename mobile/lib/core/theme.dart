import 'package:flutter/material.dart';

/// Identidad visual propia de OpenFoot (verde césped + ámbar), sin imitar otras apps.
class AppTheme {
  static const seed = Color(0xFF1B8A5A);
  static const live = Color(0xFFE5484D);
  static const free = Color(0xFF2E9D5B);
  static const subscription = Color(0xFF3E7BFA);
  static const ppv = Color(0xFFB7791F);

  static ThemeData dark() => _build(Brightness.dark);
  static ThemeData light() => _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: AppBarTheme(backgroundColor: scheme.surface, scrolledUnderElevation: 0),
      chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    );
  }
}
