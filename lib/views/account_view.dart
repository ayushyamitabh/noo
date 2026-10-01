import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/settings/settings_account_card.dart';
import '../widgets/settings/settings_accounts.dart';
import '../widgets/settings/settings_action_bar.dart';
import '../widgets/settings/settings_appearance.dart';
import '../widgets/settings/settings_file_sync.dart';
import '../widgets/settings/settings_files_cache.dart';
import '../widgets/settings/settings_security.dart';
import '../widgets/settings/settings_swipe.dart';
import '../widgets/settings/settings_tabs.dart';

/// Settings, pushed on top of the shell (DESIGN_SYSTEM.md 4's 9-section
/// order: account card, accounts, security, file sync, files cache,
/// appearance, tabs, action bar, swipe on a file).
///
/// Every layout (including wide tablet, in a centered 640px column) is
/// a two-level menu, the way native iOS/Android Settings apps
/// work: [SettingsAccountCard] (the account summary, not a settings picker)
/// stays pinned at the top of a single top-level list ([_MobileMenu]), and
/// every other section becomes one tappable [NooSettingsRow] - icon, title,
/// chevron - in a [NooGroupedList] below it. Tapping a row pushes a new
/// [_SettingsCategoryScreen] with its own [NooTopBar]/[NooTopBarBack],
/// containing just that section's content full-screen. This replaces an
/// earlier design where every section rendered inline in one long
/// collapsible-sections column (`_MobileList`, since removed) - and before
/// that, a trailing jump rail (an even earlier version) that scrolled that
/// *same* page to an anchor. Both were rejected: the jump rail added a
/// second, redundant way to navigate on top of plain scrolling without
/// shortening the page, and the collapsible-sections column still left a
/// long page to scroll past even collapsed. A genuinely separate pushed
/// screen per category removes the scroll-depth problem outright, so
/// neither a jump rail nor per-section collapsing is needed any more - see
/// [SettingsSection]'s doc comment for how that reflects in its mobile
/// layout. See each `widgets/settings/*.dart` file for a section's own
/// content and any setting that had to be slotted in or grouped under
/// "Advanced appearance".
class AccountView extends StatelessWidget {
  const AccountView({super.key});

  static final _categories = <_SettingsCategory>[
    _SettingsCategory(
      title: 'Accounts',
      icon: LucideIcons.users,
      builder: (_) => const SettingsAccountsSection(),
    ),
    _SettingsCategory(
      title: 'Security',
      icon: LucideIcons.lock,
      builder: (_) => const SettingsSecuritySection(),
    ),
    _SettingsCategory(
      title: 'File sync',
      icon: LucideIcons.cloud,
      builder: (_) => const SettingsFileSyncSection(),
    ),
    _SettingsCategory(
      title: 'Files cache',
      icon: LucideIcons.database,
      builder: (_) => const SettingsFilesCacheSection(),
    ),
    _SettingsCategory(
      title: 'Appearance',
      icon: LucideIcons.sunMoon,
      builder: (_) => const SettingsAppearanceSection(),
    ),
    _SettingsCategory(
      title: 'Tabs',
      icon: LucideIcons.layoutGrid,
      builder: (_) => const SettingsTabsSection(),
    ),
    _SettingsCategory(
      title: 'Action bar',
      icon: LucideIcons.slidersHorizontal,
      builder: (_) => const SettingsActionBarSection(),
    ),
    _SettingsCategory(
      title: 'Swipe on a file',
      icon: LucideIcons.chevronsLeftRight,
      builder: (_) => const SettingsSwipeSection(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: desktop
          ? _desktopBar(context, 'Settings')
          : NooTopBar(
              style: NooLayout.navStyle(context),
              title: 'Settings',
              leading: const NooTopBarBack(),
            ),
      body: SafeArea(
        top: false,
        child: desktop
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _MobileMenu(categories: _categories),
                ),
              )
            : _MobileMenu(categories: _categories),
      ),
    );
  }
}

/// One row of [AccountView]'s mobile top-level menu: a title, a leading
/// icon (reused from that section's own first/most-representative row, so
/// the menu icon and the content the user lands on agree), and a builder
/// for the section content shown on [_SettingsCategoryScreen].
class _SettingsCategory {
  final String title;
  final IconData icon;
  final WidgetBuilder builder;

  _SettingsCategory({
    required this.title,
    required this.icon,
    required this.builder,
  });
}

/// The mobile top-level Settings list: [SettingsAccountCard] pinned above a
/// single [NooGroupedList] of category rows, one per [AccountView._categories]
/// entry - the menu half of the menu-then-pushed-screen pattern described on
/// [AccountView]'s own doc comment.
class _MobileMenu extends StatelessWidget {
  final List<_SettingsCategory> categories;
  const _MobileMenu({required this.categories});

  void _open(BuildContext context, _SettingsCategory category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsCategoryScreen(category: category),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        NooSpace.sm,
        NooSpace.sm,
        NooSpace.sm,
        NooSpace.xxl,
      ),
      physics: const BouncingScrollPhysics(),
      children: [
        const SettingsAccountCard(),
        const SizedBox(height: NooSpace.xl),
        NooGroupedList(
          children: [
            for (final category in categories)
              NooSettingsRow(
                icon: category.icon,
                label: Text(category.title),
                trailing: Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: colors.fg3,
                ),
                onTap: () => _open(context, category),
              ),
          ],
        ),
      ],
    );
  }
}

/// A pushed, single-category Settings screen: [NooTopBar] titled with the
/// category, a back button, and just that section's own content - the
/// pushed half of [AccountView]'s mobile menu-then-screen pattern. Always
/// built in a mobile-width context (desktop never opens this screen; it
/// shows every section inline in its own grid instead), so the section
/// widgets inside render their normal mobile layout unchanged.
class _SettingsCategoryScreen extends StatelessWidget {
  final _SettingsCategory category;
  const _SettingsCategoryScreen({required this.category});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: desktop
          ? _desktopBar(context, category.title)
          : NooTopBar(
              style: NooLayout.navStyle(context),
              title: category.title,
              leading: const NooTopBarBack(),
            ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 640 : double.infinity,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                NooSpace.sm,
                NooSpace.sm,
                NooSpace.sm,
                NooSpace.xxl,
              ),
              physics: const BouncingScrollPhysics(),
              children: [category.builder(context)],
            ),
          ),
        ),
      ),
    );
  }
}

PreferredSizeWidget _desktopBar(BuildContext context, String title) {
  final top = MediaQuery.paddingOf(context).top;
  return PreferredSize(
    preferredSize: Size.fromHeight(NooToolbar.outerHeight + top),
    child: Padding(
      padding: EdgeInsets.only(top: top),
      child: NooToolbar(
        titleWidget: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: NooSpace.sm,
          children: [
            IconButton(
              icon: const Icon(LucideIcons.arrowLeft),
              tooltip: 'Back',
              onPressed: () => Navigator.maybePop(context),
            ),
            Text(title),
          ],
        ),
      ),
    ),
  );
}
