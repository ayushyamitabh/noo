import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic color tokens from `.claude/context/design-system/DESIGN_SYSTEM.md`
/// section 1.1 - read that file before changing any value here. Registered
/// on [ThemeData.extensions], so call sites reach these via
/// `Theme.of(context).extension<NooColors>()!` (or a `context.nooColors`
/// getter, once one exists) instead of the Material [ColorScheme] roles.
///
/// Two independent sources feed this, matching the app's color settings:
/// the fixed [light]/[dark] palettes below (the design system's own
/// default look), or [NooColors.fromDynamicScheme] when the user has
/// Material You dynamic color turned on - there's no third option (no
/// custom accent picker), since the design system explicitly rules out
/// "add new colors". [withAmoled] layers on top of either source when the
/// user's AMOLED toggle is on.
@immutable
class NooColors extends ThemeExtension<NooColors> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color line;
  final Color fg1;
  final Color fg2;
  final Color fg3;
  final Color accent;
  final Color accentText;
  final Color accentSoft;
  final Color danger;
  final Color dangerSoft;
  final Color dangerFill;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color info;
  final Color infoSoft;
  final Color scrim;

  const NooColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.line,
    required this.fg1,
    required this.fg2,
    required this.fg3,
    required this.accent,
    required this.accentText,
    required this.accentSoft,
    required this.danger,
    required this.dangerSoft,
    required this.dangerFill,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.info,
    required this.infoSoft,
    required this.scrim,
  });

  static const light = NooColors(
    bg: Color(0xFFF3EFE6),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF6F5F2),
    surface3: Color(0xFFEAE8E2),
    line: Color(0xFFEAE8E2),
    fg1: Color(0xFF0E0D0B),
    fg2: Color(0xFF5A5852),
    fg3: Color(0xFF7C7A72),
    accent: Color(0xFF8D0DE3),
    accentText: Color(0xFF8D0DE3),
    accentSoft: Color(0xFFECDFFF),
    danger: Color(0xFFA8202A),
    dangerSoft: Color(0xFFFDE7E7),
    dangerFill: Color(0xFFA8202A),
    success: Color(0xFF3E7A23),
    successSoft: Color(0xFFEAF5DF),
    warning: Color(0xFF8C5A0E),
    warningSoft: Color(0xFFFBEFD0),
    info: Color(0xFF2940A8),
    infoSoft: Color(0xFFE6ECFE),
    scrim: Color(0x730E0D0B),
  );

  static const dark = NooColors(
    bg: Color(0xFF0E0D0B),
    surface: Color(0xFF25241F),
    surface2: Color(0xFF3D3C38),
    surface3: Color(0xFF5A5852),
    line: Color(0xFF3D3C38),
    fg1: Color(0xFFF3EFE6),
    fg2: Color(0xFFBDBAB1),
    fg3: Color(0xFF9E9B92),
    accent: Color(0xFF8D0DE3),
    accentText: Color(0xFFCBA5FD),
    accentSoft: Color(0xFF2F0454),
    danger: Color(0xFFF49E9E),
    dangerSoft: Color(0xFF560F18),
    dangerFill: Color(0xFFA8202A),
    success: Color(0xFFB7DD9F),
    successSoft: Color(0xFF1E3F10),
    warning: Color(0xFFF0C26C),
    warningSoft: Color(0xFF4A3208),
    info: Color(0xFFB6C3FB),
    infoSoft: Color(0xFF1C2B73),
    scrim: Color(0x99000000),
  );

  /// Avatar/photo-placeholder fills (`DESIGN_SYSTEM.md` 1.1) - a fixed
  /// secondary palette, same in light and dark, always paired with
  /// [avatarTextColor]. Content-identity colors, not theme, so they don't
  /// change with brightness or dynamic color (same reasoning as file-type
  /// tinting in `styling.md`).
  static const avatarPalette = [
    Color(0xFF8DCDE2),
    Color(0xFF96B0FD),
    Color(0xFFE5D8BD),
    Color(0xFFEEEDB3),
    Color(0xFFDA9AC7),
    Color(0xFFA7D296),
    Color(0xFFE9A6A7),
    Color(0xFF85D1BD),
    Color(0xFFCBA5FD),
  ];
  static const avatarTextColor = Color(0xFF0E0D0B);

  /// Maps a Material You dynamic [ColorScheme] onto these roles for users
  /// who've turned dynamic color on, instead of the fixed [light]/[dark]
  /// palettes. `success`/`successSoft`/`warning`/`warningSoft`/`info`/
  /// `infoSoft` have no Material dynamic equivalent and are content-identity
  /// colors regardless (file-type tiles) rather than brand colors, so they
  /// always come from the fixed palette matching [cs]'s brightness.
  factory NooColors.fromDynamicScheme(ColorScheme cs) {
    final fixed = cs.brightness == Brightness.dark ? dark : light;
    return NooColors(
      bg: cs.surface,
      surface: cs.surfaceContainerLow,
      surface2: cs.surfaceContainerHigh,
      surface3: cs.surfaceContainerHighest,
      line: cs.outlineVariant,
      fg1: cs.onSurface,
      fg2: cs.onSurfaceVariant,
      fg3: cs.onSurfaceVariant,
      accent: cs.primary,
      accentText: cs.primary,
      accentSoft: cs.primaryContainer,
      danger: cs.error,
      dangerSoft: cs.errorContainer,
      dangerFill: cs.error,
      success: fixed.success,
      successSoft: fixed.successSoft,
      warning: fixed.warning,
      warningSoft: fixed.warningSoft,
      info: fixed.info,
      infoSoft: fixed.infoSoft,
      scrim: cs.scrim,
    );
  }

  /// True OLED black across every surface tone - not just [bg] - so cards,
  /// bars and sheets all go black too instead of the dark palette's warm
  /// dark-grey tones. Mirrors the AMOLED handling this replaces in
  /// `AppTheme.dark` (see git history), just against these tokens instead
  /// of Material [ColorScheme] roles.
  NooColors withAmoled() => copyWith(
    bg: Colors.black,
    surface: Colors.black,
    surface2: Colors.black,
    surface3: Colors.black,
  );

  @override
  NooColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? line,
    Color? fg1,
    Color? fg2,
    Color? fg3,
    Color? accent,
    Color? accentText,
    Color? accentSoft,
    Color? danger,
    Color? dangerSoft,
    Color? dangerFill,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? info,
    Color? infoSoft,
    Color? scrim,
  }) {
    return NooColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      line: line ?? this.line,
      fg1: fg1 ?? this.fg1,
      fg2: fg2 ?? this.fg2,
      fg3: fg3 ?? this.fg3,
      accent: accent ?? this.accent,
      accentText: accentText ?? this.accentText,
      accentSoft: accentSoft ?? this.accentSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      dangerFill: dangerFill ?? this.dangerFill,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  NooColors lerp(ThemeExtension<NooColors>? other, double t) {
    if (other is! NooColors) return this;
    return NooColors(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      line: Color.lerp(line, other.line, t)!,
      fg1: Color.lerp(fg1, other.fg1, t)!,
      fg2: Color.lerp(fg2, other.fg2, t)!,
      fg3: Color.lerp(fg3, other.fg3, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      dangerFill: Color.lerp(dangerFill, other.dangerFill, t)!,
      success: Color.lerp(success, other.success, t)!,
      successSoft: Color.lerp(successSoft, other.successSoft, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// Reads the app's [NooColors] - registered on every [ThemeData] built by
/// `AppTheme`, so this is never actually null in a running app.
extension NooColorsContext on BuildContext {
  NooColors get nooColors => Theme.of(this).extension<NooColors>()!;
}

/// The 4px spacing scale from the Noo Design System project's
/// `tokens/spacing.css` (claude.ai/design, project id
/// bb69c00d-f400-445c-9683-355668c0bfe1 - the authoritative source now;
/// `.claude/context/design-system/` is the earlier, less precise mockup
/// export).
class NooSpace {
  const NooSpace._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double smd = 14;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii from `tokens/spacing.css`. `pill` covers every button,
/// chip, segmented control, toggle, search field and badge.
class NooRadii {
  const NooRadii._();
  static const double pill = 999;
  static const double card = 20;
  static const double gridCard = 18;
  static const double input = 14;
  static const double sidebarItem = 12;
  static const double sheetTop = 28;
  static const double dialog = 24;
  static const double dropdown = 10;
  static const double screenCornerAndroid = 36;
  static const double screenCornerIOS = 48;
  static const double windowMac = 12;
  static const double windowWin = 8;
}

/// Fixed heights/widths from `tokens/spacing.css` - button sizes, row
/// heights, the desktop sidebar width. Named to match the component that
/// uses each one (`NooButton`'s `size` picks from the `button*` set).
class NooSizes {
  const NooSizes._();
  static const double buttonCta = 52;
  static const double buttonCard = 44;
  static const double buttonField = 40;
  static const double buttonToolbar = 36;
  static const double buttonCompact = 32;
  static const double buttonXs = 28;
  static const double rowMobile = 64;
  static const double rowDesktop = 52;
  static const double settingsRow = 52;
  static const double sidebarItem = 38;
  static const double toolbar = 64;
  static const double sidebarWidth = 256;
}

/// Motion constants from `tokens/spacing.css`'s `--ease`/`--dur-*`/
/// `--press-scale`.
class NooMotion {
  const NooMotion._();
  static const Curve ease = Cubic(0.7, 0, 0.15, 1);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 280);
  static const Duration slow = Duration(milliseconds: 480);
  static const double pressScale = 0.98;
}

/// The one shadow the design system allows, from `tokens/spacing.css`'s
/// `--shadow-dialog` - desktop dialogs only. Nothing else in the app should
/// use a `BoxShadow`.
const nooDialogShadow = BoxShadow(
  color: Color(0x241E002F), // rgba(30,0,47,.14)
  blurRadius: 48,
  offset: Offset(0, 24),
);

/// The named type scale from `DESIGN_SYSTEM.md` 1.3 - mobile sizes only for
/// now (desktop rework hasn't started). Schibsted Grotesk for headings,
/// Instrument Sans for UI text, per the spec. Color is deliberately not set
/// here - callers pull it from [NooColors] since the same style (e.g.
/// `meta`) is reused across surfaces with different foreground colors.
class NooText {
  const NooText._();

  static TextStyle get largeTitle => GoogleFonts.schibstedGrotesk(
    fontSize: 34,
    height: 0.9,
    fontWeight: FontWeight.w600,
    letterSpacing: -34 * 0.03,
  );

  static TextStyle get stat => GoogleFonts.schibstedGrotesk(
    fontSize: 32,
    height: 0.9,
    fontWeight: FontWeight.w600,
    letterSpacing: -32 * 0.03,
  );

  static TextStyle get title => GoogleFonts.schibstedGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: -22 * 0.02,
  );

  static TextStyle get cardTitle => GoogleFonts.schibstedGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    letterSpacing: -20 * 0.02,
  );

  /// Desktop `GroupedList` title / share dialog headings - 17px, between
  /// [cardTitle] and [groupHeading].
  static TextStyle get sectionTitle => GoogleFonts.schibstedGrotesk(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    letterSpacing: -17 * 0.02,
  );

  static TextStyle get groupHeading => GoogleFonts.schibstedGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    letterSpacing: -18 * 0.02,
  );

  static TextStyle get bodyL => GoogleFonts.instrumentSans(
    fontSize: 16,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get body => GoogleFonts.instrumentSans(
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w400,
  );

  static TextStyle get label => GoogleFonts.instrumentSans(
    fontSize: 13,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get meta => GoogleFonts.instrumentSans(
    fontSize: 13,
    height: 1.2,
    fontWeight: FontWeight.w400,
  );

  /// Bottom-nav label, idle state (Android: 12/500 fg-2 - see
  /// `Mobile Screen.dc.html`'s `aNav` block). Use [navLabelActive] for the
  /// selected destination.
  static TextStyle get navLabel =>
      GoogleFonts.instrumentSans(fontSize: 12, fontWeight: FontWeight.w500);

  /// Bottom-nav label, active state (Android: 12/600 fg-1, not accent-text -
  /// only the icon's pill uses accent-soft/accent-text).
  static TextStyle get navLabelActive =>
      GoogleFonts.instrumentSans(fontSize: 12, fontWeight: FontWeight.w600);

  static TextStyle get button =>
      GoogleFonts.instrumentSans(fontSize: 15, fontWeight: FontWeight.w600);

  static TextStyle get buttonSm =>
      GoogleFonts.instrumentSans(fontSize: 14, fontWeight: FontWeight.w600);

  static const mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['ui-monospace', 'Menlo'],
    fontSize: 14,
    height: 1,
  );
}
