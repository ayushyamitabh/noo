import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import '../core/noo_progress_bar.dart';

/// The desktop sidebar (DESIGN_SYSTEM.md 3, "Desktop"; the 256px column in
/// `Desktop Screen.dc.html`): `bg` fill, 12/12/16 padding, 2px between
/// rows, and a 1px `line` on its trailing edge separating it from the
/// `surface` main pane. Slots top to bottom:
///
/// 1. [windowControls] - e.g. macOS traffic lights (not built here)
/// 2. [account] - usually a [NooSidebarAccount] (14px gap below it)
/// 3. [items] - the pinned tabs, a [NooSidebarDivider], then the rest, as
///    [NooSidebarItem]s
/// 4. a spacer, then [storage] (usually a [NooSidebarStorage]) and
///    [settings] (a [NooSidebarItem])
///
/// Scrolls when the window is too short, keeping the bottom slots pinned
/// down when it isn't.
class NooSidebar extends StatelessWidget {
  final Widget? windowControls;
  final Widget? account;
  final List<Widget> items;
  final Widget? storage;
  final Widget? settings;

  /// Draw the 1px trailing-edge `line`. Turn off if the main pane draws
  /// its own leading border.
  final bool showDivider;

  const NooSidebar({
    super.key,
    this.windowControls,
    this.account,
    this.items = const [],
    this.storage,
    this.settings,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    const padding = EdgeInsets.fromLTRB(12, 12, 12, 16);

    return Container(
      width: NooSizes.sidebarWidth,
      decoration: BoxDecoration(
        color: colors.bg,
        border: showDivider
            ? BorderDirectional(end: BorderSide(color: colors.line))
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: padding,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - padding.vertical,
                ),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 2,
                  children: [
                    ?windowControls,
                    if (account != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: account,
                      ),
                    ...items,
                    const Spacer(),
                    ?storage,
                    ?settings,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 38px sidebar row: 18px icon, 14/500 label, optional trailing [count]
/// (12/500). Idle: fg-1 label, fg-2 icon, fg-3 count, `surface` on hover.
/// Active ([selected]): accent-soft fill, everything accent-text, label at
/// 600. Radius 12.
class NooSidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final VoidCallback? onTap;

  const NooSidebarItem({
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
    final radius = BorderRadius.circular(NooRadii.sidebarItem);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accentSoft : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: selected ? Colors.transparent : colors.surface,
          splashFactory: NoSplash.splashFactory,
          child: SizedBox(
            height: NooSizes.sidebarItem,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                spacing: 12,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: selected ? colors.accentText : colors.fg2,
                  ),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.body.copyWith(
                        fontSize: 14,
                        height: 1,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: selected ? colors.accentText : colors.fg1,
                      ),
                    ),
                  ),
                  if (count != null && count!.isNotEmpty)
                    Text(
                      count!,
                      style: NooText.body.copyWith(
                        fontSize: 12,
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

/// The 1px `line` between the pinned and remaining tabs, inset 12px with
/// 8px above and below.
class NooSidebarDivider extends StatelessWidget {
  const NooSidebarDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: context.nooColors.line,
    );
  }
}

/// The account switcher card at the top of [NooSidebar]: a `surface` card
/// (radius 14, 8/10 padding) with a 32px [avatar], [name] (14/600) over
/// [subtitle] (12, fg-3), and a `chevron-right` in fg-3.
class NooSidebarAccount extends StatelessWidget {
  /// Usually `NooAvatar(size: 32, current: true, ...)`.
  final Widget avatar;
  final String name;
  final String? subtitle;
  final VoidCallback? onTap;

  const NooSidebarAccount({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final radius = BorderRadius.circular(NooRadii.input);
    return Material(
      color: colors.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            spacing: 10,
            children: [
              avatar,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NooText.body.copyWith(
                        fontSize: 14,
                        height: 1,
                        fontWeight: FontWeight.w600,
                        color: colors.fg1,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NooText.meta.copyWith(
                          fontSize: 12,
                          height: 1,
                          color: colors.fg3,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: colors.fg3),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar storage meter: "Storage" (12/500 fg-1) and a [detail]
/// ("38.2 of 100 GB", 12 fg-2) on one line, over a 6px [NooProgressBar].
class NooSidebarStorage extends StatelessWidget {
  /// 0-1.
  final double value;
  final String detail;
  final String label;

  const NooSidebarStorage({
    super.key,
    required this.value,
    required this.detail,
    this.label = 'Storage',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final meta = NooText.meta.copyWith(
      fontSize: 12,
      height: 1,
      color: colors.fg2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Row(
            children: [
              Text(
                label,
                style: meta.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.fg1,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: meta,
                ),
              ),
            ],
          ),
          NooProgressBar(value: value),
        ],
      ),
    );
  }
}
