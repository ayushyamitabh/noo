import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../providers/server_provider.dart';

/// Wraps [child] with the user's configured swipe-left/swipe-right actions
/// (favorite, delete, share, or none) — shared between the Files list view
/// and the Photos grid so both behave identically. Callers own the actual
/// side effects (favoriting, sharing, deleting); this widget only decides
/// which action a given swipe direction maps to and drives the gesture.
class SwipeableItem extends StatelessWidget {
  final Key itemKey;
  final String itemName;
  final ServerProvider provider;
  final Future<void> Function() onFavorite;
  final Future<void> Function() onShare;
  final Future<void> Function() onDelete;
  final Widget child;

  const SwipeableItem({
    super.key,
    required this.itemKey,
    required this.itemName,
    required this.provider,
    required this.onFavorite,
    required this.onShare,
    required this.onDelete,
    required this.child,
  });

  static DismissDirection _directionFor(SwipeAction left, SwipeAction right) {
    final hasLeft = left != SwipeAction.none;
    final hasRight = right != SwipeAction.none;
    if (hasLeft && hasRight) return DismissDirection.horizontal;
    if (hasRight) return DismissDirection.startToEnd;
    if (hasLeft) return DismissDirection.endToStart;
    return DismissDirection.none;
  }

  static Widget _background(
    BuildContext context,
    SwipeAction action,
    Alignment alignment,
  ) {
    if (action == SwipeAction.none) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final Color color;
    final IconData icon;
    switch (action) {
      case SwipeAction.delete:
        color = colorScheme.error;
        icon = Icons.delete_rounded;
      case SwipeAction.favorite:
        color = Colors.red.shade400;
        icon = Icons.favorite_rounded;
      case SwipeAction.share:
        color = colorScheme.primary;
        icon = Icons.share_rounded;
      case SwipeAction.none:
        return const SizedBox.shrink();
    }

    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rightAction = provider.swipeRightAction;
    final leftAction = provider.swipeLeftAction;
    final direction = _directionFor(leftAction, rightAction);
    if (direction == DismissDirection.none) return child;

    return Dismissible(
      key: itemKey,
      direction: direction,
      background: _background(context, rightAction, Alignment.centerLeft),
      secondaryBackground: _background(
        context,
        leftAction,
        Alignment.centerRight,
      ),
      confirmDismiss: (dir) async {
        final action = dir == DismissDirection.startToEnd
            ? rightAction
            : leftAction;
        switch (action) {
          case SwipeAction.favorite:
            HapticFeedback.selectionClick();
            await onFavorite();
            return false;
          case SwipeAction.share:
            HapticFeedback.selectionClick();
            await onShare();
            return false;
          case SwipeAction.delete:
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Delete Item'),
                  content: Text(
                    'Delete "$itemName" from the server? This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(
                          dialogContext,
                        ).colorScheme.error,
                      ),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Delete'),
                    ),
                  ],
                );
              },
            );
            if (confirmed != true) return false;
            HapticFeedback.mediumImpact();
            return true; // Actual delete happens in onDismissed.
          case SwipeAction.none:
            return false;
        }
      },
      onDismissed: (dir) {
        final action = dir == DismissDirection.startToEnd
            ? rightAction
            : leftAction;
        if (action == SwipeAction.delete) onDelete();
      },
      child: child,
    );
  }
}
