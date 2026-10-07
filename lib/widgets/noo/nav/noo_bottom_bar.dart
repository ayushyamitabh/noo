import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_nav_style.dart';

export 'noo_nav_style.dart';

/// Android indicator geometry, shared between the sliding pill and each
/// item's own icon box so they line up exactly. Floating's own top offset
/// is shorter than attached's - its row is 16px shorter overall (64 vs 80)
/// and there's no edge-to-edge safe-area strip inside it eating into that.
const double _kAttachedPillTop = 14;
const double _kFloatingPillTop = 8;
const double _kAndroidPillWidth = 56;
const double _kAndroidPillHeight = 32;

/// The mobile bottom bar (DESIGN_SYSTEM.md 3, "Mobile"; `iNav`/`aNav` in
/// `Mobile Screen.dc.html`). Shows the 5 pinned tabs - which ones, and in
/// what order, is the caller's business; this only draws [destinations].
///
/// - [NooNavStyle.ios]: surface fill, 1px top `line`, a 50px row (8px top
///   padding) of icon 24 over a 10px selected label. Active: accent-text, 600.
///   Idle: centered fg-3 icon, no label. No ripple.
/// - [NooNavStyle.android]: surface fill, 80px. Every tab shows its 24px
///   icon over a 12px label (label only visible - not removed from layout,
///   so the row never resizes - once selected). The active icon sits in a
///   56x32 accent-soft pill that slides between tabs as selection moves,
///   rather than popping in/out on the destination item itself.
///
/// [NooBottomBarStyle.floating] ignores [style] and always uses the Android
/// row below, so iOS gets the same icon-only idle tabs.
///
/// [barStyle] (user-configurable in Settings, Appearance) picks between
/// that edge-to-edge [NooBottomBarStyle.attached] bar and
/// [NooBottomBarStyle.floating] - inset 16px from both side edges, 28px
/// corners, a 1px `line` border plus [nooDialogShadow] (the one shadow the
/// rest of the app allows itself, see that constant's own doc comment) so
/// it actually reads as floating above the content scrolling behind it.
/// Floating's Android row is both shorter (64 vs 80) and drops its idle
/// tabs' reserved label space - with no label to leave room for, an idle
/// icon just centers in the whole button, rather than sitting high with a
/// gap under it. The home indicator / gesture bar area below the row comes
/// from the bottom safe-area inset rather than a fixed 34/20px spacer, so
/// it's right on every device. Meant for `Scaffold.bottomNavigationBar` -
/// the host `Scaffold` needs `extendBody: true` while floating, and a
/// scrollable body needs enough trailing padding to clear the bar's own
/// footprint ([NooBottomBar.rowHeight] + [NooBottomBar.floatingBottomMargin]
/// + the bottom safe area) since nothing does that automatically once the
/// body draws behind it - see `tab_state_slivers.dart`'s
/// `bottomBarClearance`.
///
/// [frosted] (Settings, Appearance) swaps the solid `surface` fill for a
/// translucent one over a backdrop blur, on both bar styles and both nav
/// styles, and drops [nooDialogShadow] (a shadow would show through the
/// glass). It only reads as glass if content draws behind the bar, so the
/// host `Scaffold` needs `extendBody: true` and each scrollable body needs
/// the same trailing clearance floating does - see [drawsBehindBody].
///
/// [searchDestination]/[onSearchTap] (set together, from Settings'
/// "Search in bottom bar" - see `DESIGN_SYSTEM.md`'s floating bottom bar
/// entry) add a Search entry that's never highlighted (tapping it pushes
/// `SearchView`, it doesn't select anything) - the row's last item when
/// attached, or its own satellite circle beside the bar when floating,
/// always fully round regardless of the bar's own corner radius.
class NooBottomBar extends StatelessWidget {
  final NooNavStyle style;
  final NooBottomBarStyle barStyle;
  final bool frosted;

