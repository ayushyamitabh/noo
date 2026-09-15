import 'dart:ui';
import 'package:flutter/material.dart';

class FloatingNavItem {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String? badge;

  const FloatingNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge,
  });
}

class FloatingBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<FloatingNavItem> items;
  final bool isVisible;

  const FloatingBottomNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.items,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      offset: isVisible ? Offset.zero : const Offset(0, 1.5),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: isVisible ? 1.0 : 0.0,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.only(bottom: 20, left: 24, right: 24),
              constraints: const BoxConstraints(maxWidth: 460),
              height: 68,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(34),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(items.length, (index) {
                        final item = items[index];
                        final isSelected = selectedIndex == index;

                        return Expanded(
                          child: InkWell(
                            onTap: () => onDestinationSelected(index),
                            borderRadius: BorderRadius.circular(28),
                            splashColor: colorScheme.primary.withValues(alpha: 0.12),
                            highlightColor: Colors.transparent,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOutCubic,
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedScale(
                                    duration: const Duration(milliseconds: 200),
                                    scale: isSelected ? 1.12 : 1.0,
                                    child: Icon(
                                      isSelected ? item.selectedIcon : item.icon,
                                      size: 22,
                                      color: isSelected
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                      letterSpacing: 0.1,
                                    ),
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
