import 'package:flutter/foundation.dart';
import '../models/move_copy_result.dart';
import '../models/nextcloud_file_version.dart';
import '../models/nextcloud_item.dart';
import '../models/nextcloud_share.dart';
import '../models/nextcloud_sharee.dart';
import 'favorites_controller.dart';
import 'files_controller.dart';
import 'photos_controller.dart';
import 'session_controller.dart';

/// The one place that knows how an item mutation (delete/rename/move/copy/
/// favorite-toggle/create-folder) ripples across Files/Photos/Favorites -
/// those three each own their own item list, but a mutation triggered from
/// *any* of them (see each call site in the views) needs to reconcile all
/// three, since e.g. a delete removes an item Photos might also be
/// showing. Deliberately holds direct references to the sibling
/// controllers (constructed once in `main.dart`, after they already exist)
/// rather than a generic event bus, so callers can still `await` a
/// mutation and know every affected list has already been reconciled by
/// the time it returns - exactly the same guarantee the single
/// `ServerProvider` god object gave for free before this was split out.
///
/// Also home to the file-details sheet's per-item pass-throughs (shares/
/// activity/versions) - stateless, no stored data, so they don't need a
/// controller of their own.
class ItemOperations {
  final SessionController session;
  final FilesController files;
  final PhotosController photos;
  final FavoritesController favorites;

  const ItemOperations({
    required this.session,
    required this.files,
    required this.photos,
    required this.favorites,
  });

