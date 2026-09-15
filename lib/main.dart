import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/server_provider.dart';
import 'theme/app_theme.dart';
import 'views/activity_view.dart';
import 'views/files_view.dart';
import 'views/login_view.dart';
import 'views/photos_view.dart';
import 'views/search_view.dart';
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
  int _currentIndex = 0;

  late final List<ScrollController> _scrollControllers;

  @override
  void initState() {
    super.initState();
    _scrollControllers = List.generate(3, (index) => ScrollController());
  }

  @override
  void dispose() {
    for (var c in _scrollControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ServerProvider>();
    final navItems = const [
      FloatingNavItem(label: 'Files', icon: Icons.folder_rounded),
      FloatingNavItem(label: 'Photos', icon: Icons.photo_library_rounded),
      FloatingNavItem(label: 'Activity', icon: Icons.history_rounded),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              FilesView(scrollController: _scrollControllers[0]),
              PhotosView(scrollController: _scrollControllers[1]),
              ActivityView(scrollController: _scrollControllers[2]),
            ],
          ),
          FloatingBottomNavBar(
            selectedIndex: _currentIndex,
            items: navItems,
            opacity: provider.bottomBarOpacity,
            blurSigma: provider.bottomBarBlur,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
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
