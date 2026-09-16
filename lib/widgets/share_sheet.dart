import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';
import '../providers/server_provider.dart';
import 'gradual_bottom_sheet.dart';

IconData _shareTypeIcon(ShareType type) {
  switch (type) {
    case ShareType.user:
      return Icons.person_rounded;
    case ShareType.group:
      return Icons.groups_rounded;
    case ShareType.publicLink:
      return Icons.link_rounded;
    case ShareType.email:
      return Icons.email_rounded;
    case ShareType.federated:
      return Icons.public_rounded;
    case ShareType.other:
      return Icons.share_rounded;
  }
}

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

/// Standalone "Share" bottom sheet for a single file/folder — replicates
/// the web client's Sharing panel: search users/teams, "Others with
/// access" (inherited shares), an internal link to copy, an email-share
/// field, and a public link. Every "Share" action in the app (swipe,
/// multi-select, media viewer) opens this same sheet.
class ShareSheet extends StatefulWidget {
  final NextcloudItem item;
  final ScrollController? scrollController;

  const ShareSheet({super.key, required this.item, this.scrollController});

  static Future<void> show(BuildContext context, NextcloudItem item) {
    return showGradualBottomSheet(
      context,
      builder: (context, scrollController) =>
          ShareSheet(item: item, scrollController: scrollController),
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
  final _searchController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<ServerProvider>();
    final results = await Future.wait([
      provider.fetchItemShares(widget.item),
      provider.fetchInheritedShares(widget.item),
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
    final provider = context.read<ServerProvider>();
    final results = await provider.searchSharees(trimmed);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
  }

  Future<void> _addSharee(NextcloudSharee sharee) async {
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final share = await provider.createShare(
      path: widget.item.path,
      shareType: sharee.shareTypeValue,
      shareWith: sharee.shareWith,
    );
    if (!mounted) return;
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
      _searchController.clear();
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Shared with ${sharee.label}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _addEmailShare() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final share = await provider.createShare(
      path: widget.item.path,
      shareType: 4,
      shareWith: email,
    );
    if (!mounted) return;
    if (share == null) {
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
      _emailController.clear();
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text('Shared with $email'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createPublicLink() async {
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final share = await provider.createShare(
      path: widget.item.path,
      shareType: 3,
    );
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
    final provider = context.read<ServerProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deleteShare(share);
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

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _sectionHeader(String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.info_outline_rounded,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      ],
    );
  }

  Widget _shareRow(
    NextcloudShare share, {
    bool removable = true,
    bool copyUrl = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = switch (share.shareType) {
      ShareType.publicLink => 'Public link',
      _ => share.sharedWithDisplayName ?? 'Shared',
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        _shareTypeIcon(share.shareType),
        color: colorScheme.primary,
      ),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (copyUrl && share.url != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy link',
              onPressed: () => _copy(share.url!, 'link'),
            ),
          if (removable)
            IconButton(
              icon: Icon(Icons.close_rounded, color: colorScheme.error),
              tooltip: 'Remove',
              onPressed: () => _removeShare(share),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      _requested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final userGroupShares = _shares
        .where(
          (s) =>
              s.shareType == ShareType.user || s.shareType == ShareType.group,
        )
        .toList();
    final publicLinkShares = _shares
        .where((s) => s.shareType == ShareType.publicLink)
        .toList();
    final emailShares = _shares
        .where((s) => s.shareType == ShareType.email)
        .toList();
    final internalLink = internalLinkFor(provider.serverUrl, widget.item.id);

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          widget.item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _sectionHeader('Internal shares'),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Type names or teams',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
          onChanged: _search,
        ),
        for (final sharee in _searchResults)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              sharee.type == ShareeType.group
                  ? Icons.groups_rounded
                  : Icons.person_rounded,
            ),
            title: Text(sharee.label),
            subtitle: sharee.subtitle != null ? Text(sharee.subtitle!) : null,
            onTap: () => _addSharee(sharee),
          ),
        for (final share in userGroupShares) _shareRow(share),
        if (_inherited.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: const Icon(Icons.more_horiz_rounded),
            title: Text('Others with access (${_inherited.length})'),
            children: [
              for (final share in _inherited)
                _shareRow(share, removable: false),
            ],
          ),
        if (internalLink != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.link_rounded),
            title: const Text('Internal link'),
            subtitle: const Text('For people who already have access'),
            trailing: IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy link',
              onPressed: () => _copy(internalLink, 'internal link'),
            ),
          ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),
        _sectionHeader('External shares'),
        const SizedBox(height: 8),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'Type an email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
          ),
          onSubmitted: (_) => _addEmailShare(),
        ),
        for (final share in emailShares) _shareRow(share),
        const SizedBox(height: 8),
        for (final share in publicLinkShares) _shareRow(share, copyUrl: true),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.link_rounded),
          title: const Text('Create public link'),
          trailing: IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Create public link',
            onPressed: _createPublicLink,
          ),
        ),
      ],
    );
  }
}
