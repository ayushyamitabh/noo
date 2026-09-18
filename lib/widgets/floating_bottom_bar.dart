import 'package:flutter/material.dart';
import 'frosted_glass_container.dart';

class FloatingNavItem {
  final String label;
  final IconData icon;

  const FloatingNavItem({required this.label, required this.icon});
}

/// A floating pill-shaped bottom navigation bar in the style of Google
/// Photos' 2026 redesign: unselected destinations collapse to just their
/// icon, the selected destination expands into an icon+label capsule, and
/// a detached circular action (search) sits just outside the pill.
class FloatingBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavItem> items;
  final VoidCallback? onSearchTap;
  final double opacity;
  final double blurSigma;

  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
    this.onSearchTap,
    this.opacity = 0.55,
    this.blurSigma = 28,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPill(context, colorScheme),
                const SizedBox(width: 10),
                _buildSearchButton(context, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(BuildContext context, ColorScheme colorScheme) {
    return FrostedGlassContainer(
      opacity: opacity,
      blurSigma: blurSigma,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        // The selected item's label expands the pill, and with enough
        // tabs visible that can outgrow the available width (the
        // ConstrainedBox above caps it at 480, but the screen itself may
        // be narrower) - wrapped in a scroll view rather than a plain Row
        // so it degrades to a swipe instead of overflowing/clipping.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = selectedIndex == index;

              return InkWell(
                onTap: () => onDestinationSelected(index),
                borderRadius: BorderRadius.circular(26),
                splashColor: colorScheme.primary.withValues(alpha: 0.12),
                highlightColor: Colors.transparent,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOutCubic,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? 16 : 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : colorScheme.onSurfaceVariant,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimary,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton(BuildContext context, ColorScheme colorScheme) {
    return FrostedGlassContainer(
      opacity: opacity,
      blurSigma: blurSigma,
      child: SizedBox(
        width: 52,
        height: 52,
        child: InkWell(
          onTap: onSearchTap,
          borderRadius: BorderRadius.circular(32),
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(
            Icons.search_rounded,
            color: colorScheme.onSurfaceVariant,
            size: 24,
          ),
        ),
      ),
    );
  }
}
