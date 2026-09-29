import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/design_tokens.dart';
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

/// One entry in [AccountView._sections] - [icon] and [label] are only used
/// by [_SectionJumpRail]'s tap targets, not shown next to the section
/// itself (each section already titles itself).
typedef _Section = (String label, IconData icon, Widget child);

/// Settings, pushed on top of the shell (DESIGN_SYSTEM.md 4's 9-section
/// order: account card, accounts, security, file sync, files cache,
/// appearance, tabs, action bar, swipe on a file). One column of
/// [SettingsSection]s (and [SettingsActionBarSection], which has no option
/// rows of its own to put in one - just the reorder list) on
/// mobile, with a trailing jump rail (see [_SectionJumpRail]) since the
/// list runs long enough that finding a specific section by scrolling
/// alone is slow; a 2-column grid of cards on desktop, wide enough to see
/// most sections without scrolling, so it doesn't get one. See each
/// `widgets/settings/*.dart` file for a section's own content and any
/// setting that had to be slotted in or grouped under "Advanced appearance".
class AccountView extends StatelessWidget {
  const AccountView({super.key});

  static const _sections = <_Section>[
    ('Account', LucideIcons.circleUser, SettingsAccountCard()),
    ('Accounts', LucideIcons.users, SettingsAccountsSection()),
    ('Security', LucideIcons.shield, SettingsSecuritySection()),
    ('File sync', LucideIcons.folderSync, SettingsFileSyncSection()),
    ('Files cache', LucideIcons.hardDrive, SettingsFilesCacheSection()),
    ('Appearance', LucideIcons.sunMoon, SettingsAppearanceSection()),
    ('Tabs', LucideIcons.layoutGrid, SettingsTabsSection()),
    ('Action bar', LucideIcons.slidersHorizontal, SettingsActionBarSection()),
    ('Swipe', LucideIcons.moveHorizontal, SettingsSwipeSection()),
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
        child: desktop
            ? _DesktopGrid(sections: [for (final s in _sections) s.$3])
            : _MobileList(sections: _sections),
      ),
    );
  }
}

/// A stable per-section identity, shared between the [KeyedSubtree] each
/// section is wrapped in and [_SectionJumpRail]'s lookup - [GlobalObjectKey]
/// compares by [String] equality, not instance identity, so building a new
/// one from the same label on each side still resolves to the same key.
GlobalKey _sectionKey(String label) => GlobalObjectKey(label);

class _MobileList extends StatefulWidget {
  final List<_Section> sections;
  const _MobileList({required this.sections});

  @override
  State<_MobileList> createState() => _MobileListState();
}

class _MobileListState extends State<_MobileList> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _jumpTo(String label) {
    final target = _sectionKey(label).currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: NooMotion.slow,
      curve: NooMotion.ease,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(
            NooSpace.sm,
            NooSpace.sm,
            NooSpace.xxl,
            NooSpace.xxl,
          ),
          physics: const BouncingScrollPhysics(),
          children: [
            for (final (label, _, child) in widget.sections) ...[
              KeyedSubtree(key: _sectionKey(label), child: child),
              const SizedBox(height: NooSpace.xl),
            ],
          ],
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 2,
          child: _SectionJumpRail(sections: widget.sections, onTap: _jumpTo),
        ),
      ],
    );
  }
}

/// A vertical rail of small per-section icons pinned to the trailing edge,
/// sitting where the scrollbar would otherwise be - tapping one jumps
/// straight to that section instead of scrolling the whole (fairly long)
/// Settings list by hand. Each icon is a generous 32px tap target even
/// though the rail itself is slim, so this stays usable one-handed.
class _SectionJumpRail extends StatelessWidget {
  final List<_Section> sections;
  final ValueChanged<String> onTap;

  const _SectionJumpRail({required this.sections, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(NooRadii.pill),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, icon, _) in sections)
              Semantics(
                button: true,
                label: 'Jump to $label',
                child: InkResponse(
                  onTap: () => onTap(label),
                  radius: 18,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(icon, size: 16, color: colors.fg3),
                  ),
                ),
              ),
          ],
        ),
      ),
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
        for (final child in children) ...[
          child,
          const SizedBox(height: NooSpace.xl),
        ],
      ],
    );
  }
}
