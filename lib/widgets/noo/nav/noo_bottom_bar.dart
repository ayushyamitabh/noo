import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_nav_style.dart';

export 'noo_nav_style.dart';

/// Android indicator geometry, shared between the sliding pill and each
/// item's own icon box so they line up exactly.
const double _kAndroidPillTop = 14;
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
/// The home indicator / gesture bar area below the row comes from the
/// bottom safe-area inset rather than a fixed 34/20px spacer, so it's
/// right on every device. Meant for `Scaffold.bottomNavigationBar`.
class NooBottomBar extends StatelessWidget {
  final NooNavStyle style;
  final List<NooNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const NooBottomBar({
    super.key,
    required this.style,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final ios = style == NooNavStyle.ios;

    final row = ios ? _buildIosRow() : _buildAndroidRow(colors);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: ios ? Border(top: BorderSide(color: colors.line)) : null,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(height: ios ? 50 : 80, child: row),
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

  Widget _buildAndroidRow(NooColors colors) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth / destinations.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: NooMotion.base,
              curve: NooMotion.ease,
              top: _kAndroidPillTop,
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
/// with its label always below it - the label's space is reserved
/// whether or not it's showing (only its opacity changes), so the icon
/// never shifts vertically as selection changes, and stays aligned with
/// the pill's fixed [_kAndroidPillTop]/[_kAndroidPillHeight].
class _AndroidItem extends StatelessWidget {
  final NooNavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _AndroidItem({
    required this.destination,
    required this.selected,
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
        child: Padding(
          padding: const EdgeInsets.only(top: _kAndroidPillTop),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(
                height: _kAndroidPillHeight,
                child: Center(
                  child: Icon(
                    destination.icon,
                    size: 24,
                    color: selected ? colors.accentText : colors.fg2,
                  ),
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
        ),
      ),
    );
  }
}
