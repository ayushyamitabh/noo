import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color defaultNextcloudBlue = Color(0xFF0082C9);

  // Flutter's Material 3 default (ZoomPageTransitionsBuilder) doesn't
  // implement Android's predictive-back gesture at all. Opting into
  // PredictiveBackPageTransitionsBuilder here (Android only) is required —
  // on top of the manifest's enableOnBackInvokedCallback flag — for the
  // system back gesture to animate/scale the current screen away instead of
  // popping instantly.
  static const _pageTransitionsTheme = PageTransitionsTheme(
    builders: {TargetPlatform.android: PredictiveBackPageTransitionsBuilder()},
  );

  // Flutter's Slider defaults to the older "2023" Material 3 look even with
  // useMaterial3 on; year2023: false opts into the current redesign (gapped
  // track, taller handle-shaped thumb) app-wide instead of per-slider. The
  // flag itself is deprecated in favor of `false` becoming the new default
  // in a future Flutter release - safe to keep using until then.
  // ignore: deprecated_member_use
  static const _sliderTheme = SliderThemeData(year2023: false);

  static const List<Color> seedColors = [
    Color(0xFF0082C9), // Nextcloud Blue
    Color(0xFF009688), // Ocean Teal
    Color(0xFF6750A4), // Deep Purple
    Color(0xFFE65100), // Sunset Amber
    Color(0xFF2E7D32), // Emerald Green
  ];

  // Flutter's default Scrollbar renders a ~6px hairline that's easy to miss
  // and hard to grab. This tunes it to read like Android's standard
  // draggable fast-scroll thumb: thicker, pill-shaped, and always at least
  // faintly visible (not just flashing in on scroll), while still getting
  // a touch more visible/opaque while actively hovered or dragged.
  static ScrollbarThemeData _scrollbarTheme(ColorScheme colorScheme) {
    final thumbColor = colorScheme.onSurfaceVariant;
    return ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged) ||
            states.contains(WidgetState.hovered)) {
          return 10.0;
        }
        return 8.0;
      }),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.dragged)) {
          return thumbColor.withValues(alpha: 0.9);
        }
        if (states.contains(WidgetState.hovered)) {
          return thumbColor.withValues(alpha: 0.8);
        }
        return thumbColor.withValues(alpha: 0.6);
      }),
      thumbVisibility: const WidgetStatePropertyAll(true),
      trackVisibility: const WidgetStatePropertyAll(false),
      interactive: true,
    );
  }

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
      pageTransitionsTheme: _pageTransitionsTheme,
      sliderTheme: _sliderTheme,
      scrollbarTheme: _scrollbarTheme(colorScheme),
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
    bool amoled = false,
  }) {
    var colorScheme = (useDynamicColor && dynamicScheme != null)
        ? dynamicScheme
        : ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: Brightness.dark,
          );

    if (amoled) {
      // True OLED black across every surface tone Material 3 hands out -
      // not just the scaffold - so cards, app bars and sheets all go black
      // too instead of the usual dark-grey elevation tints.
      colorScheme = colorScheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: Colors.black,
        surfaceContainer: Colors.black,
        surfaceContainerHigh: Colors.black,
        surfaceContainerHighest: Colors.black,
        surfaceDim: Colors.black,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: _pageTransitionsTheme,
      sliderTheme: _sliderTheme,
      scrollbarTheme: _scrollbarTheme(colorScheme),
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
