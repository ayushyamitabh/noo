import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/design_tokens.dart';
import '../widgets/noo/lists/noo_grouped_list.dart';
import '../widgets/noo/lists/noo_settings_row.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/nav/noo_sidebar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/settings/settings_account_card.dart';
import '../widgets/settings/settings_accounts.dart';
import '../widgets/settings/settings_about.dart';
import '../widgets/settings/settings_action_bar.dart';
import '../widgets/settings/settings_appearance.dart';
import '../widgets/settings/settings_file_sync.dart';
import '../widgets/settings/settings_files_cache.dart';
import '../widgets/settings/settings_security.dart';
import '../widgets/settings/settings_swipe.dart';
import '../widgets/settings/settings_tabs.dart';
import '../widgets/settings/settings_section.dart';

/// Settings uses pushed category screens on phones and an inline category
/// sidebar with a rounded content pane on tablets.
class AccountView extends StatefulWidget {
  const AccountView({super.key});

  @override
  State<AccountView> createState() => _AccountViewState();
}

class _AccountViewState extends State<AccountView> {
  int selected = 0;

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
    _SettingsCategory(
      title: 'About',
      icon: LucideIcons.info,
      builder: (_) => const SettingsAboutSection(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);

    if (desktop) {
      final category = _categories[selected];
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 260);
      return Scaffold(
        backgroundColor: colors.bg,
        body: SafeArea(
          child: Row(
            children: [
              NooSidebar(
                windowControls: Row(
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.arrowLeft),
                      tooltip: 'Back',
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    Expanded(
                      child: Text(
                        'Settings',
                        style: NooText.title.copyWith(color: colors.fg1),
                      ),
                    ),
                  ],
                ),
                account: SettingsAccountCard(
                  compact: true,
                  onManage: () => setState(() => selected = 0),
                ),
                groupItems: true,
                items: [
                  for (var index = 0; index < _categories.length; index++)
                    if (_categories[index].title != 'Swipe on a file')
                      NooSidebarItem(
                        icon: _categories[index].icon,
                        label: _categories[index].title,
                        selected: selected == index,
                        onTap: () => setState(() => selected = index),
                      ),
                ],
              ),
              Expanded(
                child: Column(
                  children: [
                    NooToolbar(
                      title: category.title,
                      backgroundColor: colors.bg,
                      framed: false,
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        child: Material(
                          color: colors.surface2,
                          borderRadius: BorderRadius.circular(NooRadii.card),
                          clipBehavior: Clip.antiAlias,
                          child: AnimatedSwitcher(
                            duration: duration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween(
                                      begin: const Offset(0, .025),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: ListView(
                              key: ValueKey(category.title),
                              padding: const EdgeInsets.all(12),
                              children: [
                                SettingsCategoryHeading(
                                  title: category.title,
                                  child: category.builder(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

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

/// A pushed category screen used by phone navigation.
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
              children: [
                SettingsCategoryHeading(
                  title: category.title,
                  child: category.builder(context),
                ),
              ],
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
