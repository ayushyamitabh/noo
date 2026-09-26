import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/item_operations.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/lists/noo_grouped_list.dart';
import '../noo/media/noo_activity_item.dart';
import '../noo/media/noo_photo_tile.dart';

/// Per-file activity feed - the same actor/verb/tail mapping and
/// avatar-palette convention as the account-wide Activity tab
/// (`activity_view.dart`), scoped to a single item.
class DetailsActivityTab extends StatefulWidget {
  final NextcloudItem item;

  const DetailsActivityTab({super.key, required this.item});

  @override
  State<DetailsActivityTab> createState() => _DetailsActivityTabState();
}

class _DetailsActivityTabState extends State<DetailsActivityTab> {
  bool _requested = false;
  bool _isLoading = true;
  List<NextcloudActivity> _activities = [];

  Future<void> _load() async {
    final ops = context.read<ItemOperations>();
    final result = await ops.fetchFileActivity(widget.item);
    if (!mounted) return;
    setState(() {
      _activities = result;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final colors = context.nooColors;
    final session = context.watch<SessionController>();

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_activities.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.activity, size: 40, color: colors.fg3),
              const SizedBox(height: NooSpace.sm),
              Text(
                'No recent activity',
                style: NooText.cardTitle.copyWith(fontSize: 16, color: colors.fg2),
              ),
            ],
          ),
        ),
      );
    }

    return NooGroupedList(
      children: [
        for (final act in _activities)
          ColoredBox(
            color: colors.surface,
            child: NooActivityItem(
              actor: act.author,
              verb: act.title,
              tail: act.subject.isNotEmpty && act.subject != act.title
                  ? act.subject
                  : null,
              time: DateFormat.yMMMd().add_jm().format(act.timestamp),
              avatarColor: NooPhotoTile.paletteColor(act.author.hashCode),
              currentUser:
                  act.author.toLowerCase() == session.username.toLowerCase(),
            ),
          ),
      ],
    );
  }
}
