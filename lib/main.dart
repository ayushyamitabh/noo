import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/app_tab.dart';
import 'models/pick_request.dart';
import 'providers/server_provider.dart';
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
    ChangeNotifierProvider(
      create: (_) => ServerProvider(),
      child: const NextcloudApp(),
    ),
  );
}

class NextcloudApp extends StatelessWidget {
  const NextcloudApp({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          title: 'Noo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(
            provider.seedColor,
            dynamicScheme: lightDynamic,
            useDynamicColor: provider.useDynamicColor,
          ),
          darkTheme: AppTheme.dark(
            provider.seedColor,
            dynamicScheme: darkDynamic,
            useDynamicColor: provider.useDynamicColor,
            amoled: provider.amoledDark,
          ),
          themeMode: provider.themeMode,
          home: provider.isRestoringSession
              ? const _SplashView()
              : (!provider.isLoggedIn
                    ? const LoginView()
                    : (provider.needsUnlock
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
    _currentTab = context.read<ServerProvider>().defaultTab;

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
        context.read<ServerProvider>().setPickRequest(request);
      }
    });
    _pickSub = PickIntentService.onNewPickRequest.listen((request) {
      if (mounted) context.read<ServerProvider>().setPickRequest(request);
    });
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
    final provider = context.watch<ServerProvider>();

    // A one-shot request (e.g. tapping a search result) to switch tabs -
    // consumed here so it only fires once, then cleared after this frame
    // (clearing it synchronously would call notifyListeners mid-build).
    final requestedTab = provider.requestedTab;
    if (requestedTab != null) {
      _currentTab = requestedTab;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => provider.consumeRequestedTab(),
      );
    }

    final pickRequest = provider.pickRequest;
    // While acting as another app's picker, only Files and Photos make
    // sense as browsable sources - Trash/Shares/Activity/Recent aren't
    // real "pick a file from here" destinations, and only these two tabs'
    // views even know how to handle picking-mode taps. This overrides the
    // user's own hidden/reordered tab settings rather than respecting
    // them, since picking is a separate mode from normal browsing.
    final visible = pickRequest != null
        ? [AppTab.files, AppTab.photos]
        : provider.visibleTabs;
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
        if (!didPop && pickRequest != null) provider.cancelPick();
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
            if (provider.isDownloadingForPick) const _PickingProgressOverlay(),
            // Each tab now renders its own sticky selection toolbar inline
            // (right under its sort/filter row) instead of this shell
            // swapping in a shared floating bar - the bottom nav stays put
            // and usable regardless of selection state.
            FloatingBottomNavBar(
              selectedIndex: selectedIndex,
              items: navItems,
              opacity: provider.bottomBarOpacity,
              blurSigma: provider.bottomBarBlur,
              onDestinationSelected: (index) {
                final tappedTab = visible[index];
                if (tappedTab == _currentTab) {
                  if (provider.tapTabToScrollTop) {
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
/// `ServerProvider.confirmPick`) - can take a moment for a large file/video.
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
