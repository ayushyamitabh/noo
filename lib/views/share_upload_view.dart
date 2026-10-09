import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/app_tab.dart';
import '../models/nextcloud_item.dart';
import '../providers/files_controller.dart';
import '../providers/session_controller.dart';
import '../providers/settings_controller.dart';
import '../services/share_intent_service.dart';
import '../services/upload_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/breadcrumbs.dart';
import '../widgets/files_controls_row.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/files/noo_file_kind.dart';
import '../widgets/noo/files/noo_file_row.dart';
import '../widgets/noo/files/noo_file_table.dart';
import '../widgets/noo/media/noo_grid_card.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/nav/noo_toolbar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/shell/shell_common.dart';
import '../widgets/tabs/tab_state_slivers.dart';

/// Shown when another app shares one or more files to Noo (Android's
/// "Share to..." sheet). Lets the user browse to a destination folder,
/// reusing `FilesController`'s shared folder-browsing state so this feels
/// like the same browser Files itself uses, then hands the actual
/// prepare+upload off to [UploadService] - a real Android foreground
/// service (see `ShareUploadService.kt`'s doc comment), not something this
/// screen or even the app needs to stay open for. [files] only ever carry
/// cheap Uri metadata (see [ShareIntentService]'s doc comment); that
/// service is the only thing that ever reads their actual bytes. Pushed
/// via `Navigator` from outside `MainShellView` (a cold share-intent
/// launch, or Files' own "+" -> "Upload file"), so - unlike a tab - it
/// builds its own complete top chrome rather than relying on the shell's.
class ShareUploadView extends StatefulWidget {
  final List<SharedFileRef> files;

  const ShareUploadView({super.key, required this.files});

  @override
  State<ShareUploadView> createState() => _ShareUploadViewState();
}

class _ShareUploadViewState extends State<ShareUploadView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Shared files have no relationship to wherever the user was last
    // browsing, so start the destination picker fresh at the root.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<FilesController>().navigateToAbsoluteFolder('/');
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _uploadHere(SessionController session) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final files = context.read<FilesController>();
    final settings = context.read<SettingsController>();
    try {
      await UploadService.startUpload(session, files, widget.files);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not start upload: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    settings.requestTab(AppTab.files);
    navigator.popUntil((route) => route.isFirst);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          widget.files.length == 1
              ? 'Uploading ${widget.files.first.name} - see the notification for progress'
              : 'Uploading ${widget.files.length} files - see the notification for progress',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Only folders are valid upload destinations, so the listing - unlike
  // Files' own - never shows plain files at all.
  Widget _buildRow(
    BuildContext context,
    NextcloudItem item,
    int index,
    int count,
  ) {
    final colors = context.nooColors;
    final files = context.read<FilesController>();
    final row = NooFileRow(
      kind: NooFileKind.folder,
      name: item.name,
      meta: 'Folder',
      iosStyle: NooLayout.iosStyle(context),
      onTap: () => files.navigateToFolder(item.path),
    );

    final isFirst = index == 0;
    final isLast = index == count - 1;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: isFirst ? const Radius.circular(NooRadii.card) : Radius.zero,
            bottom: isLast ? const Radius.circular(NooRadii.card) : Radius.zero,
          ),
          child: row,
        ),
        if (!isLast) Container(height: 1, color: colors.line),
      ],
    );
  }

  Widget _buildDesktopRow(BuildContext context, NextcloudItem item) {
    final files = context.read<FilesController>();
    return NooFileTableRow(
      kind: NooFileKind.folder,
      name: item.name,
      onTap: () => files.navigateToFolder(item.path),
    );
  }

  Widget _buildGridCard(BuildContext context, NextcloudItem item) {
    final colors = context.nooColors;
    final files = context.read<FilesController>();
    return NooGridCard(
      name: item.name,
      meta: 'Folder',
      placeholderColor: colors.accentSoft,
      icon: LucideIcons.folder,
      iconColor: colors.accentText,
      thumbnailHeight: NooLayout.isDesktop(context) ? 118 : 104,
      onTap: () => files.navigateToFolder(item.path),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final desktop = NooLayout.isDesktop(context);
    final files = context.watch<FilesController>();
    final session = context.watch<SessionController>();
    final hasBreadcrumbs = files.pathStack.length > 1;
    final currentPath = files.pathStack.last;
    final currentLabel = currentPath == '/'
        ? 'Home'
        : currentPath.split('/').where((s) => s.isNotEmpty).last;
    final folders = files.items.where((item) => item.isFolder).toList();
    final gutter = NooLayout.gutter(context);

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            gutter,
            NooSpace.md,
            gutter,
            NooSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 44,
                child: FilesControlsRow(folderPath: currentPath),
              ),
              if (hasBreadcrumbs) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 32,
                  child: Breadcrumbs(
                    pathStack: files.pathStack,
                    onTap: (index) => files.navigateToPathIndex(index),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      if (files.isLoading)
        tabLoadingSliver
      else if (folders.isEmpty)
        tabEmptySliver(
          context,
          icon: LucideIcons.folder,
          message: 'No folders here',
        )
      else if (files.isGridView)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverGrid(
            gridDelegate: NooLayout.fileGridDelegate(context),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildGridCard(context, folders[index]),
              childCount: folders.length,
            ),
          ),
        )
      else if (desktop)
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildDesktopRow(context, folders[index]),
              childCount: folders.length,
            ),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: gutter),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _buildRow(context, folders[index], index, folders.length),
              childCount: folders.length,
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: NooSpace.xl)),
    ];

    final title = 'Upload to...';

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: desktop
          ? NooToolbar(
              title: title,
              actions: [
                NooButton(
                  variant: NooButtonVariant.secondary,
                  size: NooButtonSize.toolbar,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ],
            )
          : NooTopBar(
              style: NooLayout.navStyle(context),
              title: title,
              leading: const NooTopBarBack(label: 'Cancel'),
              // Same top-bar access as every tab (avatar -> Settings, swipe
              // to switch accounts) - nothing else belongs here: jumping to
              // another tab mid-upload would abandon this destination
              // picker, so there's no "more tabs" entry.
              actions: const [ShellAvatarButton()],
            ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: colors.accent,
          backgroundColor: colors.surface,
          onRefresh: files.refreshData,
          child: CustomScrollView(
            controller: _scrollController,
            // See files_view.dart's identical fix - without this, pull-to-
            // refresh can't be triggered on an empty or single-folder
            // listing.
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: slivers,
          ),
        ),
      ),
      // A flat surface bar with a top line, peeking up from the bottom edge -
      // a centered item-count meta line sits directly above the destination
      // button (DESIGN_SYSTEM.md's "Upload / Move / Copy destination
      // picker" recipe: "a meta line ... above a full-width ... primary
      // CTA" - matches MoveCopyDestinationPicker's identical bar). A count,
      // not a filename: this is the one-file case just as much as the
      // many-files case, and a long filename has no good fixed-width
      // treatment the way a short count always does.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              NooSpace.lg,
              NooSpace.md,
              NooSpace.lg,
              NooSpace.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Uploading ${widget.files.length} item${widget.files.length == 1 ? '' : 's'}',
                  textAlign: TextAlign.center,
                  style: NooText.meta.copyWith(color: colors.fg3),
                ),
                const SizedBox(height: NooSpace.sm),
                NooButton(
                  variant: NooButtonVariant.primary,
                  size: NooButtonSize.cta,
                  fullWidth: true,
                  icon: LucideIcons.upload,
                  onTap: () => _uploadHere(session),
                  child: Text('Upload to $currentLabel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
