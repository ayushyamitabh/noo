/// One result from a sharee search (`/ocs/.../sharees`) — a user or team
/// (group) that a file/folder can be shared with.
enum ShareeType { user, group, remote }

class NextcloudSharee {
  final String shareWith;
  final String label;
  final ShareeType type;
  final String? subtitle;

  const NextcloudSharee({
    required this.shareWith,
    required this.label,
    required this.type,
    this.subtitle,
  });

  /// The numeric OCS `shareType` used when creating a share with this
  /// sharee (0 = user, 1 = group, 6 = federated/remote).
  int get shareTypeValue {
    switch (type) {
      case ShareeType.user:
        return 0;
      case ShareeType.group:
        return 1;
      case ShareeType.remote:
        return 6;
    }
  }
}
