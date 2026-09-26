import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_segmented_control.dart';
import '../noo/core/noo_toggle.dart';
import '../noo/lists/noo_settings_row.dart';
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
/// color, AMOLED and the video seek-bar style are all settings that predate
/// the design system and have no place in it (a single fixed accent, no
/// per-user color choice). They still work, just demoted into a separate
/// "Advanced appearance" group beneath the main card per the rebuild brief,
/// rather than dropped - see the handoff report for whether to remove them
/// outright.
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
          children: [
            NooSettingsRow(
              icon: LucideIcons.sunMoon,
              label: const Text('Theme'),
              trailing: NooSegmentedControl<ThemeMode>(
                size: NooSegmentedSize.sm,
                value: settings.themeMode,
                onChanged: settings.setThemeMode,
                options: const [
                  NooSegmentOption(value: ThemeMode.system, icon: LucideIcons.monitor, label: 'System'),
                  NooSegmentOption(value: ThemeMode.light, icon: LucideIcons.sun, label: 'Light'),
                  NooSegmentOption(value: ThemeMode.dark, icon: LucideIcons.moon, label: 'Dark'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: NooSpace.xl),
        SettingsSection(
          title: 'Advanced appearance',
          children: [
            NooSettingsRow(
              icon: LucideIcons.palette,
              label: const Text('Accent color'),
              subtitle: Text(settings.useDynamicColor ? 'Matching your wallpaper' : 'Custom color'),
              trailing: _AccentSwatchDot(color: settings.useDynamicColor ? null : settings.seedColor),
              onTap: () => _openAccentPicker(context, settings),
            ),
            NooSettingsRow(
              icon: LucideIcons.sparkles,
              label: const Text('AMOLED black'),
              subtitle: const Text('Use pure black backgrounds in dark mode'),
              trailing: NooToggle(checked: settings.amoledDark, onChanged: settings.setAmoledDark),
            ),
            NooSettingsRow(
              icon: LucideIcons.waves,
              label: const Text('Seek bar style'),
              subtitle: const Text('The progress bar style used when playing videos'),
              value: _seekBarStyleLabel(settings.mediaProgressBarStyle),
              onTap: () => _openSeekBarPicker(context, settings),
            ),
          ],
        ),
      ],
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
      child: color == null ? Icon(LucideIcons.wallpaper, size: 12, color: colors.fg2) : null,
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

  const _SeekBarStyleOption({required this.style, required this.isSelected, required this.onTap});

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
