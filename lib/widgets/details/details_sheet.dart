import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import '../../models/nextcloud_item.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_segmented_control.dart';
import '../noo/files/noo_file_kind.dart';
import '../noo/files/noo_file_tile.dart';
import '../noo/noo_layout.dart';
import '../noo/overlays/noo_dialog.dart';
import '../noo/overlays/noo_overlay_header.dart';
import '../noo/overlays/noo_sheet.dart';
import '../synced_header_scaffold.dart' show formatBytes;
import 'details_activity_tab.dart';
import 'details_info_tab.dart';
import 'details_versions_tab.dart';

/// The file-type tile every per-item sheet/dialog opens on
/// (`DESIGN_SYSTEM.md` §1.2/§4) - shared by [DetailsSheet] and [ShareSheet]
/// so both overlays for the same item use the same header tile.
Widget detailsFileTile(
  NextcloudItem item, {
  NooFileTileSize size = NooFileTileSize.header,
}) {
  return NooFileTile(
    kind: NooFileKind.from(
      name: item.name,
      mimeType: item.mimeType,
      isDirectory: item.isFolder,
    ),
    size: size,
  );
}

/// The header's meta subtitle - "12.3 KB · Documents" for a file, "Folder"
/// for a folder (`DESIGN_SYSTEM.md` §4: "size · folder").
String detailsMetaLine(NextcloudItem item) {
  if (item.isFolder) return 'Folder';
  final parent = p.basename(p.dirname(item.path));
  final location = parent.isEmpty || parent == '.' || parent == '/'
      ? 'Home'
      : parent;
  return '${formatBytes(item.size)} · $location';
}

enum _DetailsTab { info, versions, activity }

/// Reusable "Details" bottom sheet/dialog for a single file/folder - Info,
/// Versions and Activity switched by a segmented control (there's no
/// tab-strip component in the noo kit, so this is the closest fit - see the
/// rebuild report). Sharing lives in its own sheet ([ShareSheet]), triggered
/// separately from wherever a "Share" action appears. Triggered from
/// long-press selection (exactly one item), the media viewer's action bar,
/// and the "open externally" flow for unsupported file types.
///
/// Only used directly on mobile (bundles its own [NooOverlayHeader]); the
/// desktop path in [show] passes [_DetailsBody] straight to [showNooDialog],
/// which renders the header itself via `leading`/`title`/`subtitle`.
class DetailsSheet extends StatelessWidget {
  final NextcloudItem item;

  const DetailsSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, NextcloudItem item) {
    if (NooLayout.isDesktop(context)) {
      return showNooDialog(
        context,
        leading: detailsFileTile(item),
        title: item.name,
        subtitle: detailsMetaLine(item),
        children: [_DetailsBody(item: item)],
      );
    }
    return showNooSheet(context, children: [DetailsSheet(item: item)]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NooOverlayHeader(
          leading: detailsFileTile(item),
          title: item.name,
          subtitle: detailsMetaLine(item),
          onClose: () => Navigator.pop(context),
        ),
        const SizedBox(height: NooSpace.lg),
        _DetailsBody(item: item),
      ],
    );
  }
}

/// The segmented control plus whichever tab's content it selects. A private
/// [StatefulWidget] rather than three fields on [DetailsSheet] so the
/// selection survives independently of how the header/container around it
/// is built (mobile embeds this once, desktop hands it to [showNooDialog]
/// directly). All three tabs are built once and kept mounted in an
/// [IndexedStack] rather than swapped in/out of the tree - Versions and
/// Activity each fetch on their own first build (see their `_requested`
/// guard), so switching tabs via a bare `switch` on the selected type would
/// tear down and rebuild whichever tab isn't showing, discarding its
/// fetched data and re-requesting it every time the user switched back.
class _DetailsBody extends StatefulWidget {
  final NextcloudItem item;

  const _DetailsBody({required this.item});

  @override
  State<_DetailsBody> createState() => _DetailsBodyState();
}

class _DetailsBodyState extends State<_DetailsBody> {
  _DetailsTab _tab = _DetailsTab.info;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NooSegmentedControl<_DetailsTab>(
          onSurface: true,
          fill: true,
          value: _tab,
          onChanged: (tab) => setState(() => _tab = tab),
          options: const [
            NooSegmentOption(
              value: _DetailsTab.info,
              icon: LucideIcons.info,
              label: 'Info',
            ),
            NooSegmentOption(
              value: _DetailsTab.versions,
              icon: LucideIcons.history,
              label: 'Versions',
            ),
            NooSegmentOption(
              value: _DetailsTab.activity,
              icon: LucideIcons.activity,
              label: 'Activity',
            ),
          ],
        ),
        const SizedBox(height: NooSpace.lg),
        IndexedStack(
          index: _tab.index,
          children: [
            DetailsInfoTab(item: widget.item),
            DetailsVersionsTab(item: widget.item),
            DetailsActivityTab(item: widget.item),
          ],
        ),
      ],
    );
  }
}
