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
/// standing in for elevation instead of a shadow (product UI stays flat -
/// DESIGN_SYSTEM.md 1.4 - so this is the one place that border does that
/// job). The host `Scaffold` needs `extendBody: true` while floating, so
/// its body scrolls behind the bar's transparent margin instead of
/// stopping short of it like [attached] does.
enum NooBottomBarStyle { attached, floating }

/// One destination in a [NooBottomBar]. Data-agnostic on purpose - the app
/// maps its own tab model (e.g. `AppTab`) onto these.
@immutable
class NooNavDestination {
  final IconData icon;
  final String label;

  const NooNavDestination({required this.icon, required this.label});
}
