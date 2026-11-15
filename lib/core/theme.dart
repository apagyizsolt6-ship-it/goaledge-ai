import 'package:flutter/material.dart';

class AppTheme {
  static const bg = Color(0xFF0A0E17);
  static const surface = Color(0xFF131A29);
  static const border = Color(0xFF1F2937);
  static const primary = Color(0xFF10B981);
  static const secondary = Color(0xFF3B82F6);
  static const danger = Color(0xFFEF4444);
  static const muted = Color(0xFF9CA3AF);
  static const gray = Color(0xFF374151);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: secondary,
          surface: surface,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: border, width: 1),
          ),
        ),
        useMaterial3: true,
      );
}
