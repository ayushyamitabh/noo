import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/nav_preset.dart';
import '../../providers/settings_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/nav/noo_floating_shadow.dart';
import '../noo/nav/noo_nav_style.dart';

/// "Layout" in Settings -> Appearance: the navigation presets as a grid of
/// small previews. Picking one applies a whole set of bar/menu options at once
/// ([NavPreset.apply]); the individual options live one level deeper under
/// "Navigation & bottom bar".
class SettingsNavPresets extends StatelessWidget {
  const SettingsNavPresets({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final colors = context.nooColors;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.all(NooSpace.sm),
        // Two cards per row, each pair the same height (descriptions differ
        // in length), rather than a Wrap of ragged cards.
        child: Column(
          children: [
            for (var i = 0; i < NavPreset.values.length; i += 2) ...[
              if (i > 0) const SizedBox(height: NooSpace.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = i; j < i + 2; j++) ...[
                      if (j > i) const SizedBox(width: NooSpace.sm),
                      Expanded(
                        child: j < NavPreset.values.length
                            ? _PresetCard(
                                preset: NavPreset.values[j],
                                selected: NavPreset.values[j].matches(settings),
                                onTap: () =>
                                    NavPreset.values[j].apply(settings),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final NavPreset preset;
  final bool selected;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(NooRadii.card);
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.label}. ${preset.description}',
      child: Material(
        color: colors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: selected ? colors.accent : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(NooSpace.xs + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(NooRadii.input),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: NavPresetPreview(preset: preset),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.fg1,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        LucideIcons.circleCheck,
                        size: 18,
                        color: colors.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  preset.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A drawn miniature of the app's chrome for [preset]: the top bar (menu,
/// title, search, avatar - wherever the preset puts them), a few list rows, and
/// the bottom bar in its style (attached strip, floating pill, compact
/// capsule, full-width dock; labelled or icon-only; solid, blurred or glass),
/// with Search and the avatar inside or beside it. A sketch, not the real bar -
/// the live preview under "Navigation & bottom bar" is that - but built from
/// the preset's own values so the differences between presets are what's drawn.
class NavPresetPreview extends StatelessWidget {
  final NavPreset preset;

  const NavPresetPreview({super.key, required this.preset});

  static const _icons = [
    LucideIcons.folder,
    LucideIcons.images,
    LucideIcons.star,
    LucideIcons.activity,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return ColoredBox(
      color: colors.bg,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Everything is sized in units of 1% of the preview's width.
          final u = constraints.maxWidth / 100;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              ..._content(colors, u),
              _topBar(colors, u),
              ..._bottomBar(context, colors, u),
            ],
          );
        },
      ),
    );
  }

  Widget _block(
    double w,
    double h,
    Color color, {
    double? radius,
    double alpha = 1,
  }) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: color.withValues(alpha: alpha),
      borderRadius: BorderRadius.circular(radius ?? h / 2),
    ),
  );

  Widget _topBar(NooColors colors, double u) {
    final avatarTop = !preset.avatarAtBottom;
    return Positioned(
      left: 4 * u,
      right: 4 * u,
      top: 4 * u,
      height: 9 * u,
      child: Row(
        children: [
          if (preset.navMenu == NooNavMenuStyle.drawer) ...[
            Icon(LucideIcons.menu, size: 5 * u, color: colors.fg2),
            SizedBox(width: 2 * u),
          ],
          _block(13 * u, 3 * u, colors.fg1, alpha: .8),
          SizedBox(width: 3 * u),
          Expanded(
            child: preset.searchInBar
                ? const SizedBox.shrink()
                : Container(
                    height: 7 * u,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(7 * u),
                    ),
                  ),
          ),
          if (preset.searchInBar) const Spacer(),
          if (avatarTop) ...[SizedBox(width: 3 * u), _avatar(colors, 7 * u)],
        ],
      ),
    );
  }

  Widget _avatar(NooColors colors, double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colors.accent.withValues(alpha: .35),
    ),
    child: Icon(LucideIcons.user, size: size * .55, color: colors.accentText),
  );

  List<Widget> _content(NooColors colors, double u) => [
    // Frosted/glass bars show what's behind them: a colourful band under the
    // bar stands in for a photo, so the translucency actually reads.
    if (preset.frosted)
      Positioned(
        left: 4 * u,
        right: 4 * u,
        top: 70 * u,
        bottom: 0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.vertical(top: Radius.circular(3 * u)),
            gradient: LinearGradient(
              colors: [
                colors.accent.withValues(alpha: .75),
                const Color(0xFF12C7B5).withValues(alpha: .75),
                const Color(0xFFFF7A59).withValues(alpha: .75),
              ],
            ),
          ),
        ),
      ),
    for (var i = 0; i < 5; i++)
      Positioned(
        left: 4 * u,
        right: 4 * u,
        top: (17 + i * 14) * u,
        height: 11 * u,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 3 * u),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(3 * u),
          ),
          child: Row(
            children: [
              _block(
                6 * u,
                6 * u,
                [
                  colors.accent,
                  colors.fg3,
                  colors.danger,
                  colors.accent,
                  colors.fg3,
                ][i],
                radius: 1.6 * u,
                alpha: .35,
              ),
              SizedBox(width: 3 * u),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(26 * u, 2 * u, colors.fg1, alpha: .7),
                  SizedBox(height: 1.4 * u),
                  _block(16 * u, 1.6 * u, colors.fg3, alpha: .6),
                ],
              ),
            ],
          ),
        ),
      ),
  ];

  /// The tab slots: icons (the first selected), plus Search and the avatar
  /// when the preset folds them into the bar itself.
  Widget _slots(
    NooColors colors,
    double u, {
    required bool search,
    required bool avatar,
    required bool labels,
    required bool inline,
    double? slotWidth,
  }) {
    Widget tab(int i) {
      final on = i == 0;
      final glyph = Icon(
        _icons[i],
        size: 4.6 * u,
        color: on ? colors.accentText : colors.fg2,
      );
      if (on && inline) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 3 * u, vertical: 1.6 * u),
          decoration: BoxDecoration(
            color: colors.accentSoft,
            borderRadius: BorderRadius.circular(8 * u),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              glyph,
              SizedBox(width: 1.6 * u),
              _block(8 * u, 1.8 * u, colors.accentText, alpha: .9),
            ],
          ),
        );
      }
      final pill = Container(
        padding: EdgeInsets.symmetric(horizontal: 3 * u, vertical: 1.2 * u),
        decoration: BoxDecoration(
          color: on ? colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(5 * u),
        ),
        child: glyph,
      );
      if (!labels) return pill;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pill,
          SizedBox(height: .8 * u),
          _block(
            6 * u,
            1.4 * u,
            on ? colors.fg1 : colors.fg3,
            alpha: on ? .9 : .5,
          ),
        ],
      );
    }

    // Scale down rather than overflow when a preview is drawn very small; the
    // selected tab gets extra width when it also carries its label.
    Widget slot(Widget child, {int flex = 2}) {
      final fitted = FittedBox(fit: BoxFit.scaleDown, child: child);
      return slotWidth == null
          ? Expanded(
              flex: flex,
              child: Center(child: fitted),
            )
          : SizedBox(
              width: slotWidth,
              child: Center(child: fitted),
            );
    }

    return Row(
      children: [
        for (var i = 0; i < 4; i++)
          slot(tab(i), flex: i == 0 && inline ? 3 : 2),
        if (search)
          slot(Icon(LucideIcons.search, size: 4.6 * u, color: colors.fg2)),
        if (avatar) slot(_avatar(colors, 6 * u)),
      ],
    );
  }

  /// A round satellite beside the bar (Search or the avatar).
  Widget _satellite(
    NooColors colors,
    double u,
    double size,
    Color fill,
    Widget child,
  ) => NooFloatingShadow(
    radius: BorderRadius.circular(size / 2),
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: child,
    ),
  );

  List<Widget> _bottomBar(BuildContext context, NooColors colors, double u) {
    final floating = preset.barStyle == NooBottomBarStyle.floating;
    final compact = preset.iconOnly && !preset.fullWidth;
    // Solid, blurred (a translucent fill) or glass (more transparent, with a
    // soft sheen standing in for the refractive rim).
    final fill = !preset.frosted
        ? colors.surface
        : colors.surface.withValues(
            alpha: preset.glassStyle == GlassStyle.glass ? .5 : .72,
          );
    final sheen = preset.frosted && preset.glassStyle == GlassStyle.glass;

    if (!floating) {
      // Edge-to-edge strip.
      return [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 17 * u,
          child: Container(
            padding: EdgeInsets.only(bottom: 2 * u),
            decoration: BoxDecoration(
              color: fill,
              border: Border(
                top: BorderSide(color: colors.line, width: .6 * u),
              ),
            ),
            child: _slots(
              colors,
              u,
              search: preset.searchInBar,
              avatar: preset.avatarAtBottom,
              labels: !preset.iconOnly,
              inline: false,
            ),
          ),
        ),
      ];
    }

    final barHeight = (preset.iconOnly ? 12 : 14) * u;
    const margin = 4.0;
    final radius = BorderRadius.circular(barHeight / 2);
    Widget pill({required Widget child, double? width}) => NooFloatingShadow(
      radius: radius,
      child: Container(
        width: width,
        height: barHeight,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: radius,
          gradient: sheen
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: .35),
                    Colors.white.withValues(alpha: 0),
                    Colors.white.withValues(alpha: .15),
                  ],
                )
              : null,
        ),
        child: child,
      ),
    );

    if (compact) {
      // Everything inside one small centred capsule.
      final slots =
          4 + (preset.searchInBar ? 1 : 0) + (preset.avatarAtBottom ? 1 : 0);
      final slotWidth = 8 * u;
      return [
        Positioned(
          left: 0,
          right: 0,
          bottom: margin * u,
          child: Center(
            child: pill(
              width: slots * slotWidth + 3 * u,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.5 * u),
                child: _slots(
                  colors,
                  u,
                  search: preset.searchInBar,
                  avatar: preset.avatarAtBottom,
                  labels: false,
                  inline: false,
                  slotWidth: slotWidth,
                ),
              ),
            ),
          ),
        ),
      ];
    }

    // A pill across the screen, with Search / the avatar as round satellites
    // beside it.
    final satellites = <Widget>[
      if (preset.searchInBar)
        _satellite(
          colors,
          u,
          barHeight,
          fill,
          Icon(LucideIcons.search, size: 5 * u, color: colors.fg1),
        ),
      if (preset.avatarAtBottom)
        _satellite(colors, u, barHeight, fill, _avatar(colors, 7 * u)),
    ];
    return [
      Positioned(
        left: margin * u,
        right: margin * u,
        bottom: margin * u,
        height: barHeight,
        child: Row(
          children: [
            Expanded(
              child: pill(
                child: _slots(
                  colors,
                  u,
                  search: false,
                  avatar: false,
                  labels: false,
                  inline: preset.inlineLabel && !preset.iconOnly,
                ),
              ),
            ),
            for (final s in satellites) ...[SizedBox(width: 2 * u), s],
          ],
        ),
      ),
    ];
  }
}
