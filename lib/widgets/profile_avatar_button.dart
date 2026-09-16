import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../views/account_view.dart';

/// Top-bar avatar button that opens the account screen. Replaces the old
/// "Account" bottom-nav destination, matching how Google Drive surfaces
/// account access from a profile picture in the app bar.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final initial = provider.username.isNotEmpty
        ? provider.username[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(right: 8),
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
    );
  }
}
