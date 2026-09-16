/// One entry in a file's version history (Nextcloud's DAV versions API).
class NextcloudFileVersion {
  /// The timestamp segment used in the DAV versions/restore URLs, e.g.
  /// `1699999999`.
  final String versionLabel;
  final DateTime timestamp;
  final int size;
  final bool isCurrent;

  const NextcloudFileVersion({
    required this.versionLabel,
    required this.timestamp,
    required this.size,
    this.isCurrent = false,
  });
}
