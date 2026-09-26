import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import '../core/noo_progress_bar.dart';

/// The mobile drawer shell (DESIGN_SYSTEM.md 2 "Drawer" / 3; `drawer` in
/// `Mobile Screen.dc.html`): 316px wide, `surface` fill, radius 28 on the
/// trailing edge, flat (no elevation). Slots top to bottom:
///
/// 1. [account] - usually a [NooDrawerAccount]
/// 2. [storage] - usually a [NooDrawerStorage]
/// 3. a divider, then - only when [moreItems] isn't empty - the [moreLabel]
///    heading and [moreItems] (the unpinned tabs, as [NooDrawerItem]s)
/// 4. a divider, then [settings] (a [NooDrawerItem])
/// 5. a spacer, then [footer] - the "Edit tabs" [NooDrawerLink]
///
/// Wraps Flutter's [Drawer], so pass it to `Scaffold.drawer` and the open/
/// close gesture and semantics come for free. The scrim is the Scaffold's
/// job, not the drawer's: set `Scaffold.drawerScrimColor` to
/// `context.nooColors.scrim`. The content scrolls if it doesn't fit (e.g.
/// landscape), keeping [footer] pinned to the bottom when it does.
class NooDrawer extends StatelessWidget {
  final Widget? account;
  final Widget? storage;
  final String moreLabel;
  final List<Widget> moreItems;
  final Widget? settings;
  final Widget? footer;

  const NooDrawer({
    super.key,
    this.account,
    this.storage,
    this.moreLabel = 'More',
    this.moreItems = const [],
    this.settings,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final insets = MediaQuery.paddingOf(context);

    Widget divider(EdgeInsets margin) =>
        Container(height: 1, margin: margin, color: colors.line);

    final children = <Widget>[
      ?account,
      ?storage,
      if (account != null || storage != null)
        divider(const EdgeInsets.fromLTRB(12, 0, 12, 8)),
      if (moreItems.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            moreLabel,
            style: NooText.label.copyWith(height: 1, color: colors.fg2),
          ),
        ),
        ...moreItems,
        if (settings != null)
          divider(const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      ],
      ?settings,
      const Spacer(),
      ?footer,
    ];

    return Drawer(
      width: 316,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(
          end: Radius.circular(NooRadii.sheetTop),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          // Reference: 64px from the screen top (= status bar + 10-24px),
          // 12px sides, 28px bottom.
          padding: EdgeInsets.fromLTRB(
            NooSpace.sm,
            insets.top + NooSpace.md,
            NooSpace.sm,
            math.max(28, insets.bottom + NooSpace.sm),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                constraints.maxHeight -
                    insets.top -
                    NooSpace.md -
                    math.max(28, insets.bottom + NooSpace.sm),
              ),
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 4,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer's account block: 48px [avatar], the account [name] (18
/// Schibsted) over a [subtitle] (usually the server host, 13 fg-3), and a
/// 36px surface-2 circle with `chevron-down` to switch accounts.
class NooDrawerAccount extends StatelessWidget {
  /// Usually `NooAvatar(size: 48, current: true, ...)`.
  final Widget avatar;
  final String name;
  final String? subtitle;

  /// Tapping the block itself (e.g. open account settings).
  final VoidCallback? onTap;

  /// The chevron button; hidden when null.
  final VoidCallback? onSwitchAccount;

  const NooDrawerAccount({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.onTap,
    this.onSwitchAccount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NooRadii.input),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              spacing: 12,
              children: [
                avatar,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    spacing: 5,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.groupHeading.copyWith(
                          height: 1,
                          color: colors.fg1,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NooText.meta.copyWith(
                            height: 1,
                            color: colors.fg3,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onSwitchAccount != null)
                  Tooltip(
                    message: 'Switch account',
                    child: Material(
                      color: colors.surface2,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onSwitchAccount,
                        child: SizedBox.square(
                          dimension: 36,
                          child: Icon(
                            LucideIcons.chevronDown,
                            size: 18,
                            color: colors.fg1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The drawer's storage meter: a 6px [NooProgressBar] over a meta line
/// ("38.2 GB of 100 GB used").
class NooDrawerStorage extends StatelessWidget {
  /// 0-1.
  final double value;
  final String label;

  const NooDrawerStorage({super.key, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          NooProgressBar(value: value),
          Text(
            label,
            style: NooText.meta.copyWith(height: 1, color: colors.fg3),
          ),
        ],
      ),
    );
  }
}

/// A 52px pill row in [NooDrawer]: 24px icon, 16/500 label, optional
/// trailing [count] (14/500 fg-3). [selected] gives it an accent-soft fill
/// with accent-text content (label at 600, matching the sidebar's active
/// item).
class NooDrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback? onTap;

  const NooDrawerItem({
    super.key,
    required this.icon,
    required this.label,
    this.count,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final fg = selected ? colors.accentText : colors.fg1;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 14,
                children: [
                  Icon(icon, size: 24, color: fg),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.bodyL.copyWith(
                        height: 1,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (count != null && count!.isNotEmpty)
                    Text(
                      count!,
                      style: NooText.body.copyWith(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w500,
                        color: selected ? colors.accentText : colors.fg3,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The accent-text link at the bottom of [NooDrawer] ("Edit tabs"): 16px
/// icon, 14/600 label.
class NooDrawerLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const NooDrawerLink({
    super.key,
    this.label = 'Edit tabs',
    this.icon = LucideIcons.pencil,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            // Vertical padding only grows the hit target (to 44px); the
            // 16px sides match the reference inset.
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Icon(icon, size: 16, color: colors.accentText),
                Text(
                  label,
                  style: NooText.buttonSm.copyWith(
                    height: 1,
                    color: colors.accentText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
