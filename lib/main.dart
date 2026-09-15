import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'providers/server_provider.dart';
import 'theme/app_theme.dart';
import 'views/account_view.dart';
import 'views/activity_view.dart';
import 'views/files_view.dart';
import 'views/login_view.dart';
import 'views/photos_view.dart';
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

    return MaterialApp(
      title: 'Nextcloud Material',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(provider.seedColor),
      darkTheme: AppTheme.dark(provider.seedColor),
      themeMode: provider.themeMode,
      home: provider.isLoggedIn ? const MainShellView() : const LoginView(),
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
  bool _isNavVisible = true;

  late final List<ScrollController> _scrollControllers;

  @override
  void initState() {
    super.initState();
    _scrollControllers = List.generate(4, (index) {
      final controller = ScrollController();
      controller.addListener(() {
        if (controller.position.userScrollDirection == ScrollDirection.reverse) {
          if (_isNavVisible) {
            setState(() {
              _isNavVisible = false;
            });
          }
        } else if (controller.position.userScrollDirection == ScrollDirection.forward) {
          if (!_isNavVisible) {
            setState(() {
              _isNavVisible = true;
            });
          }
        }
      });
      return controller;
    });
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
    final navItems = const [
      FloatingNavItem(
        label: 'Files',
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder_rounded,
      ),
      FloatingNavItem(
        label: 'Photos',
        icon: Icons.photo_library_outlined,
        selectedIcon: Icons.photo_library_rounded,
      ),
      FloatingNavItem(
        label: 'Activity',
        icon: Icons.history_rounded,
        selectedIcon: Icons.history_toggle_off_rounded,
      ),
      FloatingNavItem(
        label: 'Account',
        icon: Icons.account_circle_outlined,
        selectedIcon: Icons.account_circle_rounded,
      ),
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
              AccountView(scrollController: _scrollControllers[3]),
            ],
          ),
          FloatingBottomNavBar(
            selectedIndex: _currentIndex,
            items: navItems,
            isVisible: _isNavVisible,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
                _isNavVisible = true;
              });
            },
          ),
        ],
      ),
    );
  }
}
