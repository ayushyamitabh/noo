import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_nav_style.dart';

export 'noo_nav_style.dart';

/// The mobile bottom bar (DESIGN_SYSTEM.md 3, "Mobile"; `iNav`/`aNav` in
/// `Mobile Screen.dc.html`). Shows the 5 pinned tabs - which ones, and in
/// what order, is the caller's business; this only draws [destinations].
///
/// - [NooNavStyle.ios]: surface fill, 1px top `line`, a 50px row (8px top
///   padding) of icon 24 over a 10px label. Active: accent-text, 600.
///   Idle: fg-3, 500. No ripple.
/// - [NooNavStyle.android]: surface fill, 80px. The active icon sits in a
///   56x32 accent-soft pill (accent-text icon); label is 12px, fg-1/600
///   active and fg-2/500 idle (idle icon fg-2).
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

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < destinations.length; i++)
          Expanded(
            child: ios
                ? _IosItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  )
                : _AndroidItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
          ),
      ],
    );

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
      // No ripple: the animated pill is the press/selection feedback.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: NooMotion.fast,
              curve: NooMotion.ease,
              width: 56,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colors.accentSoft
                    : colors.accentSoft.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(NooRadii.pill),
              ),
              child: Icon(
                destination.icon,
                size: 24,
                color: selected ? colors.accentText : colors.fg2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              destination.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (selected ? NooText.navLabelActive : NooText.navLabel)
                  .copyWith(
                    height: 1,
                    color: selected ? colors.fg1 : colors.fg2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
