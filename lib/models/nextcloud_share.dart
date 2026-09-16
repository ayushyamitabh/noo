import 'nextcloud_item.dart';

enum ShareType { user, group, publicLink, email, federated, other }

/// A Nextcloud OCS share — either something the current user has shared
/// with someone else, or something someone else has shared with them
/// (distinguished by [sharedWithMe]).
class NextcloudShare {
  final String id;
  final String path;
  final String name;
  final NextcloudItemType itemType;
  final ShareType shareType;
  final String ownerDisplayName;
  final String? sharedWithDisplayName;
  final DateTime sharedAt;
  final bool sharedWithMe;

  /// Only set for public-link shares.
  final String? url;
  final int permissions;
  final String? token;
  final DateTime? expireDate;

  const NextcloudShare({
    required this.id,
    required this.path,
    required this.name,
    required this.itemType,
    required this.shareType,
    required this.ownerDisplayName,
    this.sharedWithDisplayName,
    required this.sharedAt,
    required this.sharedWithMe,
    this.url,
    this.permissions = 1,
    this.token,
    this.expireDate,
  });

  bool get isFolder => itemType == NextcloudItemType.folder;
}
