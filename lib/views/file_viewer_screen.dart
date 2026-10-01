import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../models/nextcloud_item.dart';
import '../providers/item_operations.dart';
import '../providers/session_controller.dart';
import '../services/download_service.dart';
import '../theme/design_tokens.dart';
import '../widgets/details/details_sheet.dart';
import '../widgets/frosted_glass_container.dart';
import '../widgets/marquee_title.dart';
import '../widgets/noo/core/noo_button.dart';
import '../widgets/noo/nav/noo_top_bar.dart';
import '../widgets/noo/noo_layout.dart';
import '../widgets/noo/overlays/noo_dialog.dart';
import '../widgets/noo/overlays/noo_overlay_header.dart';
import '../widgets/noo/overlays/noo_sheet.dart';
import '../widgets/share_sheet.dart';
import '../widgets/viewer/media_action_bar.dart';
import '../widgets/viewer/media_image_preview.dart';
import '../widgets/viewer/media_pdf_preview.dart';
import '../widgets/viewer/media_text_preview.dart';
import '../widgets/viewer/media_unsupported_preview.dart';
import '../widgets/viewer/media_video_preview.dart';

const _textPreviewExtensions = {
  '.txt',
  '.md',
  '.json',
  '.yaml',
  '.yml',
  '.xml',
  '.log',
  '.csv',
  '.dart',
  '.js',
  '.ts',
  '.py',
  '.java',
  '.kt',
  '.swift',
  '.c',
  '.cpp',
  '.h',
  '.sh',
  '.bat',
  '.ini',
  '.conf',
  '.gradle',
  '.html',
  '.css',
};

class FileViewerScreen extends StatefulWidget {
  final NextcloudItem item;

  /// The other items in the same folder/album, so images and videos can be
  /// swiped through without leaving the viewer. Non-media items in this list
  /// are ignored. If omitted (or the item isn't an image/video), the viewer
  /// just shows [item] on its own. Works the same way whether or not
  /// [localPathResolver] is set - swiping through offline media resolves
  /// each sibling's local path on demand, exactly like Files/Photos.
  final List<NextcloudItem>? siblings;

  /// When set, every preview (and "open externally") resolves its file
  /// from local disk through this instead of fetching from the server -
  /// used by the Offline tab, whose whole point is browsing already-
  /// downloaded files with no connection. Called once per item actually
  /// shown (the initial item and each swiped-to sibling), not just up
  /// front. Actions that need a live server (favorite/delete/download-to-
  /// device) hide themselves in this mode; Share/Open-externally/Details
  /// still work (Share already prefers the local copy when one exists -
  /// see `ShareSheet._shareFileDirectly` - and Details' shares/activity/
  /// versions tabs degrade the same way any other offline server call
  /// does).
  final Future<String?> Function(NextcloudItem item)? localPathResolver;

  const FileViewerScreen({
    super.key,
    required this.item,
    this.siblings,
    this.localPathResolver,
  });

  /// Opens the viewer with no page transition — media should appear
  /// instantly, not fade/zoom in the way MaterialPageRoute normally would.
  /// Going *back* still uses the theme's normal (predictive-back-capable)
  /// transition, via [_InstantOpenPageRoute] below.
  static Route<void> route({
    required NextcloudItem item,
    List<NextcloudItem>? siblings,
    Future<String?> Function(NextcloudItem item)? localPathResolver,
  }) {
    return _InstantOpenPageRoute<void>(
      pageBuilder: (context) => FileViewerScreen(
        item: item,
        siblings: siblings,
        localPathResolver: localPathResolver,
      ),
    );
  }

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

/// A [PageRoute] that opens instantly (zero-duration forward transition)
/// but still delegates to the app's [PageTransitionsTheme] for the reverse
/// transition — unlike a plain [PageRouteBuilder] with no transitionsBuilder,
/// which never consults the theme and so can't participate in Android's
/// predictive-back gesture at all.
class _InstantOpenPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _InstantOpenPageRoute({required this.pageBuilder, super.settings});

  final WidgetBuilder pageBuilder;

  @override
  Widget buildContent(BuildContext context) => pageBuilder(context);

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  double? _downloadProgress;
  bool _isBusy = false;
  bool _controlsVisible = true;

  late final bool _isSwipeable;
  late final List<NextcloudItem> _mediaItems;
  late int _currentIndex;
  late final PageController _pageController;

