import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/session_controller.dart';
import '../views/account_view.dart';
import 'noo/core/noo_avatar.dart';

/// Top-bar avatar button that opens the account screen. Replaces the old
/// "Account" bottom-nav destination, matching how Google Drive surfaces
/// account access from a profile picture in the app bar. Also doubles as a
/// quick account switcher: swiping up/down on it cycles to the next/
/// previous saved account immediately, with no confirmation - a shortcut
/// alongside the full switcher list in Settings.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key});

  Future<void> _handleVerticalSwipe(
    BuildContext context,
    DragEndDetails details,
  ) async {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;

    final provider = context.read<SessionController>();
    final target = velocity < 0
        ? await provider.cycleToNextAccount()
        : await provider.cycleToPreviousAccount();
    if (target == null || !context.mounted) return;

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
    final provider = context.watch<SessionController>();
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
          icon: NooAvatar(initials: initial, current: true, size: 32),
        ),
      ),
    );
  }
}
