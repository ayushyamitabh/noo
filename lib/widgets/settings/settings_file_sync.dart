import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/app_tab.dart';
import '../../providers/session_controller.dart';
import '../../providers/sync_status_controller.dart';
import '../../services/sync_service.dart';
import '../../theme/design_tokens.dart';
import '../app_tab_view_builder.dart';
import '../noo/core/noo_button.dart';
import '../noo/core/noo_toggle.dart';
import '../noo/lists/noo_settings_row.dart';
import '../noo/nav/noo_top_bar.dart';
import '../noo/nav/noo_toolbar.dart';
import '../noo/noo_layout.dart';
import 'settings_section.dart';

/// Settings section 4: device sync (which folders/files mirror locally,
/// notifications, cellular use, and a manual "Sync now").
class SettingsFileSyncSection extends StatefulWidget {
  const SettingsFileSyncSection({super.key});

  @override
  State<SettingsFileSyncSection> createState() => _SettingsFileSyncSectionState();
}

class _SettingsFileSyncSectionState extends State<SettingsFileSyncSection> {
  bool _syncingNow = false;

  Future<void> _syncNow(SessionController session, SyncStatusController sync) async {
    setState(() => _syncingNow = true);
    try {
      await SyncService.syncNow(session, sync);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start sync: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  /// The Offline tab has its own chrome-free content (see the shared
  /// rebuild contract's "division of chrome" - only the shell draws top
  /// bars for a tab), so opening it as a pushed screen from here needs a
  /// minimal top bar of its own to stay navigable.
  void _openOfflineFiles(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: NooLayout.isDesktop(context)
              ? const NooToolbar(title: 'Offline')
              : NooTopBar(
                  style: NooLayout.navStyle(context),
                  title: 'Offline',
                  leading: const NooTopBarBack(),
                ),
          body: buildAppTabView(AppTab.offline, ScrollController()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final sync = context.watch<SyncStatusController>();
    final colors = context.nooColors;
    final folders = sync.syncedPaths;
    final everything = sync.syncEverything;
    final hasSyncScope = everything || folders.isNotEmpty;

    return SettingsSection(
      title: 'File sync',
      children: [
        NooSettingsRow(
          icon: LucideIcons.cloud,
          label: const Text('Sync everything'),
          subtitle: const Text('Mirror the whole account instead of picking folders'),
          trailing: NooToggle(checked: everything, onChanged: sync.setSyncEverything),
        ),
        NooSettingsRow(
          icon: LucideIcons.hardDriveDownload,
          label: const Text('View offline files'),
          subtitle: Text(
            everything
                ? 'Every folder in this account is synced'
                : folders.isEmpty
                ? 'Nothing synced yet'
                : '${folders.length} synced folder${folders.length == 1 ? '' : 's'}/file${folders.length == 1 ? '' : 's'}',
          ),
          onTap: () => _openOfflineFiles(context),
        ),
        NooSettingsRow(
          icon: LucideIcons.bellRing,
          label: const Text('Background sync notifications'),
          subtitle: const Text(
            'Show a notification when a background sync updates files. '
            'Conflicts and "Sync now" always notify.',
          ),
          trailing: NooToggle(checked: sync.syncNotifications, onChanged: sync.setSyncNotifications),
        ),
        NooSettingsRow(
          icon: LucideIcons.signal,
          label: const Text('Sync on cellular'),
          subtitle: const Text('Off = background sync only runs on Wi-Fi'),
          trailing: NooToggle(checked: sync.syncOnCellular, onChanged: sync.setSyncOnCellular),
        ),
        NooSettingsRow(
          icon: LucideIcons.refreshCw,
          label: const Text('Sync now'),
          trailing: _syncingNow
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: colors.accentText),
                )
              : NooButton(
                  variant: NooButtonVariant.tonal,
                  size: NooButtonSize.compact,
                  disabled: !hasSyncScope,
                  onTap: () => _syncNow(session, sync),
                  child: const Text('Sync now'),
                ),
        ),
      ],
    );
  }
}
