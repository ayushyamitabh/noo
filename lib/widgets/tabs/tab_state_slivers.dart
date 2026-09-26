import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_button.dart';

/// Shared loading/error/empty slivers for Recent/Activity/Trash/Shares (and
/// any future tab shaped like them: a `CustomScrollView` over one flat
/// list), restyled with noo tokens instead of each screen hand-rolling the
/// same centered column - see `FilesView`'s identical error/empty layout,
/// which this mirrors.

/// Centered spinner for a tab's first load (list still empty).
const Widget tabLoadingSliver = SliverFillRemaining(
  hasScrollBody: false,
  child: Center(child: CircularProgressIndicator()),
);

/// Centered error state: icon, title, message, and a Retry button.
Widget tabErrorSliver(
  BuildContext context, {
  required String title,
  required String message,
  required VoidCallback onRetry,
}) {
  final colors = context.nooColors;
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.circleAlert, size: 56, color: colors.danger),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(color: colors.danger),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NooText.body.copyWith(color: colors.fg3),
            ),
            const SizedBox(height: 20),
            NooButton(
              variant: NooButtonVariant.secondary,
              size: NooButtonSize.field,
              icon: LucideIcons.refreshCw,
              onTap: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Centered empty state: an icon over a message.
Widget tabEmptySliver(
  BuildContext context, {
  required IconData icon,
  required String message,
}) {
  final colors = context.nooColors;
  return SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: colors.fg3),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NooText.cardTitle.copyWith(color: colors.fg2),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Bottom padding sliver so the last row/card clears the bottom nav/FAB -
/// same trailing pair every rebuilt tab list ends on.
const List<Widget> tabBottomInsetSlivers = [
  SliverToBoxAdapter(child: SizedBox(height: 100)),
  SliverFillRemaining(hasScrollBody: false, child: SizedBox()),
];
