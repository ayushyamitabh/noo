import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../theme/design_tokens.dart';

// Building blocks for the share sheet (mobile, via `showNooSheet`) and the
// share dialog (desktop, via `showNooDialog`) - DESIGN_SYSTEM.md section 4,
// "Share sheet / dialog". Both containers already space their children
// 22px apart, so each [NooShareSection] is one of those children.

/// A titled share-sheet section ("Share with people", "Share link", "Send
/// file directly"). [trailing] sits on the title row - the link section's
/// `NooToggle`. [caption] is the meta line under the content (e.g. "Link
/// settings don't apply").
class NooShareSection extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  final String? caption;

  const NooShareSection({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: NooText.sectionTitle.copyWith(color: colors.fg1)),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: NooSpace.sm),
        child,
        if (caption != null) ...[
          const SizedBox(height: NooSpace.xs),
          Text(caption!, style: NooText.meta.copyWith(color: colors.fg3)),
        ],
      ],
    );
  }
}

/// One person/group with access: avatar, name, subtitle, then either the
/// owner label or a tappable permission pill ("Can edit ▾"). Owner rows
/// aren't interactive, so they get plain fg-3 text instead of a pill - the
/// pill shape is reserved for things that open a menu.
class NooPersonAccessRow extends StatelessWidget {
  /// Typically a 36px `NooAvatar`.
  final Widget avatar;
  final String name;
  final String? subtitle;
  final bool owner;
  /// Pill label for non-owners, e.g. "Can edit" / "Can view".
  final String permission;
  final VoidCallback? onPermissionTap;
  final String ownerLabel;
  /// Replaces the owner label / permission pill (e.g. a plain search result).
  final Widget? trailing;

  const NooPersonAccessRow({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.owner = false,
    this.permission = 'Can edit',
    this.onPermissionTap,
    this.ownerLabel = 'Owner',
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: NooSpace.sm),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NooText.body.copyWith(
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                    color: colors.fg1,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NooText.meta.copyWith(color: colors.fg3),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: NooSpace.sm),
          if (trailing != null)
            trailing!
          else if (owner)
            Text(ownerLabel, style: NooText.label.copyWith(color: colors.fg3))
          else
            NooPermissionPill(label: permission, onTap: onPermissionTap),
        ],
      ),
    );
  }
}

/// Surface-2 pill with a trailing chevron that opens a permission menu.
/// Also used for the link section's permission option.
class NooPermissionPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const NooPermissionPill({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: NooSizes.buttonCompact,
        padding: const EdgeInsets.only(left: NooSpace.sm, right: 10),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(NooRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: NooText.label.copyWith(height: 1, color: colors.fg1)),
            const SizedBox(width: NooSpace.xxs),
            Icon(LucideIcons.chevronDown, size: 14, color: colors.fg2),
          ],
        ),
      ),
    );
  }
}
