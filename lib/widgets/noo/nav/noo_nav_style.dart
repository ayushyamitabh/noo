import 'package:flutter/widgets.dart';

/// Which platform's navigation chrome a mobile nav component draws
/// (DESIGN_SYSTEM.md 3, "Mobile"). Only the chrome differs per platform -
/// content components look the same everywhere, so this enum is only taken
/// by the `nav/` widgets ([NooBottomBar], [NooTopBar]).
enum NooNavStyle {
  ios,
  android;

  /// iOS (and macOS, when a mobile layout is shown there) get the iOS
  /// chrome; everything else gets the Android chrome.
  static NooNavStyle fromPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => NooNavStyle.ios,
        _ => NooNavStyle.android,
      };
}

/// How [NooBottomBar] sits on the screen - user-configurable in Settings
/// (Appearance). [attached] is the original edge-to-edge bar with no
/// side/bottom margin. [floating] insets it 16px from both side edges and
/// clear of the bottom safe area, rounded (28px - the same radius the
/// sheet top/drawer edge use) rather than square, with a 1px `line` border
/// plus `nooDialogShadow` - product UI otherwise stays flat (DESIGN_SYSTEM.md
/// 1.4), but a bar that's genuinely floating above scrolling content reads
/// as attached without some elevation, so it borrows the one shadow the
/// rest of the app allows itself rather than inventing a second one. The
/// host `Scaffold` needs `extendBody: true` while floating, so its body
/// scrolls behind the bar's transparent margin instead of stopping short of
/// it like [attached] does - which also means that body needs its own
/// trailing padding to clear the bar (see `NooBottomBar.rowHeight`).
enum NooBottomBarStyle { attached, floating }

/// Which widget opens the shell's navigation menu (hidden tabs + Settings)
/// on mobile - user-configurable in Settings (Appearance), same precedent
/// as [NooBottomBarStyle]. [drawer] is the original pattern: a `menu`
/// icon, top-left of the top bar, opens a left-edge `Drawer`. [avatarMenu]
/// drops that icon entirely and repurposes the avatar button - already
/// sitting top-right, already a tap target every user already knows - as
/// the one entry point instead, opening a dropdown anchored below it (see
/// `showAvatarMenu` in `widgets/avatar_menu.dart`) rather than a drawer
/// sliding from the opposite edge. Applies on both platforms, since
/// [NooTopBar]'s `onMenu`/avatar wiring is shared chrome, not
/// Android-specific - only [AppDrawer]'s left-`Drawer` convention is being
/// offered an alternative, not anything platform-only.
enum NooNavMenuStyle { drawer, avatarMenu }

/// One destination in a [NooBottomBar]. Data-agnostic on purpose - the app
/// maps its own tab model (e.g. `AppTab`) onto these.
@immutable
class NooNavDestination {
  final IconData icon;
  final String label;

  const NooNavDestination({required this.icon, required this.label});
}
