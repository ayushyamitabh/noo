import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/app_tab.dart';
import 'models/pick_request.dart';
import 'providers/favorites_controller.dart';
import 'providers/files_controller.dart';
import 'providers/item_operations.dart';
import 'providers/photos_controller.dart';
import 'providers/pick_controller.dart';
import 'providers/recent_controller.dart';
import 'providers/session_controller.dart';
import 'providers/settings_controller.dart';
import 'providers/shares_controller.dart';
import 'providers/sync_status_controller.dart';
import 'providers/trash_controller.dart';
import 'services/pick_intent_service.dart';
import 'services/share_intent_service.dart';
import 'theme/app_theme.dart';
import 'views/lock_screen_view.dart';
import 'views/login_view.dart';
import 'views/search_view.dart';
import 'views/share_upload_view.dart';
import 'widgets/app_tab_view_builder.dart';
import 'widgets/floating_bottom_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      // Split out of the former single `ServerProvider` god object - see
      // `.claude/context/architecture.md`'s "State management" section.
      // Order matters: each `create` below reads earlier providers via
      // `context.read`, which is safe here since none of them are ever
      // replaced/recreated for the app's lifetime (account switching is
      // internal state on SessionController, not a new provider instance).
      providers: [
        ChangeNotifierProvider(create: (_) => SessionController()),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        ChangeNotifierProvider(
          create: (context) => SyncStatusController(context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => FilesController(context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              PhotosController(context.read(), context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) =>
              FavoritesController(context.read(), context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => TrashController(context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => SharesController(context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => RecentController(context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => PickController(context.read()),
        ),
        Provider(
          create: (context) => ItemOperations(
            session: context.read(),
            files: context.read(),
            photos: context.read(),
            favorites: context.read(),
          ),
        ),
      ],
      child: const NextcloudApp(),
    ),
  );
}

class NextcloudApp extends StatelessWidget {
  const NextcloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final session = context.watch<SessionController>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'Noo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(
            settings.seedColor,
            dynamicScheme: lightDynamic,
            useDynamicColor: settings.useDynamicColor,
          ),
          darkTheme: AppTheme.dark(
            settings.seedColor,
            dynamicScheme: darkDynamic,
            useDynamicColor: settings.useDynamicColor,
            amoled: settings.amoledDark,
          ),
          themeMode: settings.themeMode,
          home: session.isRestoringSession
              ? const _SplashView()
              : (!session.isLoggedIn
                    ? const LoginView()
                    : (session.needsUnlock
                          ? const LockScreenView()
                          : const MainShellView())),
        );
      },
    );
  }
}

