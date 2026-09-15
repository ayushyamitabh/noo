import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/nextcloud_item.dart';
import '../providers/server_provider.dart';
import '../widgets/profile_avatar_button.dart';
import 'file_viewer_screen.dart';

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
        SliverAppBar(
          pinned: true,
          expandedHeight: kToolbarHeight,
          collapsedHeight: kToolbarHeight,
          backgroundColor: colorScheme.surface,
          surfaceTintColor: colorScheme.surface,
          scrolledUnderElevation: 0,
          actions: const [ProfileAvatarButton()],
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),

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
              delegate: SliverChildBuilderDelegate((context, index) {
                final photo = photos[index];
                return _buildPhotoTile(context, photo, provider);
              }, childCount: photos.length),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildPhotoTile(
    BuildContext context,
    NextcloudItem photo,
    ServerProvider provider,
  ) {
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
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      // Decode at the tile's actual rendered size rather
                      // than the full 500x500 preview the server returns —
                      // cheaper to decode/cache while scrolling a grid.
                      final cachePixels =
                          (constraints.maxWidth *
                                  MediaQuery.of(context).devicePixelRatio)
                              .round();
                      return Image.network(
                        photo.previewUrl!,
                        headers: provider.service?.authHeaders,
                        fit: BoxFit.cover,
                        cacheWidth: cachePixels,
                        cacheHeight: cachePixels,
                        filterQuality: FilterQuality.low,
                        gaplessPlayback: true,
                        errorBuilder: (ctx, err, stack) =>
                            _buildFallbackTile(context, photo),
                      );
                    },
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
                child: Icon(Icons.star_rounded, color: Colors.amber, size: 18),
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

  void _openLightbox(
    BuildContext context,
    NextcloudItem photo,
    ServerProvider provider,
  ) {
    Navigator.push(
      context,
      FileViewerScreen.route(item: photo, siblings: provider.photoItems),
    );
  }
}
