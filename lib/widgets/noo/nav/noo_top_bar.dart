import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';
import 'noo_nav_style.dart';

export 'noo_nav_style.dart';

// iOS large-title block: 2px above, a 34/0.9 line box (30.6 -> 31), then
// 12px below (14 when there's no search field under it, per the `iSet`
// Settings header in `Mobile Screen.dc.html`).
const double _iosRow = 44;
const double _iosTitleTop = 2;
const double _iosTitleBox = 31;
const double _iosSearch = 38;
const double _iosSearchBottom = 12;
const double _androidRow = 64;

/// Mobile top bar (DESIGN_SYSTEM.md 3, "Mobile"; `iBar`/`aBar`/`iSet`/
/// `aSet` in `Mobile Screen.dc.html`).
///
/// - [NooNavStyle.ios]: a 44px row with [leading] on the left and
///   [actions] on the right, all in accent-text; then the 34px large
///   [title]; then the optional [search] slot (laid out at 38px - pass a
///   `NooSearchField(ios: true)`).
/// - [NooNavStyle.android]: one 64px row: [leading], the 22px [title], then
///   [actions] (fg-1). Android has no [search] slot - search is an action
///   icon there, so [search] is ignored.
///
/// **Why a [PreferredSizeWidget] and not a sliver:** every part of it has a
/// fixed height, so it drops straight into `Scaffold.appBar` (which adds
/// the status-bar inset on top of [preferredSize]; the bar applies that
/// inset itself via [SafeArea]). It's still a plain box widget, so a screen
/// that wants the iOS large title to scroll away with content can put it in
/// a `SliverToBoxAdapter` (or a `SliverPersistentHeader` with a fixed
/// extent) instead - no sliver-specific variant needed. A collapsing
/// large-title-to-inline-title animation isn't in the spec, so it isn't
/// built here.
///
/// Use [NooTopBarButton] for icon actions and [NooTopBarBack] for a pushed
/// screen's back button; both size themselves for the current [style].
class NooTopBar extends StatelessWidget implements PreferredSizeWidget {
  final NooNavStyle style;
  final String title;

  /// Replaces the default leading button - e.g. a [NooTopBarBack] on a
  /// pushed screen. When null, a `menu` [NooTopBarButton] calling [onMenu]
  /// is shown if [onMenu] is set; otherwise nothing.
  final Widget? leading;
  final VoidCallback? onMenu;

  /// Trailing widgets, left to right: [NooTopBarButton]s, an avatar, etc.
  /// Icons inherit the bar's icon color (accent-text on iOS, fg-1 on
  /// Android) through [IconTheme].
  final List<Widget> actions;

  /// iOS only: the search field shown below the large title.
  final Widget? search;

  /// Android only: an extra widget (e.g. a search-field-styled launcher) in
  /// the flexible middle slot, to the title's own right - [title] keeps
  /// its natural (shrink-to-fit, ellipsized) width on the left, and this
  /// takes whatever space is left rather than replacing it. iOS already has
  /// a dedicated [search] slot below its large title for this; Android has
  /// no large title to put a second row under, so a caller that wants an
  /// inline search bar there puts it beside the title instead of adding a
  /// row.
  final Widget? androidTitleTrailing;

  /// Defaults to `bg` - the top bar sits on the screen background.
  final Color? backgroundColor;

  const NooTopBar({
    super.key,
    required this.style,
    required this.title,
    this.leading,
    this.onMenu,
    this.actions = const [],
    this.search,
    this.androidTitleTrailing,
    this.backgroundColor,
  });

  bool get _ios => style == NooNavStyle.ios;

