import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/nextcloud_item.dart';
import '../services/sync_service.dart';
import 'files_controller.dart';
import 'folder_browser.dart';
import 'session_controller.dart';

/// The Offline tab's data source: `FilesView` (the same view as the Files
/// tab) over whatever device-sync has actually mirrored to local storage,
/// i.e. the Files tab's folders filtered down to what's available offline -
/// read straight off
/// disk, no server round-trip, since the whole point is browsing what's
/// available without a connection. Walks
/// `<externalFilesDir>/sync/<accountId>/...` directly (mirrors
/// `SyncEngine.kt#syncRoot`'s layout exactly, same technique
/// `SyncStatusController.localSyncedFilePath` already relies on) rather
/// than round-tripping through a MethodChannel. Listens for
/// [SessionController.addAccountReadyListener] rather than
/// `addAccountActivatedListener` - this controller's own work is entirely
/// local, so it's safe to run even on a provisional/offline login (see
/// that method's doc comment).
///
/// Display controls (grid/list, sort, hidden files, files/folders filter)
/// aren't kept here - [items] runs the listing through the Files tab's own
/// [FilesController] prefs so the two tabs always agree.
class OfflineController extends ChangeNotifier
    with WidgetsBindingObserver
    implements FolderBrowser {
  final SessionController session;
  final FilesController files;

  List<String> _pathStack = const ['/'];
  List<NextcloudItem> _items = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _wasSyncing = false;
  // Resolved once in _load - lets [localFileFor] stay synchronous so it can
  // be called straight from a widget's build.
  String? _syncBasePath;
  StreamSubscription<SyncStatusSnapshot>? _statusSub;

  OfflineController(this.session, this.files) {
    WidgetsBinding.instance.addObserver(this);
    session.addAccountClearedListener(_onAccountCleared);
    session.addAccountReadyListener(_onAccountActivated);
    // Refreshes automatically once a sync pass finishes, so newly
    // downloaded files show up here without a manual pull-to-refresh.
    _statusSub = SyncService.statusStream.listen(_onStatusSnapshot);
  }

  @override
  List<String> get pathStack => _pathStack;
  @override
  String get currentFolderPath => _pathStack.last;
  @override
  List<NextcloudItem> get items => files.applyFilesDisplayPrefs(
    _items,
    folderPath: currentFolderPath,
    // The local mirror has no cloud/external distinction to filter on.
    applyStorageScope: false,
  );
  // Only "loading" while there's nothing to show yet - a reload over an
  // already-listed folder (e.g. the automatic one after a sync pass
  // finishes) swaps the list in place instead of flashing a spinner.
  @override
  bool get isLoading => _isLoading && _items.isEmpty;
  @override
  String? get errorMessage => _errorMessage;

  void _onAccountCleared() {
    _pathStack = const ['/'];
    _items = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _onAccountActivated() {
    unawaited(_load());
  }

  /// A background sync (which can run while the app is closed or paused)
  /// may have added or removed files since this list was last read - re-read
  /// the folder whenever the app comes back to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  void _onStatusSnapshot(SyncStatusSnapshot snapshot) {
    if (_wasSyncing && !snapshot.syncing) {
      unawaited(_load());
    }
    _wasSyncing = snapshot.syncing;
  }

  /// Reloads the currently browsed folder - used by pull-to-refresh and as
  /// the account-activation entry point.
  @override
  Future<void> reload() => _load();

  @override
  Future<void> navigateToFolder(String path) async {
    _pathStack = [..._pathStack, path];
    await _load();
  }

  @override
  Future<void> navigateToPathIndex(int index) async {
    if (index < 0 || index >= _pathStack.length - 1) return;
    _pathStack = _pathStack.sublist(0, index + 1);
    await _load();
  }

  @override
  Future<void> navigateUp() async {
    if (_pathStack.length <= 1) return;
    _pathStack = _pathStack.sublist(0, _pathStack.length - 1);
    await _load();
  }

  Future<void> _load() async {
    final accountId = session.activeAccountId;
    if (accountId == null) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _syncBasePath ??= (await getExternalStorageDirectory())?.path;
      // A sync can delete the very folder being browsed (deleted on the
      // server) - step out to the nearest ancestor that still exists rather
      // than showing a phantom empty folder.
      final base = _syncBasePath;
      if (base != null) {
        while (_pathStack.length > 1 &&
            !Directory(
              p.join(
                base,
                'sync',
                accountId,
                currentFolderPath.replaceFirst('/', ''),
              ),
            ).existsSync()) {
          _pathStack = _pathStack.sublist(0, _pathStack.length - 1);
        }
      }
      _items = await _listFolder(accountId, currentFolderPath);
    } catch (e) {
      debugPrint('[OfflineController] Error listing local files: $e');
      _errorMessage = e.toString().replaceAll('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// The absolute local path for [item] - a pure function of its remote-
  /// style `path` (same `<accountId>/<relPath>` layout `SyncEngine.kt#
  /// syncRoot` uses). Deliberately doesn't re-verify [item] is "in sync
  /// scope" the way `SyncStatusController.localSyncedFilePath` does for
  /// arbitrary items from elsewhere in the app - every item this
  /// controller ever hands out already came from listing this exact
  /// directory tree, so it's definitionally already local; re-checking
  /// scope here was the actual bug behind a file the Offline tab had just
  /// listed reporting itself as "no longer available".
  /// Synchronous counterpart to [localPathFor] for building thumbnails -
  /// null until the first [_load] has resolved the storage directory. Doesn't
  /// check the file exists; the image widget's own error fallback covers a
  /// missing one.
  File? localFileFor(NextcloudItem item) {
    final accountId = session.activeAccountId;
    final base = _syncBasePath;
    if (accountId == null || base == null) return null;
    final relPath = item.path.startsWith('/')
        ? item.path.substring(1)
        : item.path;
    return File(p.join(base, 'sync', accountId, relPath));
  }

  Future<String?> localPathFor(NextcloudItem item) async {
    final accountId = session.activeAccountId;
    if (accountId == null) return null;
    final base = await getExternalStorageDirectory();
    if (base == null) return null;
    final relPath = item.path.startsWith('/')
        ? item.path.substring(1)
        : item.path;
    final file = File(p.join(base.path, 'sync', accountId, relPath));
    return file.existsSync() ? file.path : null;
  }

  static Future<List<NextcloudItem>> _listFolder(
    String accountId,
    String folderPath,
  ) async {
    final base = await getExternalStorageDirectory();
    if (base == null) return [];
    final relFolder = folderPath == '/' ? '' : folderPath.replaceFirst('/', '');
    final dir = Directory(p.join(base.path, 'sync', accountId, relFolder));
    if (!dir.existsSync()) return [];

    final items = <NextcloudItem>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final remotePath = folderPath == '/' ? '/$name' : '$folderPath/$name';
      if (entity is Directory) {
        items.add(
          NextcloudItem(
            id: remotePath,
            name: name,
            path: remotePath,
            type: NextcloudItemType.folder,
            size: 0,
            lastModified: (await entity.stat()).modified,
          ),
        );
      } else if (entity is File) {
        final stat = await entity.stat();
        items.add(
          NextcloudItem(
            id: remotePath,
            name: name,
            path: remotePath,
            type: NextcloudItem.deduceType(remotePath, false, null),
            size: stat.size,
            lastModified: stat.modified,
          ),
        );
      }
    }
    return items;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSub?.cancel();
    super.dispose();
  }
}
