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

/// One destination in a [NooBottomBar]. Data-agnostic on purpose - the app
/// maps its own tab model (e.g. `AppTab`) onto these.
@immutable
class NooNavDestination {
  final IconData icon;
  final String label;

  const NooNavDestination({required this.icon, required this.label});
}
