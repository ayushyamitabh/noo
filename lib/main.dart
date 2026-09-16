import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'models/app_tab.dart';
import 'providers/server_provider.dart';
import 'theme/app_theme.dart';
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
              : (provider.isLoggedIn
                    ? const MainShellView()
                    : const LoginView()),
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
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

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
    // (getInitialMedia) and a share arriving while the app is already
    // running (getMediaStream) - the plugin guarantees the stream doesn't
    // re-emit whatever getInitialMedia already returned.
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
    );
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    final uploadable = files
        .where(
          (f) =>
              f.type != SharedMediaType.text && f.type != SharedMediaType.url,
        )
        .toList();
    if (uploadable.isEmpty) return;
    ReceiveSharingIntent.instance.reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ShareUploadView(files: uploadable)),
      );
    });
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    _shareSub?.cancel();
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

    final visible = provider.visibleTabs;
    final selectedTab = visible.contains(_currentTab)
        ? _currentTab
        : (visible.isNotEmpty ? visible.first : AppTab.files);
    final selectedIndex = visible
        .indexOf(selectedTab)
        .clamp(0, visible.isEmpty ? 0 : visible.length - 1);

    final navItems = visible
        .map((tab) => FloatingNavItem(label: tab.label, icon: tab.icon))
        .toList();

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: selectedIndex,
            children: visible
                .map((tab) => buildAppTabView(tab, _scrollControllers[tab]!))
                .toList(),
          ),
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
    );
  }
}
