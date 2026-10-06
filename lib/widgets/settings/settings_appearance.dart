import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_segmented_control.dart';
import '../noo/core/noo_toggle.dart';
import '../noo/lists/noo_settings_row.dart';
import '../noo/nav/noo_nav_style.dart';
import '../noo/noo_layout.dart';
import '../noo/overlays/noo_dialog.dart';
import '../noo/overlays/noo_sheet.dart';
import '../seek_bar_painter.dart';
import 'settings_section.dart';

String _seekBarStyleLabel(MediaProgressBarStyle style) {
  switch (style) {
    case MediaProgressBarStyle.classic:
      return 'Default';
    case MediaProgressBarStyle.wavy:
      return 'Wavy';
    case MediaProgressBarStyle.slim:
      return 'Slim';
    case MediaProgressBarStyle.squiggly:
      return 'Squiggly';
  }
}

/// Settings section 6: appearance. Only the theme mode (System/Light/Dark)
/// is in the design system's own recipe - the accent-color picker, dynamic
/// color, AMOLED and the video seek-bar style predate the design system, so
/// they're demoted into a separate "Advanced appearance" group beneath the
/// main card rather than folded into it. The accent picker itself picks a
/// [NooColors] variant (see [NooColors.fromSeed]/[NooColors.fromDynamicScheme]):
/// "Default" is the fixed violet palette, the named swatches retint just
/// the accent roles, and "Match wallpaper" (the `wallpaper`-icon swatch)
/// follows Material You dynamic color instead.
class SettingsAppearanceSection extends StatelessWidget {
  const SettingsAppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSection(
          title: 'Appearance',
          notice:
              'Bottom bar style, menu style and search in bottom bar have no effect on wide tablets, which use a sidebar.',
          children: [
            _ThemeRow(settings: settings),
            _BottomBarStyleRow(settings: settings),
            NooSettingsRow(
              icon: LucideIcons.glassWater,
              label: const Text('Frosted glass bottom bar'),
              subtitle: const Text(
                'A translucent, blurred bottom bar - content scrolls behind it',
              ),
              trailing: NooToggle(
                checked: settings.bottomBarFrosted,
                onChanged: settings.setBottomBarFrosted,
              ),
            ),
            _NavMenuStyleRow(settings: settings),
            NooSettingsRow(
              icon: LucideIcons.search,
              label: const Text('Search in bottom bar'),
              subtitle: const Text(
                'Adds Search to the bottom bar and removes it from the top '
                'bar - leaves room for one fewer regular tab',
              ),
              trailing: NooToggle(
                checked: settings.searchInBottomBar,
                onChanged: settings.setSearchInBottomBar,
              ),
            ),
          ],
        ),
        const SizedBox(height: NooSpace.xl),
        SettingsSection(
          title: 'Upload button',
          notice:
              'Auto shows the label on Files and Photos and shrinks to an icon on other tabs. Mini and Expanded stay the same on every tab. Has no effect on wide tablets.',
          children: [_FabStyleRow(settings: settings)],
        ),
        const SizedBox(height: NooSpace.xl),
        SettingsSection(
          title: 'Advanced appearance',
          children: [
            NooSettingsRow(
              icon: LucideIcons.palette,
              label: const Text('Accent color'),
              subtitle: Text(
                settings.useDynamicColor
                    ? 'Matching your wallpaper'
                    : settings.seedColor == AppTheme.defaultAccent
                    ? 'Default'
                    : 'Custom color',
              ),
              trailing: _AccentSwatchDot(
                color: settings.useDynamicColor ? null : settings.seedColor,
              ),
              onTap: () => _openAccentPicker(context, settings),
            ),
            NooSettingsRow(
              icon: LucideIcons.sparkles,
              label: const Text('AMOLED black'),
              subtitle: const Text('Use pure black backgrounds in dark mode'),
              trailing: NooToggle(
                checked: settings.amoledDark,
                onChanged: settings.setAmoledDark,
              ),
            ),
            NooSettingsRow(
              icon: LucideIcons.waves,
              label: const Text('Seek bar style'),
              subtitle: const Text(
                'The progress bar style used when playing videos',
              ),
              value: _seekBarStyleLabel(settings.mediaProgressBarStyle),
              onTap: () => _openSeekBarPicker(context, settings),
            ),
          ],
        ),
      ],
    );
  }
}

