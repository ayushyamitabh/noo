import '../models/nextcloud_item.dart';

/// What `FilesView` needs from whatever is supplying the folder it's
/// showing: the breadcrumb trail, the (already display-pref-filtered and
/// sorted) items, loading/error state, and navigation. Implemented by
/// [FilesController] (the server's folders) and [OfflineController] (the
/// device-sync mirror of those same folders) so the Files tab and the
/// Offline tab are literally the same view over two data sources.
///
/// Deliberately not a `Listenable` - `context.watch` subscribes to the
/// concrete provider registered in `main()`, not to this interface, so the
/// view picks the concrete controller and then treats it as a
/// [FolderBrowser].
abstract interface class FolderBrowser {
  List<String> get pathStack;
  String get currentFolderPath;

  /// Items in [currentFolderPath] with the shared Files display prefs
  /// (hidden files, type filter, sort) already applied.
  List<NextcloudItem> get items;

  bool get isLoading;
  String? get errorMessage;

  Future<void> navigateToFolder(String path);
  Future<void> navigateToPathIndex(int index);
  Future<void> navigateUp();

  /// Re-reads the current folder (pull-to-refresh / retry).
  Future<void> reload();
}
