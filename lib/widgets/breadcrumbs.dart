import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/design_tokens.dart';

/// Tappable "Home / Folder / Sub-folder" trail shown whenever the user has
/// navigated below the root - now only used by `ShareUploadView` and
/// `MoveCopyDestinationPicker` (Files/Photos moved to their own noo-styled
/// `FileBreadcrumbRow`), so this is free to carry noo tokens directly rather
/// than staying on the old Material look. Same behaviour: every crumb but
/// the last is tappable, jumping back to that depth.
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
    final colors = context.nooColors;
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
                  LucideIcons.chevronRight,
                  size: 14,
                  color: colors.fg3,
                ),
              ),
            if (i == lastIndex)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  _labelFor(i),
                  style: NooText.body.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.fg1,
                  ),
                ),
              )
            else
              // The whole pill is the tap target, not just the text.
              InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(NooRadii.pill),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    _labelFor(i),
                    style: NooText.body.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.accentText,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
