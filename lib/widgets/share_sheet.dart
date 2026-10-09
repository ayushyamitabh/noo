import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';
import '../providers/item_operations.dart';
import '../providers/session_controller.dart';
import '../providers/sync_status_controller.dart';
import '../theme/design_tokens.dart';
import 'details/details_sheet.dart' show detailsFileTile, detailsMetaLine;
import 'noo/core/noo_avatar.dart';
import 'noo/core/noo_button.dart';
import 'noo/core/noo_chip.dart';
import 'noo/core/noo_toggle.dart';
import 'noo/lists/noo_grouped_list.dart';
import 'noo/lists/noo_settings_row.dart';
import 'noo/media/noo_photo_tile.dart';
import 'noo/noo_layout.dart';
import 'noo/overlays/noo_dialog.dart';
import 'noo/overlays/noo_overlay_header.dart';
import 'noo/overlays/noo_share_parts.dart';
import 'noo/overlays/noo_sheet.dart';
import 'noo/overlays/noo_text_field.dart';

/// Builds the "internal link" URL for a file, or null if [fileId] isn't a
/// numeric Nextcloud file id (WebDAV `oc:fileid` was missing for this item).
String? internalLinkFor(String serverUrl, String fileId) {
  if (int.tryParse(fileId) == null) return null;
  var url = serverUrl.trim();
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'https://$url';
  }
  if (url.endsWith('/')) url = url.substring(0, url.length - 1);
  return '$url/index.php/f/$fileId';
}

String _initial(String s) {
  final trimmed = s.trim();
  return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
}

/// Standalone "Share" bottom sheet/dialog for a single file/folder -
/// `DESIGN_SYSTEM.md` §4 "Share sheet / dialog": share with people, a
/// public link, and (files only) sending the file itself. Every "Share"
/// action in the app (swipe, multi-select, media viewer) opens this same
/// sheet.
///
/// Only used directly on mobile (bundled behind its own [NooOverlayHeader]
/// by [show]); the desktop path hands this straight to [showNooDialog],
/// which renders the header itself via `leading`/`title`/`subtitle`.
class ShareSheet extends StatefulWidget {
  final NextcloudItem item;

  const ShareSheet({super.key, required this.item});

