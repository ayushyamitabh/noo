import 'package:flutter/material.dart';
import 'nav/noo_nav_style.dart';

/// The one place screens decide mobile vs desktop layout and iOS vs Android
/// chrome (DESIGN_SYSTEM.md 3), so every screen switches at the same point.
class NooLayout {
  const NooLayout._();

  /// Window width at which the shell swaps the bottom bar + drawer for the
  /// desktop sidebar + toolbar, and screens switch to desktop recipes
  /// (table rows, 5-column grids, 8-column photos, 24px gutter).
  static const double desktopBreakpoint = 900;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= desktopBreakpoint;

  static NooNavStyle navStyle(BuildContext context) =>
      NooNavStyle.fromPlatform(Theme.of(context).platform);

  /// True where the spec calls for the iOS variant of a content detail
  /// (`ellipsis` rather than `ellipsis-vertical` overflow, etc.).
  static bool iosStyle(BuildContext context) =>
      navStyle(context) == NooNavStyle.ios;

  /// Horizontal content gutter: 12 on mobile (cards), 24 on desktop.
  static double gutter(BuildContext context) => isDesktop(context) ? 24 : 12;
}
