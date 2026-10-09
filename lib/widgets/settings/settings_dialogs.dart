import 'package:flutter/material.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_button.dart';
import '../noo/noo_layout.dart';
import '../noo/overlays/noo_dialog.dart';
import '../noo/overlays/noo_overlay_header.dart';
import '../noo/overlays/noo_sheet.dart';

/// Shared by the account card's own quick "Remove account" action and each
/// row in the saved-accounts list - same confirm/remove/pop-to-root gate
/// either way (mirrors the pre-rework `_confirmRemoveActive`/
/// `_AccountsCard._confirmRemove`), just restyled as [showNooDialog]
/// (desktop) / [showNooSheet] (mobile) instead of an [AlertDialog].
Future<void> confirmRemoveAccount(
  BuildContext context,
  SessionController session, {
  required String accountId,
  required String username,
  required String host,
  required bool isActive,
}) async {
  final hasOtherAccounts = session.accounts.length > 1;
  final message = isActive && hasOtherAccounts
      ? 'Remove $username ($host)? Its synced files will be removed from this device. Another saved account will become active.'
      : 'Remove $username ($host)? Its synced files will be removed from this device. You can add it again later.';

  var confirmed = false;
  void cancel() => Navigator.pop(context);
  void confirm() {
    confirmed = true;
    Navigator.pop(context);
  }

  Widget buttons(NooColors colors) => Row(
    children: [
      Expanded(
        child: NooButton(
          variant: NooButtonVariant.secondary,
          size: NooButtonSize.card,
          fullWidth: true,
          onTap: cancel,
          child: const Text('Cancel'),
        ),
      ),
      const SizedBox(width: NooSpace.sm),
      Expanded(
        child: NooButton(
          variant: NooButtonVariant.danger,
          size: NooButtonSize.card,
          fullWidth: true,
          onTap: confirm,
          child: const Text('Remove'),
        ),
      ),
    ],
  );

  final colors = context.nooColors;
  if (NooLayout.isDesktop(context)) {
    await showNooDialog(
      context,
      title: 'Remove account',
      children: [
        Text(message, style: NooText.body.copyWith(color: colors.fg2)),
        buttons(colors),
      ],
    );
  } else {
    await showNooSheet(
      context,
      children: [
        NooOverlayHeader(title: 'Remove account', onClose: cancel),
        Text(message, style: NooText.body.copyWith(color: colors.fg2)),
        buttons(colors),
      ],
    );
  }

  if (!confirmed) return;
  if (!context.mounted) return;
  final navigator = Navigator.of(context);
  try {
    await session.removeAccount(accountId);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not remove local account data. Please try again.',
          ),
        ),
      );
    }
    return;
  }
  // Only when this was the last saved account does isLoggedIn drop to false
  // and main.dart swap the root route to LoginView underneath - pop back to
  // it then, rather than leaving Settings stranded on top. Removing a
  // non-active account, or falling back to another one, both keep the user
  // logged in, so Settings should just stay put.
  if (!session.isLoggedIn) {
    navigator.popUntil((route) => route.isFirst);
  }
}
