import 'package:flutter/material.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/settings/settings_account_card.dart';
import '../widgets/settings/settings_accounts.dart';
import '../widgets/settings/settings_appearance.dart';
import '../widgets/settings/settings_file_sync.dart';
import '../widgets/settings/settings_files_cache.dart';
import '../widgets/settings/settings_security.dart';
import '../widgets/settings/settings_swipe.dart';
import '../widgets/settings/settings_tabs.dart';

/// Settings, pushed on top of the shell (DESIGN_SYSTEM.md 4's 8-section
/// order: account card, accounts, security, file sync, files cache,
/// appearance, tabs, swipe on a file). One column of [SettingsSection]s on
/// mobile; a 2-column grid of cards on desktop - see each
/// `widgets/settings/*.dart` file for a section's own content and any
/// setting that had to be slotted in or grouped under "Advanced appearance".
class AccountView extends StatelessWidget {
  const AccountView({super.key});

  static const _sections = <Widget>[
    SettingsAccountCard(),
    SettingsAccountsSection(),
    SettingsSecuritySection(),
    SettingsFileSyncSection(),
    SettingsFilesCacheSection(),
    SettingsAppearanceSection(),
    SettingsTabsSection(),
    SettingsSwipeSection(),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: desktop
          ? const NooToolbar(title: 'Settings')
          : NooTopBar(
              style: NooLayout.navStyle(context),
              title: 'Settings',
              leading: const NooTopBarBack(),
            ),
      body: SafeArea(
        top: false,
        child: desktop ? _DesktopGrid(sections: _sections) : _MobileList(sections: _sections),
      ),
    );
  }
}

class _MobileList extends StatelessWidget {
  final List<Widget> sections;
  const _MobileList({required this.sections});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(NooSpace.sm, NooSpace.sm, NooSpace.sm, NooSpace.xxl),
      physics: const BouncingScrollPhysics(),
      children: [
        for (final section in sections) ...[section, const SizedBox(height: NooSpace.xl)],
      ],
    );
  }
}

/// Splits the sections between two columns rather than a strict grid, since
/// each card's content height varies a lot (the tab reorder list and the
/// accounts list can both run much taller than, say, Security) - a fixed
/// grid would either clip content or leave large gaps.
class _DesktopGrid extends StatelessWidget {
  final List<Widget> sections;
  const _DesktopGrid({required this.sections});

  @override
  Widget build(BuildContext context) {
    final left = <Widget>[];
    final right = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      (i.isEven ? left : right).add(sections[i]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NooSpace.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _Column(children: left)),
            const SizedBox(width: NooSpace.xl),
            Expanded(child: _Column(children: right)),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  final List<Widget> children;
  const _Column({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final child in children) ...[child, const SizedBox(height: NooSpace.xl)],
      ],
    );
  }
}
