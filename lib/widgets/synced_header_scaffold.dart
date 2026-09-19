import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../models/nextcloud_item.dart';
import '../models/sync_status.dart';
import '../providers/server_provider.dart';

/// Icon/label for the persistent header chip/panel - reflects device-sync
/// status (see `ServerProvider.syncHeaderStatus`), not the WebDAV
/// directory-listing refresh the pull gesture itself triggers (that has
/// its own, separate floating spinner bubble - see
/// `_SyncedHeaderScaffoldState`'s `_isRefreshing`).
(IconData, String) _syncHeaderDisplay(SyncHeaderStatus status) {
  return switch (status) {
    SyncHeaderStatus.off => (Icons.cloud_off_rounded, 'Sync off'),
    SyncHeaderStatus.syncing => (Icons.cloud_sync_rounded, 'Syncing…'),
    SyncHeaderStatus.done => (Icons.cloud_done_rounded, 'Synced'),
    SyncHeaderStatus.alert => (Symbols.cloud_alert_rounded, 'Sync issue'),
  };
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// "5.16 GB / 100 GB" — or "5.16 GB / ∞" when the server reports no quota
/// limit (or doesn't report one at all).
String formatQuota(NextcloudUserQuota quota) {
  final total = quota.totalBytes > 0 ? formatBytes(quota.totalBytes) : '∞';
  return '${formatBytes(quota.usedBytes)} / $total';
}

/// Shared "pull down to see sync status" scroll header used by both the
/// Files and Photos tabs: a compact sync-status chip that expands into a
/// storage-quota panel (Google Photos' "pull to see backup status"
/// pattern), sitting on a gray backdrop above a white rounded-top card that
/// holds the tab's own content slivers.
class SyncedHeaderScaffold extends StatefulWidget {
  final ScrollController scrollController;
  final ServerProvider provider;

  /// Trailing icons in the app bar (e.g. an upload button, the avatar).
  final List<Widget> actions;

  /// The tab's own content, already built as slivers (a filter/sort row,
  /// breadcrumbs, the grid/list, empty/loading/error states, etc.). Wrapped
  /// internally in the white rounded-top card.
  final List<Widget> contentSlivers;

  /// What a deliberate pull-to-sync should trigger. Defaults to
  /// [ServerProvider.refreshData] (the current folder's listing); pass e.g.
  /// `provider.fetchTrash` for a tab backed by different data.
  final Future<void> Function()? onRefresh;

  /// When non-null (a tab is mid-selection), this takes over the pinned top
  /// bar entirely - replacing the sync-status chip, [actions], and the
  /// pull-to-reveal quota panel - instead of appearing as a second app bar
  /// further down in [contentSlivers]. Selection is a modal-ish state (you
  /// came here to act on specific items), so it reads better as the one
  /// thing at the very top than as a strip sandwiched under the normal
  /// chrome.
  final Widget? selectionBar;

  const SyncedHeaderScaffold({
    super.key,
    required this.scrollController,
    required this.provider,
    required this.actions,
    required this.contentSlivers,
    this.onRefresh,
    this.selectionBar,
  });

  @override
  State<SyncedHeaderScaffold> createState() => _SyncedHeaderScaffoldState();
}

class _SyncedHeaderScaffoldState extends State<SyncedHeaderScaffold> {
  static const double _lockThreshold = 200;
  static const double _syncThreshold = 120;
  static const double _pullingEpsilon = 8;

  bool _headerLocked = false;
  bool _isPulling = false;
  bool _isRefreshing = false;
  double _pullDistance = 0;

  // Sync and lock are tracked separately (not one shared flag) so both can
  // still fire within a single continuous pull that passes both
  // thresholds - sync at the lower one, lock at the higher one - instead
  // of the first one reached blocking the other for the rest of the
  // gesture. Firing during the drag itself - rather than waiting for it to
  // end - is what actually matters here: waiting for ScrollEndNotification
  // meant a single deliberate pull often wasn't registering, and only a
  // fast second pull (still carrying velocity from the first one's
  // spring-back) reliably crossed the threshold before release.
  bool _syncedThisGesture = false;
  bool _lockedThisGesture = false;

  void _revealPanel() {
    if (widget.scrollController.hasClients) {
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _lockOpen() {
    if (!_headerLocked) setState(() => _headerLocked = true);
    _revealPanel();
  }

  void _startRefresh() {
    final refresh = widget.onRefresh ?? widget.provider.refreshData;
    setState(() => _isRefreshing = true);
    refresh().whenComplete(() {
      if (mounted) setState(() => _isRefreshing = false);
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.pixels < metrics.minScrollExtent) {
      _pullDistance = metrics.minScrollExtent - metrics.pixels;
      final pulling = _pullDistance > _pullingEpsilon;
      if (pulling != _isPulling && !_headerLocked) {
        setState(() => _isPulling = pulling);
      }

      if (!_lockedThisGesture && _pullDistance >= _lockThreshold) {
        _lockedThisGesture = true;
        _lockOpen();
        // Only refresh again if this pull hasn't already triggered one at
        // the lower sync threshold on its way past it.
        if (!_syncedThisGesture) {
          _syncedThisGesture = true;
          _startRefresh();
        }
      } else if (!_syncedThisGesture && _pullDistance >= _syncThreshold) {
        _syncedThisGesture = true;
        _startRefresh();
      }
    } else if (_isPulling) {
      setState(() => _isPulling = false);
    }

    if (notification is ScrollEndNotification) {
      _pullDistance = 0;
      _syncedThisGesture = false;
      _lockedThisGesture = false;
      if (_isPulling) setState(() => _isPulling = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = widget.provider;

    final Widget leadingWidget;
    if (_headerLocked) {
      leadingWidget = IconButton(
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        tooltip: 'Collapse',
        onPressed: () => setState(() => _headerLocked = false),
      );
    } else if (_isPulling) {
      leadingWidget = const SizedBox.shrink();
    } else {
      leadingWidget = _SyncStatusChip(provider: provider, onTap: _lockOpen);
    }

    final topInset = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: colorScheme.surfaceContainer,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: CustomScrollView(
              controller: widget.scrollController,
              // Plain BouncingScrollPhysics only bounces/overscrolls
              // reliably once content already fills the viewport — with
              // too little content (e.g. a single item) the pull gesture
              // can fail to register at all. AlwaysScrollableScrollPhysics
              // keeps the pull (and therefore the sync header) working
              // regardless of content length.
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: widget.selectionBar == null,
                  expandedHeight: widget.selectionBar != null
                      ? kToolbarHeight
                      : (_headerLocked
                            ? 190.0 + provider.syncConflicts.length * 52.0
                            : kToolbarHeight),
                  collapsedHeight: kToolbarHeight,
                  backgroundColor: colorScheme.surfaceContainer,
                  surfaceTintColor: colorScheme.surfaceContainer,
                  scrolledUnderElevation: 0,
                  automaticallyImplyLeading: false,
                  leadingWidth: widget.selectionBar != null
                      ? 0
                      : (_headerLocked ? 56 : 160),
                  leading: widget.selectionBar != null ? null : leadingWidget,
                  titleSpacing: widget.selectionBar != null ? 0 : null,
                  title: widget.selectionBar,
                  actions: widget.selectionBar != null
                      ? const []
                      : widget.actions,
                  flexibleSpace: widget.selectionBar != null
                      ? null
                      : FlexibleSpaceBar(
                          background: _SyncedStretchPanel(
                            provider: provider,
                            forceVisible: _headerLocked,
                          ),
                        ),
                ),
                DecoratedSliver(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  sliver: SliverMainAxisGroup(slivers: widget.contentSlivers),
                ),
              ],
            ),
          ),
          // The classic Material pull-to-refresh "bubble" — a floating
          // circular spinner, shown while a pull-triggered sync is in
          // flight. Positioned just under the status bar/toolbar area so it
          // reads as attached to the header rather than floating over
          // content.
          Positioned(
            top: topInset + 8,
            child: IgnorePointer(
              child: AnimatedScale(
                scale: _isRefreshing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _isRefreshing ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: colorScheme.surfaceContainerHigh,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact, always-visible summary of the same status shown by
/// [_SyncedStretchPanel] — tapping it is a discoverable shortcut for pulling
/// the header down to expand that same "Synced" view.
class _SyncStatusChip extends StatelessWidget {
  final ServerProvider provider;
  final VoidCallback onTap;

  const _SyncStatusChip({required this.provider, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = provider.syncHeaderStatus;
    final (icon, label) = _syncHeaderDisplay(status);
    final iconColor = status == SyncHeaderStatus.alert
        ? colorScheme.error
        : colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Material(
        color: Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

/// Revealed by pulling the header down past its normal height (Google
/// Photos' "pull to see backup status" pattern). Shows storage quota;
/// [_SyncedHeaderScaffoldState] decides via [forceVisible] whether it stays
/// locked open.
class _SyncedStretchPanel extends StatelessWidget {
  final ServerProvider provider;

  /// Keeps the panel fully shown even without live overscroll — used once
  /// the header has "locked" open after a deliberate pull-down.
  final bool forceVisible;

  const _SyncedStretchPanel({
    required this.provider,
    this.forceVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final topInset = MediaQuery.of(context).padding.top;

    return LayoutBuilder(
      builder: (context, constraints) {
        final settings = context
            .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
        final maxExtent = settings?.maxExtent ?? constraints.maxHeight;
        final stretch = (constraints.maxHeight - maxExtent).clamp(0.0, 80.0);
        // Reaches 1.0 (title fully hidden) at 50px of pull — comfortably
        // before the 100px lock threshold.
        final progress = forceVisible ? 1.0 : (stretch / 50).clamp(0.0, 1.0);
        final quota = provider.quota;
        final status = provider.syncHeaderStatus;
        final (_, statusLabel) = _syncHeaderDisplay(status);
        final conflicts = provider.syncConflicts;

        return Stack(
          children: [
            if (progress > 0)
              // Anchored below the toolbar row (icons), never the bottom,
              // so it can never share space with the title above.
              Positioned(
                left: 20,
                right: 20,
                top: topInset + kToolbarHeight + 4,
                child: Opacity(
                  opacity: progress,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (provider.serverUrl.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          provider.serverUrl.replaceFirst(
                            RegExp(r'^https?://'),
                            '',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.cloud_done_outlined,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                quota != null
                                    ? formatQuota(quota)
                                    : 'Pull to refresh',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (conflicts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        for (final conflict in conflicts)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SyncConflictRow(
                              conflict: conflict,
                              provider: provider,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One row in the locked-open panel's conflicts section - a file that
/// changed both locally and on the server since the last sync, with the
/// same two resolutions the sync-conflict notification offers (see
/// `SyncWorker.notifyConflicts`/`ConflictResolveWorker` on the native
/// side), just triggered in-app instead.
class _SyncConflictRow extends StatefulWidget {
  final SyncConflictInfo conflict;
  final ServerProvider provider;

  const _SyncConflictRow({required this.conflict, required this.provider});

  @override
  State<_SyncConflictRow> createState() => _SyncConflictRowState();
}

class _SyncConflictRowState extends State<_SyncConflictRow> {
  bool _resolving = false;

  Future<void> _resolve(bool useLocal) async {
    setState(() => _resolving = true);
    try {
      await widget.provider.resolveSyncConflict(
        widget.conflict,
        useLocal: useLocal,
      );
    } catch (_) {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Symbols.cloud_alert_rounded, color: colorScheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.conflict.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_resolving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _resolve(true),
              child: const Text('Keep local'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () => _resolve(false),
              child: const Text('Use server'),
            ),
          ],
        ],
      ),
    );
  }
}
