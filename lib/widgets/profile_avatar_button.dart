import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../views/account_view.dart';

/// Top-bar avatar button that opens the account screen. Replaces the old
/// "Account" bottom-nav destination, matching how Google Drive surfaces
/// account access from a profile picture in the app bar. Also doubles as a
/// quick account switcher: swiping up/down on it cycles to the next/
/// previous saved account immediately, with no confirmation - a shortcut
/// alongside the full switcher list in Settings.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key});

  void _handleVerticalSwipe(BuildContext context, DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;

    final provider = context.read<ServerProvider>();
    final target = velocity < 0
        ? provider.cycleToNextAccount()
        : provider.cycleToPreviousAccount();
    if (target == null) return;

    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to ${target.username}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final initial = provider.username.isNotEmpty
        ? provider.username[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onVerticalDragEnd: (details) => _handleVerticalSwipe(context, details),
        child: IconButton(
          tooltip: 'Settings',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AccountView()),
            );
          },
          icon: CircleAvatar(
            radius: 17,
            backgroundColor: colorScheme.primary,
            child: Text(
              initial,
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
