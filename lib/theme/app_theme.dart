import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color defaultNextcloudBlue = Color(0xFF0082C9);

  static const List<Color> seedColors = [
    Color(0xFF0082C9), // Nextcloud Blue
    Color(0xFF009688), // Ocean Teal
    Color(0xFF6750A4), // Deep Purple
    Color(0xFFE65100), // Sunset Amber
    Color(0xFF2E7D32), // Emerald Green
  ];

  static ThemeData light(
    Color seedColor, {
    ColorScheme? dynamicScheme,
    bool useDynamicColor = true,
  }) {
    final colorScheme = (useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.light,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme)
          .copyWith(
            headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
            titleLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w500),
          ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  static ThemeData dark(
    Color seedColor, {
    ColorScheme? dynamicScheme,
    bool useDynamicColor = true,
  }) {
    final colorScheme = (useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.dark,
          );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
          .copyWith(
            headlineMedium: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.5,
            ),
            titleLarge: GoogleFonts.inter(
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w500),
          ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        color: colorScheme.surfaceContainerLow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}