  /// Backdrop blur sigma and surface-fill opacity while [frosted] (user-
  /// adjustable in Settings; the defaults match [FrostedGlassContainer]'s
  /// blur).
  final double frostedBlur;
  final double frostedOpacity;
  final List<NooNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final NooNavDestination? searchDestination;
  final VoidCallback? onSearchTap;

  /// Bottom-avatar navigation occupies this slot while closed. Search moves
  /// from the row into the slot as the avatar expands into its popup.
  final Widget? avatarSatellite;
  final double avatarMenuProgress;

  const NooBottomBar({
    super.key,
    required this.style,
    this.barStyle = NooBottomBarStyle.attached,
    this.frosted = false,
    this.frostedBlur = defaultFrostedBlur,
    this.frostedOpacity = defaultFrostedOpacity,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.searchDestination,
    this.onSearchTap,
    this.avatarSatellite,
    this.avatarMenuProgress = 0,
  });

  /// The row height [build] draws for [style]/[barStyle] - exposed so a
  /// scrollable body sharing the same `Scaffold` can reserve exactly this
  /// much clearance (see the class doc comment) instead of guessing.
  static double rowHeight(NooNavStyle style, NooBottomBarStyle barStyle) {
    if (style == NooNavStyle.ios && barStyle != NooBottomBarStyle.floating) {
      return 50;
    }
    return barStyle == NooBottomBarStyle.floating ? 64 : 80;
  }

  static const double defaultFrostedBlur = 20;
  static const double defaultFrostedOpacity = 0.72;

  /// Whether the host `Scaffold` must draw its body behind the bar
  /// (`extendBody`) - true for floating (its transparent margin) and for any
  /// frosted bar (there's nothing to blur otherwise).
  static bool drawsBehindBody(NooBottomBarStyle barStyle, bool frosted) =>
      frosted || barStyle == NooBottomBarStyle.floating;

  /// Gap between the floating bar's bottom edge and the safe area below it
  /// (itself inside the [SafeArea] that consumes the actual device inset).
  static const double floatingBottomMargin = 12;

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final floating = barStyle == NooBottomBarStyle.floating;
    // Floating always gets the Android row (icon-only idle tabs, sliding
    // pill) - iOS's icon-over-label row doesn't fit a pill that short.
    final ios = style == NooNavStyle.ios && !floating;
    final hasSearch = searchDestination != null && onSearchTap != null;
    // Attached folds Search into the row itself (last item); floating
    // gives it a separate satellite circle instead (built below), so the
    // row builders only ever see it as a trailing item in the former case.
    final rowSearch =
        hasSearch &&
            (!floating || avatarSatellite != null) &&
            (avatarSatellite == null || !floating || avatarMenuProgress < 1)
        ? searchDestination
        : null;

    final row = ios
        ? _buildIosRow(trailingSearch: rowSearch)
        : _buildAndroidRow(
            colors,
            floating: floating,
            trailingSearch: rowSearch,
          );
    final barHeight = NooBottomBar.rowHeight(style, barStyle);

