import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';

class PhotosView extends StatelessWidget {
  final ScrollController scrollController;

  const PhotosView({super.key, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final photos = provider.photoItems;

    return CustomScrollView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Photos & Media',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${photos.length} cloud photos & video streams',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),

        if (photos.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 64,
                    color: colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No photos found in Nextcloud library',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.0,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final photo = photos[index];
                  return _buildPhotoTile(context, photo, provider);
                },
                childCount: photos.length,
              ),
            ),
          ),

        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }

  Widget _buildPhotoTile(BuildContext context, NextcloudItem photo, ServerProvider provider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return GestureDetector(
      onTap: () => _openLightbox(context, photo, provider),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            photo.previewUrl != null
                ? Image.network(
                    photo.previewUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _buildFallbackTile(context, photo),
                  )
                : _buildFallbackTile(context, photo),
            if (photo.type == NextcloudItemType.video)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            if (photo.isFavorite)
              const Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.star_rounded,
                  color: Colors.amber,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackTile(BuildContext context, NextcloudItem photo) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.secondaryContainer,
      child: Center(
        child: Icon(
          photo.type == NextcloudItemType.video
              ? Icons.movie_rounded
              : Icons.image_rounded,
          color: colorScheme.onSecondaryContainer,
          size: 32,
        ),
      ),
    );
  }

  void _openLightbox(BuildContext context, NextcloudItem photo, ServerProvider provider) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: photo.previewUrl != null
                      ? Image.network(
                          photo.previewUrl!,
                          fit: BoxFit.contain,
                        )
                      : Icon(
                          photo.type == NextcloudItemType.video
                              ? Icons.movie_rounded
                              : Icons.image_rounded,
                          size: 120,
                          color: Colors.white70,
                        ),
                ),
              ),
              Positioned(
                top: 24,
                left: 16,
                right: 16,
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.5),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            onPressed: () {
                              provider.toggleItemFavorite(photo);
                            },
                            icon: Icon(
                              photo.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: photo.isFavorite ? Colors.amber : Colors.white,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Downloading full resolution ${photo.name}...'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.download_rounded, color: Colors.white),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 32,
                left: 24,
                right: 24,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          photo.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat.yMMMMd().format(photo.lastModified)} • Nextcloud Photos',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
