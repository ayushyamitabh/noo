import 'package:flutter/material.dart';

/// Wraps a thumbnail so it can show the multi-select checkmark state:
/// dimmed with a checkmark overlaid once selected, matching the Google
/// Photos-style long-press-to-select pattern. Shared by the Files and
/// Photos tabs.
class SelectableThumbnail extends StatelessWidget {
  final bool isSelected;
  final Widget child;

  /// Fixed width/height for a small square thumbnail (Files list/grid
  /// tiles). Leave null to fill whatever space the parent already gives it
  /// instead (e.g. a Photos grid cell, whose size comes from the grid
  /// layout rather than a fixed constant).
  final double? size;
  final double checkmarkSize;

  const SelectableThumbnail({
    super.key,
    required this.isSelected,
    required this.child,
    this.size,
    this.checkmarkSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: isSelected ? 0.35 : 1,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
        if (isSelected)
          Center(
            child: Icon(
              Icons.check_circle_rounded,
              color: colorScheme.primary,
              size: checkmarkSize,
            ),
          ),
      ],
    );

    if (size == null) return stack;
    return SizedBox(width: size, height: size, child: stack);
  }
}
