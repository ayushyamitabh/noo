import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/app_tab.dart';
import 'providers/server_provider.dart';
import 'theme/app_theme.dart';
import 'views/login_view.dart';
import 'views/search_view.dart';
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
            Icon(Icons.cloud_outlined, size: 48, color: colorScheme.primary),
            const SizedBox(height: 20),
            CircularProgressIndicator(color: colorScheme.primary),
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
  }

  @override
  void dispose() {
    for (final c in _scrollControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();
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
              setState(() {
                _currentTab = visible[index];
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
