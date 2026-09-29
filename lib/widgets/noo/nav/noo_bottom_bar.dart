import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_nav_style.dart';

export 'noo_nav_style.dart';

/// Android indicator geometry, shared between the sliding pill and each
/// item's own icon box so they line up exactly. Floating's own top offset
/// is shorter than attached's - its row is 8px shorter overall (72 vs 80)
/// and there's no edge-to-edge safe-area strip inside it eating into that.
const double _kAttachedPillTop = 14;
const double _kFloatingPillTop = 10;
const double _kAndroidPillWidth = 56;
const double _kAndroidPillHeight = 32;

/// The mobile bottom bar (DESIGN_SYSTEM.md 3, "Mobile"; `iNav`/`aNav` in
/// `Mobile Screen.dc.html`). Shows the 5 pinned tabs - which ones, and in
/// what order, is the caller's business; this only draws [destinations].
///
/// - [NooNavStyle.ios]: surface fill, 1px top `line`, a 50px row (8px top
///   padding) of icon 24 over a 10px label. Active: accent-text, 600.
///   Idle: fg-3, 500. No ripple.
/// - [NooNavStyle.android]: surface fill, 80px. Every tab shows its 24px
///   icon over a 12px label (label only visible - not removed from layout,
///   so the row never resizes - once selected). The active icon sits in a
///   56x32 accent-soft pill that slides between tabs as selection moves,
///   rather than popping in/out on the destination item itself.
///
/// [barStyle] (user-configurable in Settings, Appearance) picks between
/// that edge-to-edge [NooBottomBarStyle.attached] bar and
/// [NooBottomBarStyle.floating] - inset 16px from both side edges, 28px
/// corners, a 1px `line` border instead of a shadow (see that enum's own
/// doc comment for why). Floating's Android row is 8px shorter (72 vs 80)
/// and drops its idle tabs' reserved label space - with no label to leave
/// room for, an idle icon just centers in the whole button and renders a
/// touch bigger (27 vs 24px) instead of sitting high with a gap under it.
/// The home indicator / gesture bar area below the row comes from the
/// bottom safe-area inset rather than a fixed 34/20px spacer, so it's
/// right on every device. Meant for `Scaffold.bottomNavigationBar` - the
/// host `Scaffold` needs `extendBody: true` while floating.
class NooBottomBar extends StatelessWidget {
  final NooNavStyle style;
  final NooBottomBarStyle barStyle;
  final List<NooNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const NooBottomBar({
    super.key,
    required this.style,
    this.barStyle = NooBottomBarStyle.attached,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final ios = style == NooNavStyle.ios;
    final floating = barStyle == NooBottomBarStyle.floating;

    final row = ios
        ? _buildIosRow()
        : _buildAndroidRow(colors, floating: floating);
    final barHeight = ios ? (floating ? 64.0 : 50.0) : (floating ? 72.0 : 80.0);

    if (floating) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: barHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.line),
              borderRadius: BorderRadius.circular(28),
            ),
            child: row,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: ios ? Border(top: BorderSide(color: colors.line)) : null,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(height: barHeight, child: row),
      ),
    );
  }

  Widget _buildIosRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < destinations.length; i++)
          Expanded(
            child: _IosItem(
              destination: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelected(i),
            ),
          ),
      ],
    );
  }

  Widget _buildAndroidRow(NooColors colors, {required bool floating}) {
    final pillTop = floating ? _kFloatingPillTop : _kAttachedPillTop;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / destinations.length;
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
                  Expanded(
                    child: _AndroidItem(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      floating: floating,
                      onTap: () => onSelected(i),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _IosItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _IosItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final fg = selected ? colors.accentText : colors.fg3;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
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
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
        child: Icon(destination.icon, size: 27, color: iconColor),
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
