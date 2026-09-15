import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/server_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/frosted_glass_container.dart';

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 GB';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final quota = provider.quota;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & Storage'),
        actions: [
          IconButton(
            onPressed: () => _showLogoutConfirmation(context, provider),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log Out',
            color: colorScheme.error,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          physics: const BouncingScrollPhysics(),
          children: [
            Text(
              'Connected to ${provider.serverUrl}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            // User Profile & Storage Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: colorScheme.primary,
                        child: Text(
                          (quota?.userName ?? provider.username)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quota?.userName ?? provider.username,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              quota?.email ?? provider.username,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: provider.isLoggedIn
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.red.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          provider.isLoggedIn ? 'ONLINE' : 'OFFLINE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: provider.isLoggedIn
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Storage Quota',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        quota != null
                            ? (quota.totalBytes > 0
                                  ? '${_formatBytes(quota.usedBytes)} of ${_formatBytes(quota.totalBytes)}'
                                  : '${_formatBytes(quota.usedBytes)} (Unlimited)')
                            : 'Live Server Storage',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: quota != null && quota.totalBytes > 0
                          ? quota.usagePercentage
                          : 0.1,
                      minHeight: 10,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    quota != null
                        ? (quota.totalBytes > 0
                              ? '${(quota.usagePercentage * 100).toStringAsFixed(1)}% used'
                              : 'Unlimited Storage Plan')
                        : 'WebDAV connection active',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Server Credentials Section
            Text(
              'Server Connection Info',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.dns_rounded),
                    title: const Text('Nextcloud Host'),
                    subtitle: Text(provider.serverUrl),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.person_rounded),
                    title: const Text('Logged In User'),
                    subtitle: Text(provider.username),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Refresh WebDAV Cache'),
                    onTap: () async {
                      await provider.refreshData();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Refreshed WebDAV directory data'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Material You Design Settings
            Text(
              'Material You Aesthetics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Accent Color',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      provider.useDynamicColor
                          ? 'Matching your wallpaper'
                          : 'Custom color',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _AccentSwatch(
                          isSelected: provider.useDynamicColor,
                          onTap: () => provider.setUseDynamicColor(true),
                          borderColor: colorScheme.onSurface,
                          background: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.wallpaper_rounded,
                            color: colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        ...AppTheme.seedColors.map((color) {
                          final isSelected =
                              !provider.useDynamicColor &&
                              provider.seedColor == color;
                          return _AccentSwatch(
                            isSelected: isSelected,
                            onTap: () => provider.setSeedColor(color),
                            borderColor: colorScheme.onSurface,
                            background: color,
                            child: isSelected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    Text(
                      'Theme Mode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            icon: Icon(Icons.brightness_auto_rounded),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            icon: Icon(Icons.light_mode_rounded),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            icon: Icon(Icons.dark_mode_rounded),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {provider.themeMode},
                        onSelectionChanged: (set) =>
                            provider.setThemeMode(set.first),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // UI Settings
            Text(
              'UI',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const _BottomBarAppearanceCard(),
          ],
        ),
      ),
    );
  }

  void _showLogoutConfirmation(BuildContext context, ServerProvider provider) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Log Out'),
          content: Text(
            'Are you sure you want to disconnect from ${provider.serverUrl}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                provider.logout();
              },
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );
  }
}

class _BottomBarAppearanceCard extends StatefulWidget {
  const _BottomBarAppearanceCard();

  @override
  State<_BottomBarAppearanceCard> createState() =>
      _BottomBarAppearanceCardState();
}

class _BottomBarAppearanceCardState extends State<_BottomBarAppearanceCard> {
  // Mirrors the provider values locally so the slider thumb and the live
  // preview track the drag gesture on every frame. Driving them straight off
  // `provider.bottomBar*` instead would tie the slider's own responsiveness
  // to a full Provider-wide rebuild — including the expensive BackdropFilter
  // blur in the preview — which can't keep up with fast drag ticks and makes
  // the thumb appear stuck until the next unrelated rebuild.
  double? _opacity;
  double? _blur;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final provider = context.watch<ServerProvider>();
    final opacity = _opacity ?? provider.bottomBarOpacity;
    final blur = _blur ?? provider.bottomBarBlur;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bottom Bar Appearance',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Adjust the glass effect of the floating bottom bar',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Live preview
            Container(
              height: 140,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary,
                    colorScheme.tertiary,
                    colorScheme.secondary,
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _PreviewPatternPainter()),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FrostedGlassContainer(
                        opacity: opacity,
                        blurSigma: blur,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.folder_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.photo_library_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.history_rounded,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Opacity', style: theme.textTheme.bodyMedium),
                Text(
                  '${(opacity * 100).round()}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Slider(
              value: opacity,
              min: 0.1,
              max: 1.0,
              onChanged: (value) => setState(() => _opacity = value),
              onChangeEnd: provider.setBottomBarOpacity,
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Blur', style: theme.textTheme.bodyMedium),
                Text(
                  blur.round().toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Slider(
              value: blur,
              min: 0,
              max: 40,
              onChanged: (value) => setState(() => _blur = value),
              onChangeEnd: provider.setBottomBarBlur,
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    for (var x = -size.height; x < size.width; x += 24) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPatternPainter oldDelegate) => false;
}

class _AccentSwatch extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final Color borderColor;
  final Color background;
  final Widget? child;

  const _AccentSwatch({
    required this.isSelected,
    required this.onTap,
    required this.borderColor,
    required this.background,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: borderColor, width: 3) : null,
        ),
        child: child,
      ),
    );
  }
}
