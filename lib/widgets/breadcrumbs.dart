import 'package:flutter/material.dart';

/// Tappable "Home / Folder / Sub-folder" trail shown whenever the user has
/// navigated below the root, in both the Files and Photos tabs.
class Breadcrumbs extends StatelessWidget {
  final List<String> pathStack;
  final ValueChanged<int> onTap;

  const Breadcrumbs({super.key, required this.pathStack, required this.onTap});

  String _labelFor(int index) {
    if (index == 0) return 'Home';
    final segments = pathStack[index]
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? 'Home' : segments.last;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lastIndex = pathStack.length - 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < pathStack.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: colorScheme.outlineVariant,
                ),
              ),
            if (i == lastIndex)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _labelFor(i),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
              )
            else
              // A chip's whole pill is the tap target (not just the text),
              // so the previous plain-text crumbs were fiddly to hit.
              ActionChip(
                label: Text(_labelFor(i)),
                labelStyle: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
                onPressed: () => onTap(i),
                backgroundColor: colorScheme.surfaceContainerHigh,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
          ],
        ],
      ),
    );
  }
}