  static Future<void> show(BuildContext context, NextcloudItem item) {
    if (NooLayout.isDesktop(context)) {
      return showNooDialog(
        context,
        leading: detailsFileTile(item),
        title: item.name,
        subtitle: detailsMetaLine(item),
        children: [ShareSheet(item: item)],
      );
    }
    return showNooSheet(
      context,
      children: [
        Builder(
          builder: (sheetContext) => NooOverlayHeader(
            leading: detailsFileTile(item),
            title: item.name,
            subtitle: detailsMetaLine(item),
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
        ShareSheet(item: item),
      ],
    );
  }

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  bool _requested = false;
  bool _isLoading = true;
  List<NextcloudShare> _shares = [];
  List<NextcloudShare> _inherited = [];
  List<NextcloudSharee> _searchResults = [];
  bool _isSearching = false;
  bool _isAddingPerson = false;
  bool _isTogglingLink = false;
  String? _pendingShareeKey;
  final Set<String> _updatingShareIds = {};
  bool _isSharingFile = false;
  bool _showInherited = false;
  final _peopleController = TextEditingController();
  final _linkController = TextEditingController();
  final _peopleFocus = FocusNode();
  final _peopleKey = GlobalKey();

  /// Once the user types, scrolls the sheet so the people field and its
  /// results (under their title) sit near the top, leaving a little room under the sheet's
  /// rounded top edge.
  void _revealPeopleSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _peopleKey.currentContext;
      final box = ctx?.findRenderObject();
      if (ctx == null || box is! RenderBox) return;
      final position = Scrollable.maybeOf(ctx)?.position;
      final viewport = RenderAbstractViewport.maybeOf(box);
      if (position == null || viewport == null) return;
      final target = (viewport.getOffsetToReveal(box, 0).offset - 8).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _peopleFocus.dispose();
    _peopleController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ops = context.read<ItemOperations>();
    final results = await Future.wait([
      ops.fetchItemShares(widget.item),
      ops.fetchInheritedShares(widget.item),
    ]);
    if (!mounted) return;
    setState(() {
      _shares = results[0];
      _inherited = results[1];
      _isLoading = false;
    });
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    _revealPeopleSection();
    final ops = context.read<ItemOperations>();
    final results = await ops.searchSharees(trimmed);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
    _revealPeopleSection();
  }

  /// The single "Name, email or group" field: reuses whichever match is
  /// live, or falls back to an email share when the text looks like one -
  /// same two underlying actions the pre-rework sheet split across two
  /// separate fields.
  Future<void> _submitPeopleField() async {
    final text = _peopleController.text.trim();
    if (text.isEmpty) return;
    if (_searchResults.isNotEmpty) {
      await _addSharee(_searchResults.first);
    } else if (text.contains('@')) {
      await _addEmail(text);
    }
  }

  String _shareeKey(NextcloudSharee s) => '${s.shareTypeValue}:${s.shareWith}';

  Future<void> _addSharee(NextcloudSharee sharee) async {
    if (_pendingShareeKey != null) return;
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingShareeKey = _shareeKey(sharee));
    final share = await ops.createShare(
      path: widget.item.path,
      shareType: sharee.shareTypeValue,
      shareWith: sharee.shareWith,
    );
    if (!mounted) return;
    setState(() => _pendingShareeKey = null);
    if (share == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not share this item'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _shares = [..._shares, share];
      _searchResults = [];
      _peopleController.clear();
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Shared with ${sharee.label}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addEmail(String email) async {
    setState(() => _isAddingPerson = true);
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    final share = await ops.createShare(
      path: widget.item.path,
      shareType: 4,
      shareWith: email,
    );
    if (!mounted) return;
    if (share == null) {
      setState(() => _isAddingPerson = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create email share'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _shares = [..._shares, share];
      _peopleController.clear();
      _isAddingPerson = false;
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Shared with $email'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createPublicLink() async {
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    final share = await ops.createShare(path: widget.item.path, shareType: 3);
    if (!mounted) return;
    if (share == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not create public link'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _shares = [..._shares, share]);
  }

  Future<void> _removeShare(NextcloudShare share) async {
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await ops.deleteShare(share);
    if (!mounted) return;
    if (success) {
      setState(() => _shares = _shares.where((s) => s.id != share.id).toList());
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not remove share'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// The link toggle: on creates a public link, off removes every public
  /// link share (there's normally at most one - the sheet only ever
  /// surfaces the first one - but this cleans up any extras from before the
  /// rework's single-link toggle).
  Future<void> _toggleLink(bool checked) async {
    setState(() => _isTogglingLink = true);
    if (checked) {
      await _createPublicLink();
    } else {
      final links = _shares
          .where((s) => s.shareType == ShareType.publicLink)
          .toList();
      for (final link in links) {
        await _removeShare(link);
      }
    }
    if (mounted) setState(() => _isTogglingLink = false);
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Downloads the item to a scratch file and hands it to the OS's native
  /// "Share to..." sheet (`share_plus`) - a completely different action from
  /// the rest of this sheet (which shares *within* Nextcloud, via users/
  /// links) and the only one here that reads the file's actual bytes.
  Future<void> _shareFileDirectly() async {
    final session = context.read<SessionController>();
    final sync = context.read<SyncStatusController>();
    if (session.service == null) return;
    setState(() => _isSharingFile = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Already mirrored locally by device sync? Share that copy straight
      // away instead of a fresh WebDAV fetch - see
      // SyncStatusController.localSyncedFilePath.
      final tempPath =
          await sync.localSyncedFilePath(widget.item) ??
          await () async {
            final tempDir = await getTemporaryDirectory();
            final path = p.join(tempDir.path, widget.item.name);
            await session.service!.downloadToFile(widget.item.path, path);
            return path;
          }();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempPath)],
          fileNameOverrides: [widget.item.name],
        ),
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not share the file'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharingFile = false);
    }
  }

  /// Permission menu for a person row: Can view / Can edit, then removing
  /// access. Keeps the reshare bit (16) as it was.
  void _openPersonMenu(NextcloudShare share) {
    final label = share.sharedWithDisplayName ?? 'Shared';
    final canEdit = (share.permissions & 2) != 0;

    void remove() {
      Navigator.pop(context);
      _removeShare(share);
    }

    void choose(bool edit) {
      Navigator.pop(context);
      _setPermission(share, edit);
    }

    Widget check(bool on) => Icon(
      LucideIcons.check,
      size: 18,
      color: on ? context.nooColors.accentText : Colors.transparent,
    );

    final rows = <Widget>[
      NooSettingsRow(
        icon: LucideIcons.eye,
        label: const Text('Can view'),
        trailing: check(!canEdit),
        onTap: () => choose(false),
      ),
      NooSettingsRow(
        icon: LucideIcons.pencil,
        label: const Text('Can edit'),
        trailing: check(canEdit),
        onTap: () => choose(true),
      ),
      NooSettingsRow(
        icon: LucideIcons.userMinus,
        label: const Text('Remove access'),
        danger: true,
        onTap: remove,
      ),
    ];
    if (NooLayout.isDesktop(context)) {
      showNooDialog(
        context,
        title: label,
        children: [Column(children: rows)],
      );
    } else {
      showNooSheet(
        context,
        children: [
          NooOverlayHeader(title: label, onClose: () => Navigator.pop(context)),
          NooGroupedList(children: rows),
        ],
      );
    }
  }

  Future<void> _setPermission(NextcloudShare share, bool edit) async {
    if (((share.permissions & 2) != 0) == edit) return;
    final ops = context.read<ItemOperations>();
    final messenger = ScaffoldMessenger.of(context);
    final reshare = share.permissions & 16;
    final base = edit ? (share.isFolder ? 15 : 3) : 1;
    final permissions = base | reshare;
    setState(() => _updatingShareIds.add(share.id));
    final ok = await ops.updateSharePermissions(share, permissions);
    if (!mounted) return;
    setState(() => _updatingShareIds.remove(share.id));
    if (ok) {
      setState(() {
        _shares = [
          for (final s in _shares)
            s.id == share.id ? s.withPermissions(permissions) : s,
        ];
      });
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not change permission'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _peopleSection(
    NooColors colors,
    SessionController session,
    List<NextcloudShare> peopleShares,
    String? internalLink,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AbsorbPointer(
          absorbing: _isAddingPerson,
          child: NooTextField(
            controller: _peopleController,
            focusNode: _peopleFocus,
            leadingIcon: LucideIcons.search,
            placeholder: 'Name, email or group',
            onChanged: _search,
            onSubmitted: (_) => _submitPeopleField(),
            trailing: (_isSearching || _isAddingPerson)
                ? const Padding(
                    padding: EdgeInsets.all(4),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        for (final sharee in _searchResults)
          InkWell(
            borderRadius: BorderRadius.circular(NooRadii.input),
            onTap: _pendingShareeKey == null ? () => _addSharee(sharee) : null,
            child: NooPersonAccessRow(
              avatar: NooAvatar(
                initials: _initial(sharee.label),
                color: NooPhotoTile.paletteColor(sharee.label.hashCode),
                icon: sharee.type == ShareeType.group
                    ? LucideIcons.users
                    : null,
              ),
              name: sharee.label,
              subtitle: sharee.subtitle,
              trailing: _pendingShareeKey == _shareeKey(sharee)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        if (_searchResults.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: NooSpace.xs),
            child: Divider(height: 1, thickness: 1, color: colors.line),
          )
        else
          const SizedBox(height: NooSpace.xs),
        NooPersonAccessRow(
          avatar: NooAvatar(
            initials: _initial(session.displayName),
            current: true,
          ),
          name: session.displayName,
          owner: true,
        ),
        for (final share in peopleShares)
          NooPersonAccessRow(
            avatar: NooAvatar(
              initials: _initial(share.sharedWithDisplayName ?? share.id),
              color: NooPhotoTile.paletteColor(
                (share.sharedWithDisplayName ?? share.id).hashCode,
              ),
              icon: share.shareType == ShareType.group
                  ? LucideIcons.users
                  : null,
            ),
            name: share.sharedWithDisplayName ?? 'Shared',
            subtitle: share.shareType == ShareType.group
                ? 'Group'
                : (share.shareType == ShareType.email
                      ? 'Invited by email'
                      : null),
            permission: (share.permissions & 2) != 0 ? 'Can edit' : 'Can view',
            permissionLoading: _updatingShareIds.contains(share.id),
            onPermissionTap: _updatingShareIds.contains(share.id)
                ? null
                : () => _openPersonMenu(share),
          ),
        if (_inherited.isNotEmpty) ...[
          const SizedBox(height: NooSpace.xs),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showInherited = !_showInherited),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: NooSpace.xs),
              child: Row(
                children: [
                  Icon(LucideIcons.users, size: 16, color: colors.fg3),
                  const SizedBox(width: NooSpace.xs),
                  Expanded(
                    child: Text(
                      'Others with access (${_inherited.length})',
                      style: NooText.meta.copyWith(color: colors.fg3),
                    ),
                  ),
                  Icon(
                    _showInherited
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 16,
                    color: colors.fg3,
                  ),
                ],
              ),
            ),
          ),
          if (_showInherited)
            for (final share in _inherited)
              Padding(
                padding: const EdgeInsets.only(bottom: NooSpace.xs),
                child: NooPersonAccessRow(
                  avatar: NooAvatar(
                    initials: _initial(
                      share.sharedWithDisplayName ?? share.ownerDisplayName,
                    ),
                  ),
                  name: share.sharedWithDisplayName ?? share.ownerDisplayName,
                  owner: true,
                  ownerLabel: 'Inherited',
                ),
              ),
        ],
        if (internalLink != null) ...[
          const SizedBox(height: NooSpace.xs),
          Row(
            children: [
              Icon(LucideIcons.link, size: 18, color: colors.fg3),
              const SizedBox(width: NooSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Internal link',
                      style: NooText.bodyL.copyWith(color: colors.fg1),
                    ),
                    Text(
                      'For people who already have access',
                      style: NooText.meta.copyWith(color: colors.fg3),
                    ),
                  ],
                ),
              ),
              NooButton(
                size: NooButtonSize.compact,
                variant: NooButtonVariant.secondary,
                icon: LucideIcons.copy,
                onTap: () => _copy(internalLink, 'internal link'),
                child: const Text('Copy'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _linkSection(NextcloudShare link) {
    final canEdit = (link.permissions & 2) != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NooTextField(
          controller: _linkController,
          mono: true,
          readOnly: true,
          trailing: NooButton(
            size: NooButtonSize.field,
            icon: LucideIcons.copy,
            onTap: () => _copy(link.url ?? '', 'link'),
            child: const Text('Copy link'),
          ),
        ),
        const SizedBox(height: NooSpace.sm),
        Wrap(
          spacing: NooSpace.xs,
          runSpacing: NooSpace.xs,
          children: [
            NooChip(child: Text(canEdit ? 'Can edit' : 'View only')),
            NooChip(
              child: Text(
                link.expireDate != null
                    ? 'Expires ${DateFormat.yMMMd().format(link.expireDate!)}'
                    : 'No expiry',
              ),
            ),
          ],
        ),
      ],
    );
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
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final peopleShares = _shares
        .where(
          (s) =>
              s.shareType == ShareType.user ||
              s.shareType == ShareType.group ||
              s.shareType == ShareType.email,
        )
        .toList();
    final publicLinkShares = _shares
        .where((s) => s.shareType == ShareType.publicLink)
        .toList();
    final hasLink = publicLinkShares.isNotEmpty;
    if (hasLink) {
      final url = publicLinkShares.first.url ?? '';
      if (_linkController.text != url) _linkController.text = url;
    }
    final internalLink = internalLinkFor(session.serverUrl, widget.item.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NooShareSection(
          key: _peopleKey,
          title: 'Share with people',
          child: _peopleSection(colors, session, peopleShares, internalLink),
        ),
        const SizedBox(height: 22),
        NooShareSection(
          title: 'Share link',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isTogglingLink) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: NooSpace.sm),
              ],
              NooToggle(
                checked: hasLink,
                onChanged: _isTogglingLink ? null : _toggleLink,
              ),
            ],
          ),
          caption: hasLink
              ? null
              : 'Anyone with the link can access this ${widget.item.isFolder ? 'folder' : 'file'}.',
          child: hasLink
              ? _linkSection(publicLinkShares.first)
              : const SizedBox.shrink(),
        ),
        if (!widget.item.isFolder) ...[
          const SizedBox(height: 22),
          NooShareSection(
            title: 'Send file directly',
            caption:
                "Link settings above don't apply - this sends the file's bytes directly.",
            child: NooButton(
              variant: NooButtonVariant.outline,
              size: NooButtonSize.card,
              fullWidth: true,
              icon: LucideIcons.send,
              disabled: _isSharingFile,
              onTap: _isSharingFile ? null : _shareFileDirectly,
              child: Text(_isSharingFile ? 'Preparing…' : 'Send file directly'),
            ),
          ),
        ],
      ],
    );
  }
}
