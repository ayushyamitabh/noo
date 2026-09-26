import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'design_tokens.dart';

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

  // Design-system typefaces (DESIGN_SYSTEM.md 1.3): Schibsted Grotesk for
  // headings, Instrument Sans for UI/body text. Applied over Flutter's
  // default TextTheme slots app-wide - screens not yet reworked to the
  // design system's own named type scale (`NooText`) still benefit from
  // the new typefaces immediately instead of staying on Inter until their
  // turn comes.
  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    return GoogleFonts.instrumentSansTextTheme(base).copyWith(
      displayLarge: GoogleFonts.schibstedGrotesk(
        textStyle: base.displayLarge,
        fontWeight: FontWeight.w600,
      ),
      displayMedium: GoogleFonts.schibstedGrotesk(
        textStyle: base.displayMedium,
        fontWeight: FontWeight.w600,
      ),
      displaySmall: GoogleFonts.schibstedGrotesk(
        textStyle: base.displaySmall,
        fontWeight: FontWeight.w600,
      ),
      headlineLarge: GoogleFonts.schibstedGrotesk(
        textStyle: base.headlineLarge,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.schibstedGrotesk(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
      ),
      headlineSmall: GoogleFonts.schibstedGrotesk(
        textStyle: base.headlineSmall,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.schibstedGrotesk(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.schibstedGrotesk(fontWeight: FontWeight.w500),
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
    final nooColors = (useDynamicColor && dynamicScheme != null)
        ? NooColors.fromDynamicScheme(dynamicScheme)
        : NooColors.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      extensions: [nooColors],
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: _pageTransitionsTheme,
      sliderTheme: _sliderTheme,
      textTheme: _textTheme(Brightness.light),
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
        titleTextStyle: GoogleFonts.schibstedGrotesk(
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
    var nooColors = (useDynamicColor && dynamicScheme != null)
        ? NooColors.fromDynamicScheme(dynamicScheme)
        : NooColors.dark;

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
      nooColors = nooColors.withAmoled();
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      extensions: [nooColors],
      scaffoldBackgroundColor: colorScheme.surface,
      pageTransitionsTheme: _pageTransitionsTheme,
      sliderTheme: _sliderTheme,
      textTheme: _textTheme(Brightness.dark),
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
        titleTextStyle: GoogleFonts.schibstedGrotesk(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }
}