/// The "Theme" row: label on its own line, then the System/Light/Dark
/// segmented control full-width on the line below - not the usual
/// label-plus-trailing-control `NooSettingsRow` layout, since three
/// icon+label segments crammed into a trailing slot next to the row's own
/// label left every segment too cramped to read comfortably. Matches the
/// same "label, then a full-width segmented control below it" shape
/// `_showSortSheet` (Ascending/Descending) and Photos' own filter sheet
/// (All/Photos/Videos) already use.
class _ThemeRow extends StatelessWidget {
  final SettingsController settings;

  const _ThemeRow({required this.settings});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sunMoon, size: 20, color: colors.fg2),
                const SizedBox(width: 14),
                Text('Theme', style: NooText.bodyL.copyWith(color: colors.fg1)),
              ],
            ),
            const SizedBox(height: 12),
            NooSegmentedControl<ThemeMode>(
              fill: true,
              value: settings.themeMode,
              onChanged: settings.setThemeMode,
              options: const [
                NooSegmentOption(
                  value: ThemeMode.system,
                  icon: LucideIcons.monitor,
                  label: 'System',
                ),
                NooSegmentOption(
                  value: ThemeMode.light,
                  icon: LucideIcons.sun,
                  label: 'Light',
                ),
                NooSegmentOption(
                  value: ThemeMode.dark,
                  icon: LucideIcons.moon,
                  label: 'Dark',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Bottom bar" row: same "label, then a full-width segmented control
/// below it" shape as [_ThemeRow] right above it. Attached is the original
/// edge-to-edge bar; floating insets it from both side/bottom edges with
/// rounded corners - see [NooBottomBarStyle]'s own doc comment for the
/// full visual rationale.
class _BottomBarStyleRow extends StatelessWidget {
  final SettingsController settings;

  const _BottomBarStyleRow({required this.settings});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.panelBottom, size: 20, color: colors.fg2),
                const SizedBox(width: 14),
                Text(
                  'Bottom bar',
                  style: NooText.bodyL.copyWith(color: colors.fg1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NooSegmentedControl<NooBottomBarStyle>(
              fill: true,
              value: settings.bottomBarStyle,
              onChanged: settings.setBottomBarStyle,
              options: const [
                NooSegmentOption(
                  value: NooBottomBarStyle.attached,
                  icon: LucideIcons.panelBottom,
                  label: 'Attached',
                ),
                NooSegmentOption(
                  value: NooBottomBarStyle.floating,
                  icon: LucideIcons.panelBottomOpen,
                  label: 'Floating',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Navigation menu" (Settings → Appearance): which widget opens hidden
/// tabs + Settings - the original `menu` icon that opens a left `Drawer`,
/// or the avatar button instead (opens `showAvatarMenu`, a dropdown
/// anchored under it) - see [NooNavMenuStyle]'s own doc comment for the
/// full reachability rationale (dropping the hamburger removes one of the
/// two top-corner targets the shell asks a thumb to reach, rather than
/// adding a third kind of chrome like a side rail would).
class _NavMenuStyleRow extends StatelessWidget {
  final SettingsController settings;

  const _NavMenuStyleRow({required this.settings});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.panelLeft, size: 20, color: colors.fg2),
                const SizedBox(width: 14),
                Text(
                  'Navigation menu',
                  style: NooText.bodyL.copyWith(color: colors.fg1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NooSegmentedControl<NooNavMenuStyle>(
              fill: true,
              value: settings.navMenuStyle,
              onChanged: settings.setNavMenuStyle,
              options: const [
                NooSegmentOption(
                  value: NooNavMenuStyle.drawer,
                  icon: LucideIcons.menu,
                  label: 'Hamburger',
                ),
                NooSegmentOption(
                  value: NooNavMenuStyle.avatarMenu,
                  icon: LucideIcons.userRound,
                  label: 'Avatar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FabStyleRow extends StatelessWidget {
  final SettingsController settings;

  const _FabStyleRow({required this.settings});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NooSpace.md,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.circlePlus, size: 20, color: colors.fg2),
                const SizedBox(width: 14),
                Text(
                  'Upload button size',
                  style: NooText.bodyL.copyWith(color: colors.fg1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NooSegmentedControl<FabStyle>(
              fill: true,
              value: settings.fabStyle,
              onChanged: settings.setFabStyle,
              options: const [
                NooSegmentOption(
                  value: FabStyle.auto,
                  icon: LucideIcons.wandSparkles,
                  label: 'Auto',
                ),
                NooSegmentOption(
                  value: FabStyle.mini,
                  icon: LucideIcons.minimize2,
                  label: 'Mini',
                ),
                NooSegmentOption(
                  value: FabStyle.expanded,
                  icon: LucideIcons.maximize2,
                  label: 'Expanded',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The current accent-color choice, shown as a small filled circle in the
/// "Accent color" row - a wallpaper icon when following the OS's dynamic
/// color instead of a fixed swatch.
class _AccentSwatchDot extends StatelessWidget {
  final Color? color;
  const _AccentSwatchDot({this.color});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? colors.surface3,
        shape: BoxShape.circle,
      ),
      child: color == null
          ? Icon(LucideIcons.wallpaper, size: 12, color: colors.fg2)
          : null,
    );
  }
}

void _openAccentPicker(BuildContext context, SettingsController settings) {
  Widget grid(NooColors colors) => Wrap(
    spacing: 14,
    runSpacing: 14,
    children: [
      _AccentSwatch(
        isSelected: settings.useDynamicColor,
        onTap: () {
          settings.setUseDynamicColor(true);
          Navigator.pop(context);
        },
        background: colors.surface3,
        child: Icon(LucideIcons.wallpaper, color: colors.fg2, size: 20),
      ),
      for (final color in AppTheme.seedColors)
        _AccentSwatch(
          isSelected: !settings.useDynamicColor && settings.seedColor == color,
          onTap: () {
            settings.setSeedColor(color);
            Navigator.pop(context);
          },
          background: color,
        ),
    ],
  );

  final colors = context.nooColors;
  if (NooLayout.isDesktop(context)) {
    showNooDialog(context, title: 'Accent color', children: [grid(colors)]);
  } else {
    showNooSheet(context, children: [grid(colors)]);
  }
}

class _AccentSwatch extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Color background;
  final Widget? child;

  const _AccentSwatch({
    required this.isSelected,
    required this.onTap,
    required this.background,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: colors.fg1, width: 3) : null,
        ),
        child: isSelected && child == null
            ? const Icon(LucideIcons.check, color: Colors.white, size: 20)
            : child,
      ),
    );
  }
}

void _openSeekBarPicker(BuildContext context, SettingsController settings) {
  Widget grid() => GridView.count(
    crossAxisCount: 2,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 1.35,
    children: [
      for (final style in MediaProgressBarStyle.values)
        _SeekBarStyleOption(
          style: style,
          isSelected: style == settings.mediaProgressBarStyle,
          onTap: () {
            settings.setMediaProgressBarStyle(style);
            Navigator.pop(context);
          },
        ),
    ],
  );

  if (NooLayout.isDesktop(context)) {
    showNooDialog(context, title: 'Seek bar style', children: [grid()]);
  } else {
    showNooSheet(context, children: [grid()]);
  }
}

class _SeekBarStyleOption extends StatelessWidget {
  final MediaProgressBarStyle style;
  final bool isSelected;
  final VoidCallback onTap;

  const _SeekBarStyleOption({
    required this.style,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Material(
      color: isSelected ? colors.accentSoft : colors.surface2,
      borderRadius: BorderRadius.circular(NooRadii.input),
      child: InkWell(
        borderRadius: BorderRadius.circular(NooRadii.input),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Center(
                  child: SizedBox(
                    width: 100,
                    height: 28,
                    child: SeekBarPreview(
                      style: style,
                      playedColor: isSelected ? colors.accentText : colors.fg2,
                      trackColor: colors.surface3,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _seekBarStyleLabel(style),
                style: NooText.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? colors.accentText : colors.fg1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
