import '../widgets/noo/nav/noo_nav_style.dart';
import 'settings_controller.dart';

/// A ready-made combination of the navigation/bottom-bar settings (Settings ->
/// Appearance -> Layout). Each one is just a set of values for options that
/// can also be changed one by one under "Navigation & bottom bar" - picking a
/// preset applies them all at once, and the one whose values the settings
/// currently equal shows as selected.
enum NavPreset {
  classic(
    'Classic',
    'Edge-to-edge bar, side menu, search up top.',
    barStyle: NooBottomBarStyle.attached,
    iconOnly: false,
    fullWidth: true,
    inlineLabel: false,
    frosted: false,
    navMenu: NooNavMenuStyle.drawer,
    avatar: AvatarPosition.top,
    searchInBar: false,
  ),
  floating(
    'Floating',
    'A floating bar with the label beside the active tab. Menu and search up top.',
    barStyle: NooBottomBarStyle.floating,
    iconOnly: false,
    fullWidth: true,
    inlineLabel: true,
    frosted: false,
    navMenu: NooNavMenuStyle.avatarMenu,
    avatar: AvatarPosition.top,
    searchInBar: false,
  ),
  withinReach(
    'Within reach',
    'Everything at the bottom: the bar, search and your avatar menu.',
    barStyle: NooBottomBarStyle.floating,
    iconOnly: false,
    fullWidth: true,
    inlineLabel: true,
    frosted: false,
    navMenu: NooNavMenuStyle.avatarMenu,
    avatar: AvatarPosition.bottom,
    searchInBar: true,
  ),
  capsule(
    'Capsule',
    'One small icon-only pill with search and your avatar tucked inside.',
    barStyle: NooBottomBarStyle.floating,
    iconOnly: true,
    fullWidth: false,
    inlineLabel: false,
    frosted: false,
    navMenu: NooNavMenuStyle.avatarMenu,
    avatar: AvatarPosition.bottom,
    searchInBar: true,
  ),
  crystal(
    'Crystal',
    'The capsule in true glass: refractive edges over your content.',
    barStyle: NooBottomBarStyle.floating,
    iconOnly: true,
    fullWidth: false,
    inlineLabel: false,
    frosted: true,
    glassStyle: GlassStyle.glass,
    navMenu: NooNavMenuStyle.avatarMenu,
    avatar: AvatarPosition.bottom,
    searchInBar: true,
  ),
  dock(
    'Frosted dock',
    'A full-width, icon-only bar in soft frosted blur.',
    barStyle: NooBottomBarStyle.floating,
    iconOnly: true,
    fullWidth: true,
    inlineLabel: false,
    frosted: true,
    glassStyle: GlassStyle.blur,
    navMenu: NooNavMenuStyle.avatarMenu,
    avatar: AvatarPosition.bottom,
    searchInBar: true,
  );

  final String label;
  final String description;
  final NooBottomBarStyle barStyle;
  final bool iconOnly;
  final bool fullWidth;
  final bool inlineLabel;
  final bool frosted;

  /// Only meaningful (and only applied/compared) when [frosted].
  final GlassStyle glassStyle;
  final NooNavMenuStyle navMenu;

  /// Only meaningful when [navMenu] is the avatar menu.
  final AvatarPosition avatar;
  final bool searchInBar;

  const NavPreset(
    this.label,
    this.description, {
    required this.barStyle,
    required this.iconOnly,
    required this.fullWidth,
    required this.inlineLabel,
    required this.frosted,
    this.glassStyle = GlassStyle.blur,
    required this.navMenu,
    required this.avatar,
    required this.searchInBar,
  });

  /// Whether the avatar button lives in the bottom bar for this preset.
  bool get avatarAtBottom =>
      navMenu == NooNavMenuStyle.avatarMenu && avatar == AvatarPosition.bottom;

  void apply(SettingsController settings) => settings.applyNavLayout(
    barStyle: barStyle,
    iconOnly: iconOnly,
    iconOnlyFullWidth: fullWidth,
    inlineLabel: inlineLabel,
    frosted: frosted,
    glassStyle: frosted ? glassStyle : null,
    navMenu: navMenu,
    avatar: avatar,
    searchInBar: searchInBar,
  );

  /// Whether [settings] currently equal this preset - ignoring the options
  /// that have no effect under the others (the full-width choice without
  /// icon-only, the glass style without frosting, ...), so toggling something
  /// irrelevant doesn't deselect it.
  bool matches(SettingsController settings) {
    if (settings.bottomBarStyle != barStyle) return false;
    if (settings.bottomBarIconOnly != iconOnly) return false;
    if (iconOnly && settings.bottomBarIconOnlyFullWidth != fullWidth) {
      return false;
    }
    if (barStyle == NooBottomBarStyle.floating &&
        !iconOnly &&
        settings.bottomBarInlineLabel != inlineLabel) {
      return false;
    }
    if (settings.bottomBarFrosted != frosted) return false;
    if (frosted && settings.glassStyle != glassStyle) return false;
    if (settings.navMenuStyle != navMenu) return false;
    if (navMenu == NooNavMenuStyle.avatarMenu &&
        settings.avatarPosition != avatar) {
      return false;
    }
    return settings.searchInBottomBar == searchInBar;
  }
}
