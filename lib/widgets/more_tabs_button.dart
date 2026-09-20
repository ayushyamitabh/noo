import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../providers/pick_controller.dart';
import '../providers/settings_controller.dart';
import 'app_tab_view_builder.dart';

/// Opens a tab that's currently hidden from the bottom nav bar as its own
/// standalone screen. Shown in every tab's toolbar (not just Files) so
/// hidden destinations stay reachable no matter which tab is active.
/// Always visible; dims/disables itself when nothing is hidden.
class MoreTabsButton extends StatelessWidget {
  const MoreTabsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final pick = context.watch<PickController>();
    final settings = context.watch<SettingsController>();

    // While picking (another app's GET_CONTENT request), MainShellView
    // already restricts the bottom nav to Files/Photos - this button would
    // otherwise be the one remaining way to reach a tab that isn't a valid
    // pick source (Trash, Shares, ...), so it hides entirely rather than
    // just disabling.
    if (pick.isPicking) return const SizedBox.shrink();

    return PopupMenuButton<AppTab>(
      icon: const Icon(Icons.apps_rounded),
      tooltip: 'More tabs',
      enabled: settings.hiddenTabs.isNotEmpty,
      onSelected: (tab) => _openHiddenTab(context, tab),
      itemBuilder: (context) => [
        for (final tab in settings.tabOrder.where(
          (t) => settings.hiddenTabs.contains(t),
        ))
          PopupMenuItem(
            value: tab,
            child: Row(
              children: [
                Icon(tab.icon, size: 20),
                const SizedBox(width: 12),
                Text(tab.label),
              ],
            ),
          ),
      ],
    );
  }

  void _openHiddenTab(BuildContext context, AppTab tab) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            Scaffold(body: buildAppTabView(tab, ScrollController())),
      ),
    );
  }
}