  /// The active page's video controller, once `MediaVideoPreview` reports
  /// it - only ever set by the *current* page (see `_buildBody`), so a
  /// neighboring `PageView` page can't steal the transport row. Drives
  /// `VideoTransportControls` inside the bottom `MediaActionBar` panel.
  VideoPlayerController? _videoController;

  /// Whether the *current* page's `MediaImagePreview` is zoomed in - see
  /// `_buildBody`'s `onZoomChanged`. Disables the `PageView`'s own
  /// left/right swipe while true, so panning around a zoomed photo doesn't
  /// also drag the gallery to the next item.
  bool _isZoomed = false;

  NextcloudItem get _currentItem => _mediaItems[_currentIndex];

  bool get _isOffline => widget.localPathResolver != null;

  bool get _isPdf => _currentItem.name.toLowerCase().endsWith('.pdf');
  bool get _isText => _textPreviewExtensions.contains(
    p.extension(_currentItem.name).toLowerCase(),
  );

  @override
  void initState() {
    super.initState();
    _isSwipeable =
        widget.item.type == NextcloudItemType.image ||
        widget.item.type == NextcloudItemType.video;

    if (_isSwipeable) {
      final source = widget.siblings ?? [widget.item];
      _mediaItems = source
          .where(
            (i) =>
                i.type == NextcloudItemType.image ||
                i.type == NextcloudItemType.video,
          )
          .toList();
      if (_mediaItems.isEmpty) _mediaItems = [widget.item];
      final idx = _mediaItems.indexWhere((i) => i.path == widget.item.path);
      _currentIndex = idx >= 0 ? idx : 0;
    } else {
      _mediaItems = [widget.item];
      _currentIndex = 0;
    }
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<String> _downloadToTemp(
    SessionController session,
    NextcloudItem item,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final savePath = p.join(tempDir.path, item.name);
    setState(() => _downloadProgress = 0);
    await session.service!.downloadToFile(
      item.path,
      savePath,
      onProgress: (received, total) {
        if (total > 0 && mounted) {
          setState(() => _downloadProgress = received / total);
        }
      },
    );
    if (mounted) setState(() => _downloadProgress = null);
    return savePath;
  }

  Future<void> _openExternally(SessionController session) async {
    final item = _currentItem;
    setState(() => _isBusy = true);
    try {
      final path = _isOffline
          ? await widget.localPathResolver!(item)
          : await _downloadToTemp(session, item);
      if (path == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This file is no longer available offline'),
            ),
          );
        }
        return;
      }
      final result = await OpenFile.open(path);
      if (mounted && result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file: ${result.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open ${item.name}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Hands off to `DownloadService.kt` (see its doc comment) rather than
  /// downloading in Dart then prompting `file_saver` - same reasoning as
  /// `UploadService`/`ShareUploadService.kt` on the upload side: a real
  /// Android Service survives the app being closed mid-download, and one
  /// notification covers progress/cancel instead of blocking this screen.
  Future<void> _downloadToDevice(SessionController session) async {
    final item = _currentItem;
    try {
      await DownloadService.startDownload(session, [item]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Downloading ${item.name} - see the notification for progress',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Download failed: $e')));
      }
    }
  }

  Future<void> _toggleFavorite(ItemOperations ops) async {
    final item = _currentItem;
    await ops.toggleItemFavorite(item);
    if (!mounted) return;
    setState(() {
      _mediaItems[_currentIndex] = item.copyWith(isFavorite: !item.isFavorite);
    });
  }

  /// Delete confirmation, restyled as [showNooDialog] (desktop) /
  /// [showNooSheet] (mobile) instead of an [AlertDialog] - same pattern as
  /// `confirmRemoveAccount` in `settings_dialogs.dart`.
  Future<bool> _confirmDelete(String name) async {
    var confirmed = false;
    void cancel() => Navigator.pop(context);
    void confirm() {
      confirmed = true;
      Navigator.pop(context);
    }

    Widget buttons() => Row(
      children: [
        Expanded(
          child: NooButton(
            variant: NooButtonVariant.secondary,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: cancel,
            child: const Text('Cancel'),
          ),
        ),
        const SizedBox(width: NooSpace.sm),
        Expanded(
          child: NooButton(
            variant: NooButtonVariant.danger,
            size: NooButtonSize.card,
            fullWidth: true,
            onTap: confirm,
            child: const Text('Delete'),
          ),
        ),
      ],
    );

    final message = 'Delete "$name" from the server? This cannot be undone.';
    final colors = context.nooColors;
    if (NooLayout.isDesktop(context)) {
      await showNooDialog(
        context,
        title: 'Delete file',
        children: [
          Text(message, style: NooText.body.copyWith(color: colors.fg2)),
          buttons(),
        ],
      );
    } else {
      await showNooSheet(
        context,
        children: [
          NooOverlayHeader(title: 'Delete file', onClose: cancel),
          Text(message, style: NooText.body.copyWith(color: colors.fg2)),
          buttons(),
        ],
      );
    }
    return confirmed;
  }

  Future<void> _deleteCurrentItem(ItemOperations ops) async {
    final item = _currentItem;
    final confirmed = await _confirmDelete(item.name);
    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);
    final success = await ops.deleteItem(item.path);
    if (!mounted) return;
    setState(() => _isBusy = false);

    if (!success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete ${item.name}')));
      return;
    }

    setState(() {
      _mediaItems.removeAt(_currentIndex);
      if (_mediaItems.isNotEmpty && _currentIndex >= _mediaItems.length) {
        _currentIndex = _mediaItems.length - 1;
      }
    });

    if (_mediaItems.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    if (_isSwipeable && _pageController.hasClients) {
      _pageController.jumpToPage(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final ops = context.read<ItemOperations>();
    final colors = context.nooColors;
    // The stage follows the app's own theme (`bg`) rather than being pinned
    // to black - a black stage in light mode read as jarringly out of place
    // next to the rest of the light-themed app. The floating top/action
    // bars now follow the theme too (FrostedGlassContainer's own `surface`
    // default), at a higher blur opacity to stay legible over arbitrary
    // photo/video brightness underneath.
    final stageColor = colors.bg;

    return Scaffold(
      backgroundColor: stageColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _controlsVisible = !_controlsVisible),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: stageColor,
                child: _buildBody(context, session),
              ),
            ),
            if (_downloadProgress != null)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(
                  value: _downloadProgress,
                  color: colors.accent,
                  backgroundColor: colors.fg1.withValues(alpha: 0.16),
                ),
              ),
            // Scrim behind the top bar, per the approved canvas
            // (https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4): a plain
            // gradient fade, not `FrostedGlassContainer`'s blur - just
            // enough to keep the back button/title legible over bright
            // media without another blurred layer stacked on the bar itself.
            // Fades toward `surface` (the same tint the panel itself uses),
            // not a fixed black - a black scrim would fight the panel's own
            // theme-matched icons/text (dark in light theme) instead of
            // extending its contrast strategy past the panel's hard edge.
            if (_isSwipeable)
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: _controlsVisible ? 1 : 0,
                  child: Container(
                    height: 150,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colors.surface.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              offset: _controlsVisible ? Offset.zero : const Offset(0, -1.4),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                // The blurred/tinted background lives outside the SafeArea
                // (not inside it) so it extends up behind the status bar
                // instead of stopping short beneath it - see the matching
                // fix/comment on MediaActionBar's own SafeArea.
                child: FrostedGlassContainer(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 6,
                      ),
                      child: IconTheme.merge(
                        // `fg1`, matching FrostedGlassContainer's own
                        // theme-following panel underneath - both used to
                        // be a fixed white-on-black regardless of theme.
                        data: IconThemeData(color: colors.fg1, size: 24),
                        child: Row(
                          children: [
                            NooTopBarButton(
                              icon: LucideIcons.arrowLeft,
                              tooltip: 'Back',
                              onTap: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: MarqueeTitle(
                                text: _currentItem.name,
                                style: NooText.label.copyWith(
                                  color: colors.fg1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isSwipeable)
              Align(
                alignment: Alignment.bottomCenter,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _controlsVisible ? 1 : 0,
                    child: Container(
                      height: 260,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            colors.surface.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOutCubic,
                offset: _controlsVisible ? Offset.zero : const Offset(0, 1.4),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: MediaActionBar(
                    isFavorite: _currentItem.isFavorite,
                    isBusy: _isBusy,
                    // Favorite/delete/download-to-device all need a live
                    // server - hidden rather than shown-and-failing while
                    // browsing an already-local file from the Offline tab.
                    showServerActions: !_isOffline,
                    transportControls:
                        _isSwipeable &&
                            _currentItem.type == NextcloudItemType.video &&
                            _videoController != null
                        ? VideoTransportControls(controller: _videoController!)
                        : null,
                    onShare: () => ShareSheet.show(context, _currentItem),
                    onFavorite: () => _toggleFavorite(ops),
                    onDelete: () => _deleteCurrentItem(ops),
                    onOpenExternally: () => _openExternally(session),
                    onDownload: () => _downloadToDevice(session),
                    onDetails: () => DetailsSheet.show(context, _currentItem),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SessionController session) {
    if (!_isSwipeable) {
      return _buildStaticPreview(context, session);
    }

    return PageView.builder(
      controller: _pageController,
      // Zoomed into the current photo: let InteractiveViewer's own pan
      // claim horizontal drags instead of the PageView swiping to the next
      // item out from under it.
      physics: _isZoomed ? const NeverScrollableScrollPhysics() : null,
      itemCount: _mediaItems.length,
      onPageChanged: (index) => setState(() {
        _currentIndex = index;
        // The outgoing page's `onController` stops being passed below (it's
        // no longer the active index) and reports null on its own dispose,
        // but that can lag a frame or two behind this rebuild - clear
        // eagerly so the transport row never briefly shows the old video.
        _videoController = null;
        // The new page always starts unzoomed - and the old page's own
        // listener is now scoped away from `_isZoomed` (see `isActive`
        // below), so nothing else would reset this.
        _isZoomed = false;
      }),
      itemBuilder: (context, index) {
        final mediaItem = _mediaItems[index];
        final isActive = index == _currentIndex;
        if (!_isOffline) {
          if (mediaItem.type == NextcloudItemType.image) {
            return MediaImagePreview(
              key: ValueKey(mediaItem.id),
              url: session.service!.fileUrl(mediaItem.path),
              headers: session.service!.authHeaders,
              onZoomChanged: isActive
                  ? (zoomed) => setState(() => _isZoomed = zoomed)
                  : null,
            );
          }
          return MediaVideoPreview(
            key: ValueKey(mediaItem.id),
            url: session.service!.fileUrl(mediaItem.path),
            headers: session.service!.authHeaders,
            isActive: isActive,
            onController: isActive
                ? (c) => setState(() => _videoController = c)
                : null,
          );
        }
        // Offline: each swiped-to item resolves its own local path on
        // demand (see FileViewerScreen.localPathResolver's doc comment) -
        // this is what makes swiping through offline media behave exactly
        // like Files/Photos instead of only ever showing the one item the
        // viewer was opened on.
        return FutureBuilder<String?>(
          key: ValueKey(mediaItem.id),
          future: widget.localPathResolver!(mediaItem),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(
                  color: context.nooColors.accent,
                ),
              );
            }
            final localPath = snapshot.data;
            if (localPath == null) {
              return Center(
                child: Icon(
                  LucideIcons.cloudOff,
                  color: context.nooColors.fg3,
                  size: 64,
                ),
              );
            }
            if (mediaItem.type == NextcloudItemType.image) {
              return MediaImagePreview(
                url: null,
                headers: const {},
                localPath: localPath,
                onZoomChanged: isActive
                    ? (zoomed) => setState(() => _isZoomed = zoomed)
                    : null,
              );
            }
            return MediaVideoPreview(
              url: null,
              headers: const {},
              localPath: localPath,
              isActive: isActive,
              onController: isActive
                  ? (c) => setState(() => _videoController = c)
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildStaticPreview(BuildContext context, SessionController session) {
    switch (widget.item.type) {
      case NextcloudItemType.image:
      case NextcloudItemType.video:
        // Unreachable: these types are always handled by the swipeable path.
        return const SizedBox.shrink();
      default:
        if (_isPdf) {
          return MediaPdfPreview(
            item: widget.item,
            session: session,
            localPathResolver: widget.localPathResolver,
          );
        }
        if (_isText) {
          return MediaTextPreview(
            item: widget.item,
            session: session,
            localPathResolver: widget.localPathResolver,
          );
        }
        return MediaUnsupportedPreview(
          item: widget.item,
          isBusy: _isBusy,
          onOpenExternally: () => _openExternally(session),
          onOpenDetails: () => DetailsSheet.show(context, widget.item),
        );
    }
  }
}