    if (floating) {
      final pillRadius = BorderRadius.circular(28);
      final pillBox = Container(
        height: barHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _fill(colors),
          border: Border.all(color: colors.line),
          borderRadius: pillRadius,
          boxShadow: frosted ? null : const [nooDialogShadow],
        ),
        child: row,
      );
      final pill = frosted
          ? _blurred(pillBox, pillRadius, frostedBlur)
          : pillBox;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            NooBottomBar.floatingBottomMargin,
          ),
          child: avatarSatellite != null
              ? _withAvatar(pill, barHeight, hasSearch)
              : hasSearch
              // A fixed-height SizedBox, not just a Row with
              // crossAxisAlignment.stretch - the bottomNavigationBar slot
              // gives this widget a *loose* (unbounded-max) height
              // constraint, and stretch on an unbounded cross axis blows up
              // to fill the screen in profile/release (the assertion that
              // would catch it in debug is stripped there) - the same
              // silent-oversizing bug files_controls_row.dart hit earlier
              // from a different cause. Both children already size
              // themselves explicitly (pill's own `height`, the
              // satellite's `size`), so stretch was never actually needed.
              ? SizedBox(
                  height: barHeight,
                  child: Row(
                    children: [
                      Expanded(child: pill),
                      const SizedBox(width: 8),
                      _SearchSatellite(
                        destination: searchDestination!,
                        onTap: onSearchTap!,
                        size: barHeight,
                        frosted: frosted,
                        frostedBlur: frostedBlur,
                        frostedOpacity: frostedOpacity,
                      ),
                    ],
                  ),
                )
              : pill,
        ),
      );
    }

    final bar = Container(
      decoration: BoxDecoration(
        color: _fill(colors),
        border: ios ? Border(top: BorderSide(color: colors.line)) : null,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: barHeight,
          child: avatarSatellite == null
              ? row
              : Row(
                  children: [
                    Expanded(child: row),
                    SizedBox(
                      width: barHeight,
                      height: barHeight,
                      child: avatarSatellite,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),
        ),
      ),
    );
    return frosted ? _blurred(bar, BorderRadius.zero, frostedBlur) : bar;
  }

  Widget _withAvatar(Widget rail, double height, bool hasSearch) {
    final satelliteWidth = hasSearch
        ? height
        : height * (1 - avatarMenuProgress);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          Expanded(child: rail),
          SizedBox(width: 8 * (hasSearch ? 1 : 1 - avatarMenuProgress)),
          SizedBox(
            width: satelliteWidth,
            height: height,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerRight,
                minWidth: height,
                maxWidth: height,
                child: Stack(
                  children: [
                    avatarSatellite!,
                    if (hasSearch && avatarMenuProgress > 0)
                      Opacity(
                        opacity: avatarMenuProgress,
                        child: _SearchSatellite(
                          destination: searchDestination!,
                          onTap: onSearchTap!,
                          size: height,
                          frosted: frosted,
                          frostedBlur: frostedBlur,
                          frostedOpacity: frostedOpacity,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _fill(NooColors colors) => frosted
      ? colors.surface.withValues(alpha: frostedOpacity)
      : colors.surface;

  double get _rowSearchFraction =>
      avatarSatellite == null || barStyle == NooBottomBarStyle.attached
      ? 1
      : 1 - avatarMenuProgress;

  Widget _searchRowItem(Widget child, double width) => SizedBox(
    width: width * _rowSearchFraction,
    child: IgnorePointer(
      ignoring: _rowSearchFraction < .95,
      child: ClipRect(
        child: OverflowBox(
          minWidth: width,
          maxWidth: width,
          child: Opacity(opacity: _rowSearchFraction, child: child),
        ),
      ),
    ),
  );

  Widget _buildIosRow({NooNavDestination? trailingSearch}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth /
            (destinations.length +
                (trailingSearch == null ? 0 : _rowSearchFraction));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < destinations.length; i++)
              SizedBox(
                width: width,
                child: _IosItem(
                  destination: destinations[i],
                  selected: i == selectedIndex,
                  selectedLabelOnly: true,
                  onTap: () => onSelected(i),
                ),
              ),
            if (trailingSearch != null)
              _searchRowItem(
                _IosItem(
                  destination: trailingSearch,
                  selected: false,
                  selectedLabelOnly: true,
                  onTap: onSearchTap!,
                ),
                width,
              ),
          ],
        );
      },
    );
  }

  Widget _buildAndroidRow(
    NooColors colors, {
    required bool floating,
    NooNavDestination? trailingSearch,
  }) {
    final pillTop = floating ? _kFloatingPillTop : _kAttachedPillTop;
    final itemCount =
        destinations.length + (trailingSearch != null ? _rowSearchFraction : 0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / itemCount;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: NooMotion.base,
              curve: NooMotion.ease,
              top: pillTop,
              left:
                  itemWidth * selectedIndex +
                  (itemWidth - _kAndroidPillWidth) / 2,
              width: _kAndroidPillWidth,
              height: _kAndroidPillHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accentSoft,
                  borderRadius: BorderRadius.circular(NooRadii.pill),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < destinations.length; i++)
                  SizedBox(
                    width: itemWidth,
                    child: _AndroidItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      floating: floating,
                      onTap: () => onSelected(i),
                    ),
                  ),
                if (trailingSearch != null)
                  _searchRowItem(
                    _AndroidItem(
                      destination: trailingSearch,
                      selected: false,
                      floating: floating,
                      onTap: onSearchTap!,
                    ),
                    itemWidth,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Clips [child] to [radius] and blurs whatever is drawn behind it - the
/// frosted bar's backdrop. [child] supplies the translucent fill on top.
Widget _blurred(Widget child, BorderRadius radius, double sigma) => ClipRRect(
  borderRadius: radius,
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  ),
);

/// The floating bar's own Search entry point, next to the pill rather than
/// inside it - always fully round (see [NooBottomBar]'s doc comment),
/// same fill/border as the pill so the two still read as one family.
class _SearchSatellite extends StatelessWidget {
  final NooNavDestination destination;
  final VoidCallback onTap;
  final double size;
  final bool frosted;
  final double frostedBlur;
  final double frostedOpacity;

  const _SearchSatellite({
    required this.destination,
    required this.onTap,
    required this.size,
    required this.frosted,
    required this.frostedBlur,
    required this.frostedOpacity,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Semantics(
      button: true,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _satelliteBody(colors),
      ),
    );
  }

  Widget _satelliteBody(NooColors colors) {
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: frosted
            ? colors.surface.withValues(alpha: frostedOpacity)
            : colors.surface,
        border: Border.all(color: colors.line),
        shape: BoxShape.circle,
        boxShadow: frosted ? null : const [nooDialogShadow],
      ),
      child: Icon(destination.icon, size: 24, color: colors.fg1),
    );
    return frosted
        ? _blurred(disc, BorderRadius.circular(size / 2), frostedBlur)
        : disc;
  }
}

