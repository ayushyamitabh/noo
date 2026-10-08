import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../providers/session_controller.dart';
import '../noo/core/noo_toggle.dart';
import '../noo/lists/noo_settings_row.dart';
import 'settings_section.dart';

/// Settings section 3: three independent locks - opening the app, switching
/// accounts, and revealing hidden files - each behind the device's own PIN/
/// biometric credential (see `AppLockService` - this app never stores or
/// handles a PIN itself). Turning one on or off asks for that credential, and
/// none of them requires or implies another.
class SettingsSecuritySection extends StatelessWidget {
  const SettingsSecuritySection({super.key});

  Future<void> _handleLockChanged(
    BuildContext context, {
    required Future<bool> Function() change,
    required bool turningOn,
    required String name,
  }) async {
    final success = await change();
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            turningOn
                ? "Could not turn on $name - make sure this device has a PIN, pattern, password, or biometric configured"
                : 'Could not turn off $name',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return SettingsSection(
      title: 'Security',
      children: [
        NooSettingsRow(
          icon: LucideIcons.lock,
          label: const Text('App lock'),
          subtitle: const Text(
            "Require this device's PIN or biometric to open Noo",
          ),
          trailing: NooToggle(
            checked: session.loginLockEnabled,
            onChanged: (value) => _handleLockChanged(
              context,
              change: value ? session.setupLoginLock : session.disableLoginLock,
              turningOn: value,
              name: 'login lock',
            ),
          ),
        ),
        NooSettingsRow(
          icon: LucideIcons.arrowLeftRight,
          label: const Text('Lock account switching'),
          subtitle: const Text('Unlock to switch between saved accounts'),
          trailing: NooToggle(
            checked: session.lockAccountSwitching,
            onChanged: (value) => _handleLockChanged(
              context,
              change: () => session.setLockAccountSwitching(value),
              turningOn: value,
              name: 'account switching lock',
            ),
          ),
        ),
        NooSettingsRow(
          icon: LucideIcons.eyeOff,
          label: const Text('Lock hidden files'),
          subtitle: const Text('Unlock to reveal hidden files and folders'),
          trailing: NooToggle(
            checked: session.lockHiddenFiles,
            onChanged: (value) => _handleLockChanged(
              context,
              change: () => session.setLockHiddenFiles(value),
              turningOn: value,
              name: 'hidden files lock',
            ),
          ),
        ),
      ],
    );
  }
}
