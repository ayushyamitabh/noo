import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

/// The desktop main-pane toolbar (DESIGN_SYSTEM.md 3, "Desktop"; the 64px
/// header in `Desktop Screen.dc.html`): 24px leading / 20px trailing
/// padding, 12px gaps, a 1px `line` along the bottom. Left to right:
///
/// - optional back/forward chevrons ([showHistoryNav] - macOS only; Windows
///   doesn't show them), 20px, fg-3
/// - the [title] (22 Schibsted) - or [titleWidget] instead, e.g. a
///   breadcrumb in Files; it inherits the title [DefaultTextStyle]
/// - flexible space
/// - the [search] slot, 260px wide (pass a `NooSearchField(onSurface: true)`)
/// - [actions] - `NooSegmentedControl`, `NooButton(size: toolbar)`, etc.
///
/// A [PreferredSizeWidget], so it can be the main pane's `Scaffold.appBar`.
/// No [SafeArea]: it never sits under a status bar.
class NooToolbar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? search;
  final List<Widget> actions;

  final bool showHistoryNav;

  /// Back/forward handlers for [showHistoryNav]; a null one draws that
  /// chevron disabled.
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  /// Defaults to `surface` - the toolbar belongs to the main pane.
  final Color? backgroundColor;

  const NooToolbar({
    super.key,
    this.title,
    this.titleWidget,
    this.search,
    this.actions = const [],
    this.showHistoryNav = false,
    this.onBack,
    this.onForward,
    this.backgroundColor,
  }) : assert(
         title == null || titleWidget == null,
         'Pass either title or titleWidget, not both.',
       );

  @override
  Size get preferredSize => const Size.fromHeight(NooSizes.toolbar);

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final titleStyle = NooText.title.copyWith(height: 1, color: colors.fg1);

    return Material(
      color: backgroundColor ?? colors.surface,
      child: Container(
        height: NooSizes.toolbar,
        padding: const EdgeInsetsDirectional.only(start: 24, end: 20),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.line)),
        ),
        child: Row(
          spacing: 12,
          children: [
            if (showHistoryNav)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    _HistoryButton(
                      icon: LucideIcons.chevronLeft,
                      tooltip: 'Back',
                      onTap: onBack,
                    ),
                    _HistoryButton(
                      icon: LucideIcons.chevronRight,
                      tooltip: 'Forward',
                      onTap: onForward,
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DefaultTextStyle(
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: titleWidget ?? Text(title ?? ''),
                ),
              ),
            ),
            if (search != null) SizedBox(width: 260, child: search),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// A 20px fg-3 chevron with a 28px hover/press target. Dimmed when
/// [onTap] is null (nothing to go back/forward to).
class _HistoryButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HistoryButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: InkResponse(
          onTap: onTap,
          radius: 16,
          splashFactory: NoSplash.splashFactory,
          hoverColor: colors.surface2,
          child: SizedBox.square(
            dimension: 28,
            child: Icon(icon, size: 20, color: colors.fg3),
          ),
        ),
      ),
    );
  }
}