  Future<bool> deleteItem(String itemPath) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.deleteItem(itemPath);
    if (success) {
      photos.applyDelete(itemPath);
      await files.refreshData();
      await favorites.syncIfLoaded();
    }
    return success;
  }

  Future<bool> renameItem(NextcloudItem item, String newName) async {
    final service = session.service;
    if (service == null) return false;
    final success = await service.renameItem(item.path, newName);
    if (success) {
      await files.refreshData();
      await favorites.syncIfLoaded();
    }
    return success;
  }

  /// True if [destFolderPath] is [folderPath] itself or one of its own
  /// descendants - moving/copying a folder into itself (or a subfolder of
  /// itself) is nonsensical and rejected client-side rather than left to
  /// the server to (maybe) reject.
  bool _isSelfOrDescendant(String destFolderPath, String folderPath) {
    final dest = destFolderPath.endsWith('/')
        ? destFolderPath
        : '$destFolderPath/';
    final folder = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    return dest == folder || dest.startsWith(folder);
  }

  Future<MoveCopyResult> _moveOrCopyItems(
    List<NextcloudItem> items,
    String destFolderPath, {
    required bool copy,
  }) async {
    final service = session.service;
    if (service == null || items.isEmpty) return const MoveCopyResult();
    for (final item in items) {
      if (item.isFolder && _isSelfOrDescendant(destFolderPath, item.path)) {
        return const MoveCopyResult(
          blockedReason:
              "Can't move a folder into itself or one of its own subfolders",
        );
      }
    }

    var succeeded = 0;
    var failed = 0;
    final conflicts = <MoveCopyConflict>[];
    for (final item in items) {
      final status = copy
          ? await service.copyItem(item.path, destFolderPath)
          : await service.moveItem(item.path, destFolderPath);
      if (status == 201 || status == 204) {
        succeeded++;
      } else if (status == 412) {
        conflicts.add(MoveCopyConflict(item));
      } else {
        failed++;
      }
    }
    if (succeeded > 0) {
      files.invalidateCache();
      await files.refreshData();
      await favorites.syncIfLoaded();
    }
    return MoveCopyResult(
      succeeded: succeeded,
      conflicts: conflicts,
      failed: failed,
    );
  }

  /// Moves every item in [items] into [destFolderPath], keeping each
  /// item's own filename. Items that would collide with something already
  /// there come back in [MoveCopyResult.conflicts] rather than failing
  /// outright - resolve those with [resolveConflicts].
  Future<MoveCopyResult> moveItems(
    List<NextcloudItem> items,
    String destFolderPath,
  ) {
    return _moveOrCopyItems(items, destFolderPath, copy: false);
  }

  /// Same as [moveItems] but duplicates rather than relocates.
  Future<MoveCopyResult> copyItems(
    List<NextcloudItem> items,
    String destFolderPath,
  ) {
    return _moveOrCopyItems(items, destFolderPath, copy: true);
  }

  /// Finds the first `name (n).ext` not already in [existing] - `existing`
  /// is mutated as names are claimed, so a batch of "keep both" resolutions
  /// never picks the same generated name twice.
  String _nextAvailableName(String name, Set<String> existing) {
    if (!existing.contains(name)) return name;
    final dotIndex = name.lastIndexOf('.');
    final hasExtension = dotIndex > 0 && dotIndex < name.length - 1;
    final base = hasExtension ? name.substring(0, dotIndex) : name;
    final ext = hasExtension ? name.substring(dotIndex) : '';
    var n = 2;
    while (existing.contains('$base ($n)$ext')) {
      n++;
    }
    return '$base ($n)$ext';
  }

  /// Resolves a previous [moveItems]/[copyItems] call's conflicts per
  /// [choices] (keyed by `item.id`): overwrite the existing item, keep
  /// both (renamed against a fresh listing of [destFolderPath] so two
  /// "keep both" picks in the same batch can't collide with each other),
  /// or skip (left untouched at the source).
  Future<MoveCopyResult> resolveConflicts(
    List<MoveCopyConflict> conflicts,
    String destFolderPath, {
    required bool copy,
    required Map<String, ConflictChoice> choices,
  }) async {
    final service = session.service;
    if (service == null || conflicts.isEmpty) return const MoveCopyResult();

    final needsKeepBoth = conflicts.any(
      (c) => choices[c.item.id] == ConflictChoice.keepBoth,
    );
    final existingNames = needsKeepBoth
        ? (await files.fetchFolderListing(destFolderPath))
              .map((i) => i.name)
              .toSet()
        : <String>{};

    var succeeded = 0;
    var failed = 0;
    for (final conflict in conflicts) {
      final choice = choices[conflict.item.id] ?? ConflictChoice.skip;
      if (choice == ConflictChoice.skip) continue;

      final int status;
      if (choice == ConflictChoice.overwrite) {
        status = copy
            ? await service.copyItem(
                conflict.item.path,
                destFolderPath,
                overwrite: true,
              )
            : await service.moveItem(
                conflict.item.path,
                destFolderPath,
                overwrite: true,
              );
      } else {
        final newName = _nextAvailableName(conflict.item.name, existingNames);
        existingNames.add(newName);
        status = copy
            ? await service.copyItem(
                conflict.item.path,
                destFolderPath,
                newName: newName,
              )
            : await service.moveItem(
                conflict.item.path,
                destFolderPath,
                newName: newName,
              );
      }
      if (status == 201 || status == 204) {
        succeeded++;
      } else {
        failed++;
      }
    }
    if (succeeded > 0) {
      files.invalidateCache();
      await files.refreshData();
      await favorites.syncIfLoaded();
    }
    return MoveCopyResult(succeeded: succeeded, failed: failed);
  }

  Future<void> toggleItemFavorite(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return;
    final success = await service.toggleFavorite(item.path, item.isFavorite);
    if (success) {
      final updated = item.copyWith(isFavorite: !item.isFavorite);
      files.applyFavoriteToggle(updated);
      photos.applyFavoriteToggle(updated);
      favorites.applyFavoriteToggle(updated);
    }
  }

  /// Creates a public link share for [item] and returns its URL, or null on
  /// failure (server error, unsupported item, etc).
  Future<String?> createShareLink(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return null;
    try {
      return await service.createPublicShareLink(item.path);
    } catch (e) {
      debugPrint('[ItemOperations] createShareLink failed: $e');
      return null;
    }
  }

  // --- Details sheet: per-item sharing/activity/versions ---
  //
  // Thin pass-throughs (no stored state) - the data here is transient and
  // scoped to whichever item's Details sheet happens to be open, so it
  // lives in that sheet's own local widget state rather than a controller.

  Future<List<NextcloudShare>> fetchItemShares(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return [];
    try {
      return await service.fetchSharesForPath(item.path);
    } catch (e) {
      debugPrint('[ItemOperations] fetchItemShares failed: $e');
      return [];
    }
  }

  Future<List<NextcloudShare>> fetchInheritedShares(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return [];
    return service.fetchInheritedShares(item.path);
  }

  Future<List<NextcloudSharee>> searchSharees(String query) async {
    final service = session.service;
    if (service == null) return [];
    try {
      return await service.searchSharees(query);
    } catch (e) {
      debugPrint('[ItemOperations] searchSharees failed: $e');
      return [];
    }
  }

  Future<NextcloudShare?> createShare({
    required String path,
    required int shareType,
    String? shareWith,
    String? password,
    DateTime? expireDate,
  }) async {
    final service = session.service;
    if (service == null) return null;
    try {
      return await service.createShare(
        path: path,
        shareType: shareType,
        shareWith: shareWith,
        password: password,
        expireDate: expireDate,
      );
    } catch (e) {
      debugPrint('[ItemOperations] createShare failed: $e');
      return null;
    }
  }

  /// Deletes a share (from the file-details/Share sheet, not the Shares
  /// tab itself - see `SharesController.deleteShare` for that one, which
  /// additionally patches the tab's own list).
  Future<bool> deleteShare(NextcloudShare share) async {
    final service = session.service;
    if (service == null) return false;
    return service.deleteShare(share.id);
  }

  Future<List<NextcloudActivity>> fetchFileActivity(NextcloudItem item) async {
    final service = session.service;
    if (service == null) return [];
    return service.fetchFileActivity(item.id);
  }

  Future<List<NextcloudFileVersion>> fetchFileVersions(
    NextcloudItem item,
  ) async {
    final service = session.service;
    if (service == null) return [];
    return service.fetchFileVersions(item.id);
  }

  Future<bool> restoreFileVersion(
    NextcloudItem item,
    String versionLabel,
  ) async {
    final service = session.service;
    if (service == null) return false;
    try {
      return await service.restoreFileVersion(item.id, versionLabel);
    } catch (e) {
      debugPrint('[ItemOperations] restoreFileVersion failed: $e');
      return false;
    }
  }

  Future<bool> downloadVersion(
    NextcloudItem item,
    String versionLabel,
    String savePath,
  ) async {
    final service = session.service;
    if (service == null) return false;
    try {
      await service.downloadVersionToFile(item.id, versionLabel, savePath);
      return true;
    } catch (e) {
      debugPrint('[ItemOperations] downloadVersion failed: $e');
      return false;
    }
  }
}
