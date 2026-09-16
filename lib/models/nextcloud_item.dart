import 'package:flutter/material.dart';

enum NextcloudItemType { file, folder, image, video, document, audio, archive }

class NextcloudItem {
  final String id;
  final String name;
  final String path;
  final NextcloudItemType type;
  final int size; // in bytes
  final DateTime lastModified;
  final DateTime dateCreated;
  final bool isFavorite;
  final String? mimeType;
  final String? etag;
  final String? previewUrl;
  final int? imageWidth;
  final int? imageHeight;
  final String? mountType;

  /// Trash-bin items only: the folder path the item was deleted from, and
  /// when it was deleted. Null for items fetched from a regular directory.
  final String? originalLocation;
  final DateTime? deletedAt;

  const NextcloudItem({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.size,
    required this.lastModified,
    DateTime? dateCreated,
    this.isFavorite = false,
    this.mimeType,
    this.etag,
    this.previewUrl,
    this.imageWidth,
    this.imageHeight,
    this.mountType,
    this.originalLocation,
    this.deletedAt,
  }) : dateCreated = dateCreated ?? lastModified;

  bool get isFolder => type == NextcloudItemType.folder;
  bool get isMedia =>
      type == NextcloudItemType.image || type == NextcloudItemType.video;
  bool get isExternalStorage => mountType == 'external';

  NextcloudItem copyWith({
    String? id,
    String? name,
    String? path,
    NextcloudItemType? type,
    int? size,
    DateTime? lastModified,
    DateTime? dateCreated,
    bool? isFavorite,
    String? mimeType,
    String? etag,
    String? previewUrl,
    int? imageWidth,
    int? imageHeight,
    String? mountType,
    String? originalLocation,
    DateTime? deletedAt,
  }) {
    return NextcloudItem(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      size: size ?? this.size,
      lastModified: lastModified ?? this.lastModified,
      dateCreated: dateCreated ?? this.dateCreated,
      isFavorite: isFavorite ?? this.isFavorite,
      mimeType: mimeType ?? this.mimeType,
      etag: etag ?? this.etag,
      previewUrl: previewUrl ?? this.previewUrl,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      mountType: mountType ?? this.mountType,
      originalLocation: originalLocation ?? this.originalLocation,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  static NextcloudItemType deduceType(
    String path,
    bool isCollection,
    String? mime,
  ) {
    if (isCollection) return NextcloudItemType.folder;
    final lower = path.toLowerCase();
    if (mime?.startsWith('image/') == true ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic')) {
      return NextcloudItemType.image;
    }
    if (mime?.startsWith('video/') == true ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.webm')) {
      return NextcloudItemType.video;
    }
    if (mime?.startsWith('audio/') == true ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.ogg')) {
      return NextcloudItemType.audio;
    }
    if (lower.endsWith('.pdf') ||
        lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.xlsx')) {
      return NextcloudItemType.document;
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.tar') ||
        lower.endsWith('.gz') ||
        lower.endsWith('.7z')) {
      return NextcloudItemType.archive;
    }
    return NextcloudItemType.file;
  }
}

class NextcloudUserQuota {
  final int usedBytes;
  final int totalBytes;
  final double usagePercentage;
  final String userName;
  final String email;
  final String serverVersion;
  final List<String> groups;

  const NextcloudUserQuota({
    required this.usedBytes,
    required this.totalBytes,
    required this.usagePercentage,
    required this.userName,
    required this.email,
    required this.serverVersion,
    this.groups = const [],
  });

  factory NextcloudUserQuota.demo() {
    return const NextcloudUserQuota(
      usedBytes: 48500000000, // ~45.17 GB
      totalBytes: 107374182400, // 100 GB
      usagePercentage: 0.4517,
      userName: 'Ayush Admin',
      email: 'ayush@cloud.internal',
      serverVersion: 'Nextcloud 29.0.4 Hub 8',
      groups: ['Family', 'Friends'],
    );
  }
}

class NextcloudActivity {
  final String id;
  final String title;
  final String subject;
  final DateTime timestamp;
  final IconData icon;
  final String author;

  const NextcloudActivity({
    required this.id,
    required this.title,
    required this.subject,
    required this.timestamp,
    required this.icon,
    required this.author,
  });
}
