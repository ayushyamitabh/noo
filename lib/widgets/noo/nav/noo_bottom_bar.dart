import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../../glass_backdrop.dart';
import 'noo_floating_shadow.dart';
import 'noo_nav_style.dart';
import 'noo_search_hero.dart';

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
/// corners, no border: a soft two-layer drop shadow ([NooFloatingShadow])
/// is what lifts it off the content scrolling behind it, on the bar and on
/// its round satellites alike.
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
/// styles. The floating bar keeps its drop shadow ([NooFloatingShadow] paints
/// it only outside the shape, so it doesn't show through the glass). It only
/// reads as glass if content draws behind the bar, so the
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

  /// Settings, Appearance, "Icon-only bottom bar": no labels at all (not even
  /// the selected tab's), a shorter row, selection shown by the pill/accent.
  final bool iconOnly;

  /// Floating only (Settings, Appearance, "Label beside active icon"): the
  /// active tab widens into a pill holding its icon *and* label side by
  /// side ([_InlineLabelRow]); idle tabs are icon-only. Ignored while
  /// attached, [iconOnly], or when Search sits inside the row.
  final bool inlineLabel;

  /// With [iconOnly]: stretch across the bar's normal width instead of
  /// shrinking to a pill around the icons. The compact pill also takes
  /// Search and a bottom avatar inside it rather than beside it.
  final bool fullWidth;

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

  /// Wraps the Search entry in the shared [NooSearchHero] so it morphs into
  /// `SearchView`'s bottom search field (and back). Only the real shell bar
  /// sets this: a second bar on screen (Settings' previews) would put two
  /// heroes with one tag in the same route.
  final bool searchHero;

  /// Bottom-avatar navigation occupies this slot while closed. Search moves
  /// from the row into the slot as the avatar expands into its popup.
  final Widget? avatarSatellite;
  final double avatarMenuProgress;

  const NooBottomBar({
    super.key,
    required this.style,
    this.barStyle = NooBottomBarStyle.attached,
    this.frosted = false,
    this.iconOnly = false,
    this.inlineLabel = false,
    this.fullWidth = true,
    this.frostedBlur = defaultFrostedBlur,
    this.frostedOpacity = defaultFrostedOpacity,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.searchDestination,
    this.onSearchTap,
    this.searchHero = false,
    this.avatarSatellite,
    this.avatarMenuProgress = 0,
  });

  /// The row height [build] draws for [style]/[barStyle] - exposed so a
  /// scrollable body sharing the same `Scaffold` can reserve exactly this
  /// much clearance (see the class doc comment) instead of guessing.
  static double rowHeight(
    NooNavStyle style,
    NooBottomBarStyle barStyle, {
    bool iconOnly = false,
  }) {
    if (style == NooNavStyle.ios && barStyle != NooBottomBarStyle.floating) {
      return 50;
    }
    if (iconOnly) return iconOnlyHeight;
    return barStyle == NooBottomBarStyle.floating ? 64 : 80;
  }

  /// The compact icon-only pill: its height, and each icon's slot width.
  static const double iconOnlyHeight = 56;
  static const double iconOnlyItemWidth = 52;
  static const double _iconOnlyPillWidth = 44;
  static const double _iconOnlyPillHeight = 36;

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

  /// Icon-only, shrunk to its icons (see [fullWidth]).
  bool get _compact => iconOnly && !fullWidth;

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
            (_compact ||
                ((!floating || avatarSatellite != null) &&
                    (avatarSatellite == null ||
                        !floating ||
                        avatarMenuProgress < 1)))
        ? searchDestination
        : null;

    final barHeight = NooBottomBar.rowHeight(
      style,
      barStyle,
      iconOnly: iconOnly,
    );
    final Widget row = floating && inlineLabel && !iconOnly && rowSearch == null
        ? _InlineLabelRow(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
            pillHeight: barHeight - 24,
          )
        : ios
        ? _buildIosRow(trailingSearch: rowSearch)
        : _buildAndroidRow(
            colors,
            floating: floating,
            trailingSearch: rowSearch,
          );

    if (floating) {
      final mergedAvatar = _compact && avatarSatellite != null;
      final pillRadius = BorderRadius.circular(28);
      final pillBox = Container(
        height: barHeight,
        // Icon-only: exactly wide enough for its icons (plus 4px inner
        // padding each side), centred by the wrapper below.
        width: _compact
            ? (destinations.length +
                          (rowSearch != null ? _rowSearchFraction : 0) +
                          (mergedAvatar ? 1 : 0)) *
                      iconOnlyItemWidth +
                  10
            : null,
        padding: _compact ? const EdgeInsets.symmetric(horizontal: 4) : null,
        clipBehavior: Clip.antiAlias,
        // No border: the floating bar is separated from the content by its
        // drop shadow ([NooFloatingShadow], wrapped around it below).
        decoration: BoxDecoration(
          color: _fill(context, colors),
          borderRadius: pillRadius,
        ),
        child: mergedAvatar
            ? Row(
                children: [
                  SizedBox(
                    width:
                        (destinations.length +
                            (rowSearch != null ? _rowSearchFraction : 0)) *
                        iconOnlyItemWidth,
                    child: row,
                  ),
                  SizedBox(
                    width: iconOnlyItemWidth,
                    child: Center(child: avatarSatellite),
                  ),
                ],
              )
            : row,
      );
      final pillCore = NooFloatingShadow(
        radius: pillRadius,
        child: frosted ? _blurred(pillBox, pillRadius, frostedBlur) : pillBox,
      );
      // Fixed height: the bottomNavigationBar slot is loose, and a bare Center
      // would grow to fill the whole screen height (see the SizedBox note on
      // the search-satellite row below).
      final pill = _compact
          ? SizedBox(
              height: barHeight,
              child: Center(child: pillCore),
            )
          : pillCore;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            NooBottomBar.floatingBottomMargin,
          ),
          child: _compact
              ? pill
              : avatarSatellite != null
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
                        hero: searchHero,
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
        color: _fill(context, colors),
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
              // The slot's own bounds would crop the satellites' drop
              // shadow into a visible square: let it spill vertically
              // always, and sideways once the slot is fully open (it only
              // needs cropping while its width animates).
              clipper: _ShadowRoomClipper(spillSides: satelliteWidth >= height),
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
                          hero: searchHero && avatarMenuProgress >= 1,
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

  Color _fill(BuildContext context, NooColors colors) => frosted
      ? GlassBackdrop.fillColor(context, colors.surface, frostedOpacity)
      : colors.surface;

  double get _rowSearchFraction =>
      _compact ||
          avatarSatellite == null ||
          barStyle == NooBottomBarStyle.attached
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
          child: Opacity(
            opacity: _rowSearchFraction,
            // Only while fully in the row: mid avatar-menu animation the
            // search button is also (partly) the satellite, and two heroes
            // can't share a tag.
            child: searchHero && _rowSearchFraction >= 1
                ? NooSearchHero(child: child)
                : child,
          ),
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
                  iconOnly: iconOnly,
                  onTap: () => onSelected(i),
                ),
              ),
            if (trailingSearch != null)
              _searchRowItem(
                _IosItem(
                  destination: trailingSearch,
                  selected: false,
                  selectedLabelOnly: true,
                  iconOnly: iconOnly,
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
    final pillTop = iconOnly
        ? (NooBottomBar.iconOnlyHeight - NooBottomBar._iconOnlyPillHeight) / 2
        : floating
        ? _kFloatingPillTop
        : _kAttachedPillTop;
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
                  (itemWidth -
                          (iconOnly
                              ? NooBottomBar._iconOnlyPillWidth
                              : _kAndroidPillWidth)) /
                      2,
              width: iconOnly
                  ? NooBottomBar._iconOnlyPillWidth
                  : _kAndroidPillWidth,
              height: iconOnly
                  ? NooBottomBar._iconOnlyPillHeight
                  : _kAndroidPillHeight,
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
                      iconOnly: iconOnly,
                      onTap: () => onSelected(i),
                    ),
                  ),
                if (trailingSearch != null)
                  _searchRowItem(
                    _AndroidItem(
                      destination: trailingSearch,
                      selected: false,
                      floating: floating,
                      iconOnly: iconOnly,
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

/// A [ClipRect] clipper that keeps a satellite's drop shadow: the child's own
/// bounds plus generous room above/below (and to the sides when
/// [spillSides]).
class _ShadowRoomClipper extends CustomClipper<Rect> {
  final bool spillSides;

  const _ShadowRoomClipper({required this.spillSides});

  @override
  Rect getClip(Size size) {
    const room = 80.0;
    final side = spillSides ? room : 0.0;
    return Rect.fromLTRB(-side, -room, size.width + side, size.height + room);
  }

  @override
  bool shouldReclip(_ShadowRoomClipper old) => old.spillSides != spillSides;
}

/// Clips [child] to [radius] and blurs whatever is drawn behind it - the
/// frosted bar's backdrop. [child] supplies the translucent fill on top.
Widget _blurred(Widget child, BorderRadius radius, double sigma) =>
    GlassBackdrop(radius: radius, sigma: sigma, child: child);

/// Horizontal padding inside [_InlineLabelRow]'s active pill, the gap
/// between its icon and label, and the narrowest an idle tab may get
/// (still a comfortable tap target) before the active label truncates.
const double _kInlinePillPadding = 14;
const double _kInlineIconGap = 8;
const double _kInlineMinIdleWidth = 48;

/// [NooBottomBar.inlineLabel]'s row. Tab widths aren't equal: the active
/// tab gets exactly what its pill needs (measured label, capped so every
/// idle tab keeps at least [_kInlineMinIdleWidth]), the rest split what's
/// left. Each tab's width animates with [AnimatedContainer] - every tab
/// shares one duration/curve and starts together, so the widths keep
/// summing to the row's width on every frame, and the whole width of each
/// tab stays tappable (no dead gaps between icons).
class _InlineLabelRow extends StatefulWidget {
  final List<NooNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double pillHeight;

  const _InlineLabelRow({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.pillHeight,
  });

  @override
  State<_InlineLabelRow> createState() => _InlineLabelRowState();
}

class _InlineLabelRowState extends State<_InlineLabelRow> {
  // The active label's real laid-out width, read off an offstage copy of the
  // very same Text (see build). A TextPainter measured up front used the
  // fallback font's metrics until the web font finished loading and left
  // the pill a few px too narrow, fading the label's last letter - the
  // offstage Text re-lays out when the font arrives, and its
  // SizeChangedLayoutNotifier tells us to re-read it.
  final _measureKey = GlobalKey();
  double? _labelWidth;

  static TextStyle _labelStyle(Color color) =>
      NooText.navLabelActive.copyWith(height: 1, color: color);

  @override
  void initState() {
    super.initState();
    _scheduleRead();
  }

  @override
  void didUpdateWidget(_InlineLabelRow old) {
    super.didUpdateWidget(old);
    _scheduleRead();
  }

  void _scheduleRead() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _measureKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      if (box.size.width != _labelWidth) {
        setState(() => _labelWidth = box.size.width);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final destinations = widget.destinations;
    final selectedIndex = widget.selectedIndex;
    final count = destinations.length;
    if (count == 0) return const SizedBox.shrink();
    final hasSelection = selectedIndex >= 0 && selectedIndex < count;
    final labelStyle = _labelStyle(colors.accentText);

    final row = LayoutBuilder(
      builder: (context, constraints) {
        final total = constraints.maxWidth;
        var activeWidth = 0.0;
        if (hasSelection) {
          final wanted =
              _kInlinePillPadding * 2 +
              24 +
              _kInlineIconGap +
              (_labelWidth ?? 40).ceilToDouble() +
              // The pill's own 4px inset from the tab edge, both sides.
              8;
          final cap = count == 1
              ? total
              : total - (count - 1) * _kInlineMinIdleWidth;
          activeWidth = wanted.clamp(0, cap < 0 ? 0 : cap).toDouble();
        }
        final idleWidth = hasSelection
            ? (count == 1 ? 0.0 : (total - activeWidth) / (count - 1))
            : total / count;

        return Row(
          children: [
            for (var i = 0; i < count; i++)
              _InlineLabelItem(
                destination: destinations[i],
                selected: i == selectedIndex,
                width: i == selectedIndex ? activeWidth : idleWidth,
                pillHeight: widget.pillHeight,
                labelStyle: labelStyle,
                onTap: () => widget.onSelected(i),
              ),
          ],
        );
      },
    );

    if (!hasSelection) return row;
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleRead();
              return true;
            },
            child: Offstage(
              child: SizeChangedLayoutNotifier(
                child: Text(
                  destinations[selectedIndex].label,
                  key: _measureKey,
                  maxLines: 1,
                  softWrap: false,
                  style: labelStyle,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(child: row),
      ],
    );
  }
}

class _InlineLabelItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final double width;
  final double pillHeight;
  final TextStyle labelStyle;
  final VoidCallback onTap;

  const _InlineLabelItem({
    required this.destination,
    required this.selected,
    required this.width,
    required this.pillHeight,
    required this.labelStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: NooMotion.base,
          curve: NooMotion.ease,
          width: width,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: NooMotion.base,
            curve: NooMotion.ease,
            height: pillHeight,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: EdgeInsets.symmetric(
              horizontal: selected ? _kInlinePillPadding : 0,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? colors.accentSoft
                  : colors.accentSoft.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(NooRadii.pill),
            ),
            // ClipRect + a non-wrapping, fading label: while the pill is
            // still growing the label is revealed left-to-right instead of
            // flickering through ellipsis states every frame.
            child: ClipRect(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    destination.icon,
                    size: selected ? 24 : 25,
                    color: selected ? colors.accentText : colors.fg2,
                  ),
                  if (selected)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: _kInlineIconGap),
                        child: Text(
                          destination.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: labelStyle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating bar's own Search entry point, next to the pill rather than
/// inside it - always fully round (see [NooBottomBar]'s doc comment),
/// same fill/shadow as the pill so the two still read as one family.
class _SearchSatellite extends StatelessWidget {
  final NooNavDestination destination;
  final VoidCallback onTap;
  final double size;
  final bool hero;
  final bool frosted;
  final double frostedBlur;
  final double frostedOpacity;

  const _SearchSatellite({
    required this.destination,
    required this.onTap,
    required this.size,
    this.hero = false,
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
        child: _satelliteBody(context, colors),
      ),
    );
  }

  Widget _satelliteBody(BuildContext context, NooColors colors) {
    final disc = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: frosted
            ? GlassBackdrop.fillColor(context, colors.surface, frostedOpacity)
            : colors.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(destination.icon, size: 24, color: colors.fg1),
    );
    final radius = BorderRadius.circular(size / 2);
    final body = NooFloatingShadow(
      radius: radius,
      child: frosted ? _blurred(disc, radius, frostedBlur) : disc,
    );
    return hero ? NooSearchHero(child: body) : body;
  }
}

class _IosItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final bool selectedLabelOnly;
  final bool iconOnly;
  final VoidCallback onTap;

  const _IosItem({
    required this.destination,
    required this.selected,
    this.selectedLabelOnly = false,
    this.iconOnly = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final fg = selected ? colors.accentText : colors.fg3;
    return Semantics(
      button: true,
      selected: selected,
      label: iconOnly || (selectedLabelOnly && !selected)
          ? destination.label
          : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: iconOnly || (selectedLabelOnly && !selected)
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
  final bool iconOnly;
  final VoidCallback onTap;

  const _AndroidItem({
    required this.destination,
    required this.selected,
    required this.floating,
    this.iconOnly = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final iconColor = selected ? colors.accentText : colors.fg2;

    final Widget content;
    if (iconOnly || (floating && !selected)) {
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
