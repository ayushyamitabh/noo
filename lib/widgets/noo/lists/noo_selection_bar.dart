import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../models/selection_action.dart';
import '../../../theme/design_tokens.dart';
import '../files/noo_file_row.dart' show NooOverflowButton;
import '../overlays/noo_sheet.dart';
import 'noo_grouped_list.dart';
import 'noo_settings_row.dart';

/// Bulk actions shown inline before the rest collapse behind "More" - a
/// fixed, non-scrolling width on every platform (design canvas
/// https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4, "Selection action
/// bar"). Mobile is tighter (icons share the bar with the close circle and
/// count on a ~360dp phone); desktop's labelled pills have a wider toolbar
/// to work with.
const int _kMobileInlineActions = 3;
const int _kDesktopInlineActions = 4;

/// The multi-select action bar Files/Photos/Favorites swap in for their own
/// sort/filter row while selecting - design canvas
/// https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4 ("Selection action
/// bar"), since DESIGN_SYSTEM.md has no §4 recipe of its own for this.
/// Replaces the bare row of Material `IconButton`s each screen used to
/// build ad hoc.
///
/// A floating `surface` card (radius 20), with the bottom bar's border
/// and shadow - selection reads as a distinct mode, not
/// just a row of buttons floating on `bg` - with a close circle, the
/// count, and the bulk actions. This sits in the *content* pane's own
/// pinned header slot on every platform (the shell's desktop toolbar,
/// built separately in `main.dart`, never changes for selection), so
/// mobile and desktop share the same fixed 56px height; only the gutter
/// ([isDesktop] ? 24 : 12, matching `NooLayout.gutter`) and the actions'
/// presentation differ:
/// - Mobile: the first [_kMobileInlineActions] actions as plain 20px
///   accent-text icons, no fill.
/// - Desktop: the first [_kDesktopInlineActions] as labelled tonal pills -
///   danger-soft/danger for the one labelled "Delete", accent-soft/
///   accent-text otherwise - since desktop has the room for labels.
///
/// Any actions beyond that inline count sit behind a trailing "More"
/// button that opens the same grouped-list sheet a file row's own overflow
/// menu already uses (see `FilesView._showItemActions`) - never a second
/// scrolling row, which is what this replaced: with up to 9 bulk actions
/// (favorite, share, download, delete, copy, move, rename, sync,
/// details), a horizontally-scrolling row hid actions behind a swipe
/// gesture with no visible cue that there was more to find.
class NooSelectionBar extends StatelessWidget {
  final int count;
  final List<SelectionAction> actions;
  final VoidCallback onClose;
  final bool isDesktop;
  final bool iosStyle;

  const NooSelectionBar({
    super.key,
    required this.count,
    required this.actions,
    required this.onClose,
    required this.isDesktop,
    this.iosStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final gutter = isDesktop ? NooSpace.xl : NooSpace.sm;
    final inlineCount = isDesktop
        ? _kDesktopInlineActions
        : _kMobileInlineActions;
    final inlineActions = actions.length > inlineCount
        ? actions.sublist(0, inlineCount)
        : actions;
    final overflowActions = actions.length > inlineCount
        ? actions.sublist(inlineCount)
        : const <SelectionAction>[];

    // Every screen pins this into a fixed 56px sliver-header slot (the same
    // one the sort/filter row otherwise occupies) - the 4px top/bottom
    // margin plus the card's own 48px must add up to exactly that, or the
    // header overflows (see files_view.dart's `topRow` height comment for
    // the same warning about this exact number).
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter, vertical: NooSpace.xxs),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(NooRadii.card),
          border: Border.all(color: colors.line),
          boxShadow: const [nooDialogShadow],
        ),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: 'Cancel selection',
              child: GestureDetector(
                onTap: onClose,
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(LucideIcons.x, size: 18, color: colors.fg1),
                ),
              ),
            ),
            const SizedBox(width: NooSpace.xs),
            Text(
              '$count selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NooText.cardTitle.copyWith(
                fontSize: 17,
                color: colors.fg1,
              ),
            ),
            const SizedBox(width: NooSpace.xs),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: isDesktop
                    ? _desktopActions(
                        context,
                        colors,
                        inlineActions,
                        overflowActions,
                      )
                    : _mobileActions(
                        context,
                        colors,
                        inlineActions,
                        overflowActions,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileActions(
    BuildContext context,
    NooColors colors,
    List<SelectionAction> inline,
    List<SelectionAction> overflow,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in inline)
          Semantics(
            button: true,
            label: action.label,
            child: InkResponse(
              onTap: action.onTap,
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(action.icon, size: 20, color: colors.accentText),
              ),
            ),
          ),
        if (overflow.isNotEmpty)
          NooOverflowButton(
            iosStyle: iosStyle,
            onTap: () => _showOverflowSheet(context, overflow),
          ),
      ],
    );
  }

  Widget _desktopActions(
    BuildContext context,
    NooColors colors,
    List<SelectionAction> inline,
    List<SelectionAction> overflow,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in inline) ...[
          _DesktopActionPill(action: action, colors: colors),
          const SizedBox(width: 6),
        ],
        if (overflow.isNotEmpty)
          _DesktopMorePill(
            colors: colors,
            onTap: () => _showOverflowSheet(context, overflow),
          ),
      ],
    );
  }

  void _showOverflowSheet(
    BuildContext context,
    List<SelectionAction> overflow,
  ) {
    showNooSheet(
      context,
      children: [
        NooGroupedList(
          children: [
            for (final action in overflow)
              NooSettingsRow(
                icon: action.icon,
                label: Text(action.label),
                onTap: () {
                  Navigator.pop(context);
                  action.onTap();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _DesktopActionPill extends StatelessWidget {
  final SelectionAction action;
  final NooColors colors;

  const _DesktopActionPill({required this.action, required this.colors});

  @override
  Widget build(BuildContext context) {
    final danger = action.label == 'Delete';
    final bg = danger ? colors.dangerSoft : colors.accentSoft;
    final fg = danger ? colors.danger : colors.accentText;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(NooRadii.pill),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(NooRadii.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            height: 32,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(action.icon, size: 15, color: fg),
                const SizedBox(width: 6),
                Text(
                  action.label,
                  style: NooText.buttonSm.copyWith(color: fg, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The desktop overflow trigger - a secondary pill (matching the Button
/// component's "Secondary" variant) rather than a tonal one, so it reads
/// as "opens a menu" and not as another bulk action next to it. The
/// trailing `chevron-down` mirrors the same "opens a menu" cue `NooChip`
/// uses.
class _DesktopMorePill extends StatelessWidget {
  final NooColors colors;
  final VoidCallback onTap;

  const _DesktopMorePill({required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'More actions',
      child: Material(
        color: colors.surface2,
        borderRadius: BorderRadius.circular(NooRadii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(NooRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              height: 32,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'More',
                    style: NooText.buttonSm.copyWith(
                      color: colors.fg1,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(LucideIcons.chevronDown, size: 14, color: colors.fg1),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