class _SplashView extends StatelessWidget {
  const _SplashView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The monochrome adaptive-icon layer is a plain white silhouette
            // on transparent, meant to be tinted rather than shown as-is -
            // srcIn recolors it to the theme's foreground so it reads
            // correctly in both light and dark mode.
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                colorScheme.onSurface,
                BlendMode.srcIn,
              ),
              child: Image.asset(
                'assets/icon/app_icon_monochrome.png',
                width: 72,
                height: 72,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShellView extends StatefulWidget {
  const MainShellView({super.key});

  @override
  State<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends State<MainShellView> {
  late AppTab _currentTab;
  late final Map<AppTab, ScrollController> _scrollControllers;
  StreamSubscription<List<SharedFileRef>>? _shareSub;
  StreamSubscription<PickRequest>? _pickSub;

  @override
  void initState() {
    super.initState();
    _scrollControllers = {
      for (final tab in AppTab.values) tab: ScrollController(),
    };
    // Preferences load asynchronously, but in practice finish well before
    // session restore (which also has to hit the network) does, so by the
    // time this shell mounts `defaultTab` already reflects the saved value.
    _currentTab = context.read<SettingsController>().defaultTab;

    // Handles both a cold start via another app's "Share to..." sheet
    // (getInitialShare) and a share arriving while the app is already
    // running (onNewShare). See MainActivity.kt's doc comment for why this
    // is hand-rolled instead of the receive_sharing_intent plugin - in
    // short, this only ever fetches cheap Uri metadata here, never a
    // file's actual bytes, so a large shared file can't block startup.
    ShareIntentService.getInitialShare().then(_handleSharedFiles);
    _shareSub = ShareIntentService.onNewShare.listen(_handleSharedFiles);

    // Same cold-start-vs-already-running split as the share intent above:
    // another app may have launched Noo as its GET_CONTENT picker.
    PickIntentService.getPickRequest().then((request) {
      if (request != null && mounted) {
        context.read<PickController>().setPickRequest(request);
      }
    });
    _pickSub = PickIntentService.onNewPickRequest.listen((request) {
      if (mounted) context.read<PickController>().setPickRequest(request);
    });

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRequestNotificationPermission(),
    );
  }

  static const _prefNotificationPermissionAsked =
      'notification_permission_asked';

  // Asked once, on the app's first launch after login, rather than every
  // time this shell mounts - a plain-language reason shown before the OS
  // prompt (which just says "Noo would like to send you notifications"
  // with no context) so the system dialog doesn't feel unexplained, since
  // it's what shows upload/download progress for background transfers.
  Future<void> _maybeRequestNotificationPermission() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefNotificationPermissionAsked) ?? false) return;
    await prefs.setBool(_prefNotificationPermissionAsked, true);

    final status = await Permission.notification.status;
    if (status.isGranted || status.isPermanentlyDenied) return;
    if (!mounted) return;

    final shouldRequest = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Allow notifications?'),
        content: const Text(
          'Noo shows upload and download progress as a notification, so '
          'you can track transfers that keep running in the background.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (shouldRequest == true) {
      await Permission.notification.request();
    }
  }

  void _handleSharedFiles(List<SharedFileRef> files) {
    if (files.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ShareUploadView(files: files)));
    });
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _shareSub?.cancel();
    _pickSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final pick = context.watch<PickController>();

    // A one-shot request (e.g. tapping a search result) to switch tabs -
    // consumed here so it only fires once, then cleared after this frame
    // (clearing it synchronously would call notifyListeners mid-build).
    final requestedTab = settings.requestedTab;
    if (requestedTab != null) {
      _currentTab = requestedTab;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => settings.consumeRequestedTab(),
      );
    }

    final pickRequest = pick.pickRequest;
    // While acting as another app's picker, only Files and Photos make
    // sense as browsable sources - Trash/Shares/Activity/Recent aren't
    // real "pick a file from here" destinations, and only these two tabs'
    // views even know how to handle picking-mode taps. This overrides the
    // user's own hidden/reordered tab settings rather than respecting
    // them, since picking is a separate mode from normal browsing.
    final visible = pickRequest != null
        ? [AppTab.files, AppTab.photos]
        : settings.visibleTabs;
    final selectedTab = visible.contains(_currentTab)
        ? _currentTab
        : (visible.isNotEmpty ? visible.first : AppTab.files);
    final selectedIndex = visible
        .indexOf(selectedTab)
        .clamp(0, visible.isEmpty ? 0 : visible.length - 1);

    final navItems = visible
        .map((tab) => FloatingNavItem(label: tab.label, icon: tab.icon))
        .toList();

    return PopScope(
      // While picking, system back cancels the pick (and tells the caller
      // nothing was chosen) instead of exiting the app from under it -
      // there's no Navigator route to pop at this, the root screen.
      canPop: pickRequest == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && pickRequest != null) pick.cancelPick();
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: selectedIndex,
              children: visible
                  .map((tab) => buildAppTabView(tab, _scrollControllers[tab]!))
                  .toList(),
            ),
            if (pick.isDownloadingForPick) const _PickingProgressOverlay(),
            // Each tab now renders its own sticky selection toolbar inline
            // (right under its sort/filter row) instead of this shell
            // swapping in a shared floating bar - the bottom nav stays put
            // and usable regardless of selection state.
            FloatingBottomNavBar(
              selectedIndex: selectedIndex,
              items: navItems,
              opacity: settings.bottomBarOpacity,
              blurSigma: settings.bottomBarBlur,
              onDestinationSelected: (index) {
                final tappedTab = visible[index];
                if (tappedTab == _currentTab) {
                  if (settings.tapTabToScrollTop) {
                    final controller = _scrollControllers[tappedTab];
                    if (controller != null && controller.hasClients) {
                      controller.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  }
                  return;
                }
                setState(() {
                  _currentTab = tappedTab;
                });
              },
              onSearchTap: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SearchView()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Blocks interaction while the selected file(s) download to a local cache
/// folder before being handed back to the caller (see
/// `PickController.confirmPick`) - can take a moment for a large file/video.
class _PickingProgressOverlay extends StatelessWidget {
  const _PickingProgressOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing file...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
