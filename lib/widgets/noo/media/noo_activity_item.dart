import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../core/noo_avatar.dart';

/// Activity feed entry (`DESIGN_SYSTEM.md` section 2, "Activity item"):
/// a 36px [NooAvatar], then the sentence **actor** verb **object** tail
/// with the time below in meta style, and an optional [trailing] slot on
/// the right for the 32px/r10 file tile (built by the caller, so this
/// doesn't depend on the file-kind mapping).
class NooActivityItem extends StatelessWidget {
  final String actor;

  /// Plain text between actor and object, e.g. `"shared"`.
  final String verb;

  /// Bold subject of the action, e.g. a file name.
  final String? object;

  /// Plain text after the object, e.g. `"with you"`.
  final String? tail;

  final String? time;

  /// Avatar initials; defaults to the first letter of [actor].
  final String? initials;

  /// One of [NooColors.avatarPalette].
  final Color? avatarColor;

  /// Uses the accent-soft current-user avatar.
  final bool currentUser;

  /// Right-aligned slot, typically a 32px file tile.
  final Widget? trailing;

  final VoidCallback? onTap;

  const NooActivityItem({
    super.key,
    required this.actor,
    required this.verb,
    this.object,
    this.tail,
    this.time,
    this.initials,
    this.avatarColor,
    this.currentUser = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final base = NooText.body.copyWith(color: colors.fg1);
    const bold = TextStyle(fontWeight: FontWeight.w600);

    final fallbackInitials = actor.trim().isEmpty
        ? ''
        : actor.trim().characters.first.toUpperCase();

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: NooSpace.md,
            vertical: NooSpace.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NooAvatar(
                initials: initials ?? fallbackInitials,
                size: 36,
                color: avatarColor,
                current: currentUser,
              ),
              const SizedBox(width: NooSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: base,
                        children: [
                          TextSpan(text: actor, style: bold),
                          TextSpan(text: ' $verb'),
                          if (object != null) ...[
                            const TextSpan(text: ' '),
                            TextSpan(text: object, style: bold),
                          ],
                          if (tail != null) TextSpan(text: ' $tail'),
                        ],
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(height: NooSpace.xxs),
                      Text(time!, style: NooText.meta.copyWith(color: colors.fg3)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: NooSpace.sm),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