  @override
  Size get preferredSize {
    if (!_ios) return const Size.fromHeight(_androidRow);
    return Size.fromHeight(
      _iosRow +
          _iosTitleTop +
          _iosTitleBox +
          (search != null ? 12 + _iosSearch + _iosSearchBottom : 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final lead =
        leading ??
        (onMenu != null
            ? NooTopBarButton(
                icon: LucideIcons.menu,
                tooltip: 'Menu',
                onTap: onMenu,
              )
            : null);

    final Widget body = _ios
        ? _buildIos(colors, lead)
        : _buildAndroid(context, colors, lead);

    return _NooTopBarScope(
      style: style,
      child: IconTheme.merge(
        data: IconThemeData(
          size: 24,
          color: _ios ? colors.accentText : colors.fg1,
        ),
        child: Material(
          color: backgroundColor ?? colors.bg,
          child: SafeArea(bottom: false, child: body),
        ),
      ),
    );
  }

  Widget _buildIos(NooColors colors, Widget? lead) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _iosRow,
          // 44px hit boxes around 24px icons add 10px each side, so 6px of
          // row padding puts the icons 16px from the screen edge.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(children: [?lead, const Spacer(), ...actions]),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            NooSpace.md,
            _iosTitleTop,
            NooSpace.md,
            search != null ? 12 : 14,
          ),
          child: SizedBox(
            height: _iosTitleBox,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NooText.largeTitle.copyWith(
                  leadingDistribution: TextLeadingDistribution.even,
                  color: colors.fg1,
                ),
              ),
            ),
          ),
        ),
        if (search != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NooSpace.md,
              0,
              NooSpace.md,
              _iosSearchBottom,
            ),
            child: SizedBox(height: _iosSearch, child: search),
          ),
      ],
    );
  }

  Widget _buildAndroid(BuildContext context, NooColors colors, Widget? lead) {
    return SizedBox(
      height: _androidRow,
      child: Padding(
        padding: EdgeInsetsDirectional.only(
          start: lead != null ? 4 : 16,
          end: 8,
        ),
        child: Row(
          spacing: 4,
          children: [
            ?lead,
            // The title is a non-flex child capped at 40% of the screen
            // width (so it keeps its natural width but still ellipsizes),
            // leaving the `Expanded` trailing widget all the remaining
            // space. A `Flexible` title would instead split the free space
            // 1:1 with it, since both default to flex 1.
            if (androidTitleTrailing != null) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                ),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.title.copyWith(height: 1, color: colors.fg1),
                ),
              ),
              Expanded(child: androidTitleTrailing!),
            ] else
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.title.copyWith(height: 1, color: colors.fg1),
                ),
              ),
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Lets [NooTopBarButton]/[NooTopBarBack] size themselves for the bar
/// they're in without the caller repeating the style.
class _NooTopBarScope extends InheritedWidget {
  final NooNavStyle style;

  const _NooTopBarScope({required this.style, required super.child});

  static NooNavStyle of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_NooTopBarScope>()?.style ??
      NooNavStyle.android;

  @override
  bool updateShouldNotify(_NooTopBarScope oldWidget) =>
      style != oldWidget.style;
}

/// A 24px icon action for [NooTopBar] - a 44px (iOS) or 48px (Android)
/// round hit box, colored by the bar's [IconTheme].
class NooTopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const NooTopBarButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final box = _NooTopBarScope.of(context) == NooNavStyle.ios ? 44.0 : 48.0;
    Widget button = SizedBox.square(
      dimension: box,
      child: InkResponse(
        onTap: onTap,
        radius: box / 2,
        child: Center(child: Icon(icon)),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip, child: button);
    return Semantics(button: true, label: tooltip, child: button);
  }
}

/// Back button for a pushed screen's [NooTopBar.leading]. iOS: a
/// `chevron-left` plus the previous screen's [label] in 17px accent-text
/// ("‹ Files"). Android: an `arrow-left` icon button ([label] becomes its
/// tooltip).
class NooTopBarBack extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const NooTopBarBack({super.key, this.label = 'Back', this.onTap});

  @override
  Widget build(BuildContext context) {
    final onPressed = onTap ?? () => Navigator.maybePop(context);
    if (_NooTopBarScope.of(context) == NooNavStyle.android) {
      return NooTopBarButton(
        icon: LucideIcons.arrowLeft,
        tooltip: label,
        onTap: onPressed,
      );
    }
    final colors = context.nooColors;
    return Semantics(
      button: true,
      child: InkResponse(
        onTap: onPressed,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(NooRadii.pill),
        child: SizedBox(
          height: 44,
          child: Padding(
            // The row already has 6px padding; 4 more lands the chevron at
            // the reference's 10px inset.
            padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                Icon(LucideIcons.chevronLeft, color: colors.accentText),
                Text(
                  label,
                  style: NooText.bodyL.copyWith(
                    fontSize: 17,
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