class _IosItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final bool selectedLabelOnly;
  final VoidCallback onTap;

  const _IosItem({
    required this.destination,
    required this.selected,
    this.selectedLabelOnly = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final fg = selected ? colors.accentText : colors.fg3;
    return Semantics(
      button: true,
      selected: selected,
      label: selectedLabelOnly && !selected ? destination.label : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: selectedLabelOnly && !selected
            ? Center(child: Icon(destination.icon, size: 24, color: fg))
            : Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Icon(destination.icon, size: 24, color: fg),
                    const SizedBox(height: 4),
                    Text(
                      destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.navLabel.copyWith(
                        fontSize: 10,
                        height: 1,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Icon (over the shared sliding pill, drawn separately by [NooBottomBar])
/// with its label below it. Attached always reserves the label's space
/// (just invisible when idle, per [_kAttachedPillTop]'s doc comment on
/// [NooBottomBar]) so the icon never shifts vertically as selection
/// changes. Floating drops that reserved space when idle instead: there's
/// no label to leave room for, so the icon centers in the whole button and
/// renders a touch bigger.
class _AndroidItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final bool floating;
  final VoidCallback onTap;

  const _AndroidItem({
    required this.destination,
    required this.selected,
    required this.floating,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final iconColor = selected ? colors.accentText : colors.fg2;

    final Widget content;
    if (floating && !selected) {
      content = Center(
        child: Icon(destination.icon, size: 25, color: iconColor),
      );
    } else {
      content = Padding(
        padding: EdgeInsets.only(
          top: floating ? _kFloatingPillTop : _kAttachedPillTop,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            SizedBox(
              height: _kAndroidPillHeight,
              child: Center(
                child: Icon(destination.icon, size: 24, color: iconColor),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              duration: NooMotion.base,
              curve: NooMotion.ease,
              opacity: selected ? 1 : 0,
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.navLabelActive.copyWith(
                  height: 1,
                  color: colors.fg1,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}
