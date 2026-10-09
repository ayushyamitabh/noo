import 'dart:async';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/app_tab.dart';
import 'models/pick_request.dart';
import 'providers/connectivity_controller.dart';
import 'providers/favorites_controller.dart';
import 'providers/files_controller.dart';
import 'providers/item_operations.dart';
import 'providers/offline_controller.dart';
import 'providers/photos_controller.dart';
import 'providers/pick_controller.dart';
import 'providers/recent_controller.dart';
import 'providers/session_controller.dart';
import 'providers/settings_controller.dart';
import 'providers/shares_controller.dart';
import 'providers/sync_status_controller.dart';
import 'providers/trash_controller.dart';
import 'services/ios_hinge.dart';
import 'services/mac_secondary_click.dart';
import 'services/pick_intent_service.dart';
import 'services/share_account_service.dart';
import 'services/share_intent_service.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'views/lock_screen_view.dart';
import 'views/login_view.dart';
import 'views/share_upload_view.dart';
import 'widgets/app_drawer.dart';
import 'widgets/app_tab_view_builder.dart';
import 'widgets/tabs/tab_state_slivers.dart';
import 'widgets/app_top_bar.dart';
import 'widgets/avatar_menu.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/create_menu.dart';
import 'widgets/noo/core/noo_button.dart';
import 'widgets/noo/core/noo_pointer_selection.dart';
import 'widgets/noo/core/noo_fab.dart';
import 'widgets/noo/core/noo_logo_loader.dart';
import 'widgets/noo/nav/noo_bottom_bar.dart';
import 'widgets/noo/nav/noo_sidebar.dart';
import 'widgets/noo/nav/noo_toolbar.dart';
import 'widgets/noo/noo_layout.dart';
import 'widgets/noo/overlays/noo_dialog.dart';
import 'widgets/shell/shell_common.dart';
import 'widgets/shell/tablet_account_menu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacSecondaryClick.initialize();
  await IosHinge.initialize();
  // Fonts ship in assets/google_fonts; never fetch them from Google at runtime.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(
    MultiProvider(
      // Split out of the former single `ServerProvider` god object - see
      // `.claude/context/architecture.md`'s "State management" section.
      // Order matters: each `create` below reads earlier providers via
      // `context.read`, which is safe here since none of them are ever
      // replaced/recreated for the app's lifetime (account switching is
      // internal state on SessionController, not a new provider instance).
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityController()),
        ChangeNotifierProvider(
          create: (context) {
            final session = SessionController(context.read());
            // iOS's Share Extension has no Flutter engine; sign-out must wipe
            // what it was given. (Publishing happens in the shell - see
            // ShareAccountSync - once there's a FilesController to read.)
            session.addAccountClearedListener(ShareAccountService.clear);
            return session;
          },
        ),
        ChangeNotifierProvider(create: (_) => SettingsController()),
        // Before SyncStatusController, which follows its Files Cache rule
        // for how often synced files refresh.
        ChangeNotifierProvider(
          create: (context) => FilesController(context.read()),
        ),
        ChangeNotifierProvider(
          // Eager (`lazy: false`) - this controller only loads its persisted
          // state when SessionController fires the account-ready event, and
          // that fires once at startup, before any widget has read this
          // provider. Lazily created, it would register its listener too
          // late and stay empty ("Sync off") until an account switch.
          lazy: false,
          create: (context) =>
              SyncStatusController(context.read(), context.read()),
        ),
        ChangeNotifierProvider(
          create: (context) => PhotosController(context.read(), context.read()),
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
        ChangeNotifierProvider(
          // Eager for the same reason as SyncStatusController above.
          lazy: false,
          create: (context) =>
              OfflineController(context.read(), context.read()),
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
          builder: (context, child) =>
              IosHingeLayout(child: NooPointerSelection(child: child!)),
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
    final colors = context.nooColors;
    return Scaffold(
      backgroundColor: colors.bg,
      // Picks up straight from the Android launch splash, which shows the
      // same full-color logo at the same size on the same background - the
      // logo's own animation is the loading indicator.
      body: const Center(child: NooLogoLoader(width: 112)),
    );
  }
}

class MainShellView extends StatefulWidget {
  const MainShellView({super.key});

  @override
  State<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends State<MainShellView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _paneTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );
  late AppTab _currentTab;
  final Set<AppTab> _selectionActiveTabs = {};
  late final Map<AppTab, ScrollController> _scrollControllers;
  final _refreshKeys = {
    for (final tab in AppTab.values) tab: GlobalKey<RefreshIndicatorState>(),
  };
  StreamSubscription<List<SharedFileRef>>? _shareSub;
  StreamSubscription<PickRequest>? _pickSub;
  ShareAccountSync? _shareAccountSync;

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

    // iOS's Share Extension picks accounts/folders on its own, so it's kept
    // supplied with the accounts, lock settings and hidden-files filters.
    _shareAccountSync = ShareAccountSync(
      context.read<SessionController>(),
      context.read<FilesController>(),
    )..start();

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

    final colors = context.nooColors;
    final shouldRequest = await showNooDialog<bool>(
      context,
      title: 'Allow notifications?',
      barrierDismissible: false,
      children: [
        Text(
          'Noo shows upload and download progress as a notification, so '
          'you can track transfers that keep running in the background.',
          style: NooText.body.copyWith(color: colors.fg2),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 10,
          children: [
            NooButton(
              variant: NooButtonVariant.secondary,
              onTap: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            NooButton(
              variant: NooButtonVariant.primary,
              onTap: () => Navigator.of(context).pop(true),
              child: const Text('Allow'),
            ),
          ],
        ),
      ],
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
    _shareAccountSync?.dispose();
    _paneTransition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final settings = context.watch<SettingsController>();
    final pick = context.watch<PickController>();
    final connectivity = context.watch<ConnectivityController>();
    final quota = context.watch<FilesController>().quota;
    // Cheap and already loaded once the Trash tab has been visited this
    // session - not worth adding a fetch just to populate a nav badge.
    final trashCount = context.watch<TrashController>().items.length;

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
    // them, since picking is a separate mode from normal browsing. With
    // no network at all, every other tab would just show its own loading
    // spinner forever/an error state, so the nav collapses to just Offline
    // - the one tab that works without a connection (see
    // `FilesView(offline: true)`/`ConnectivityController`).
    final overrideActive = pickRequest != null || connectivity.isOffline;
    final pinnedTabs = pickRequest != null
        ? [AppTab.files, AppTab.photos]
        : connectivity.isOffline
        ? [AppTab.offline]
        : settings.visibleTabs;
    // The drawer/sidebar's "More" section - hidden while an override above
    // is active, same as the drawer itself being unavailable during pick.
    final hiddenTabs = overrideActive
        ? const <AppTab>[]
        : settings.tabOrder
              .where((t) => settings.hiddenTabs.contains(t))
              .toList();

    // A tab opened from "More" isn't one of the pinned destinations, but
    // should stay shown and selected (with no destination highlighted in
    // the bottom bar/sidebar) until the user taps a pinned or another
    // "More" tab.
    final displayTabs = !overrideActive && !pinnedTabs.contains(_currentTab)
        ? [...pinnedTabs, _currentTab]
        : pinnedTabs;
    final selectedTab = displayTabs.contains(_currentTab)
        ? _currentTab
        : (displayTabs.isNotEmpty ? displayTabs.first : AppTab.files);
    final selectedIndex = displayTabs
        .indexOf(selectedTab)
        .clamp(0, displayTabs.isEmpty ? 0 : displayTabs.length - 1);
    final pinnedIndex = pinnedTabs.indexOf(selectedTab);

    void selectTab(AppTab tab) {
      if (tab == _currentTab) return;
      if (NooLayout.isDesktop(context) &&
          !MediaQuery.disableAnimationsOf(context)) {
        _paneTransition.forward(from: 0);
      }
      setState(() => _currentTab = tab);
    }

    String? trashBadge(AppTab tab) =>
        tab == AppTab.trash && trashCount > 0 ? '$trashCount' : null;

    final isDesktop = NooLayout.isDesktop(context);
    final navStyle = NooLayout.navStyle(context);
    // Picking/offline already override the tab set itself (see pinnedTabs
    // above) - Search doesn't belong in either: there's nothing to search
    // for a file-picking flow, and Search needs the network Offline mode
    // doesn't have.
    final showBottomBarSearch = !overrideActive && settings.searchInBottomBar;

    // Each tab renders its own sticky selection toolbar inline (right under
    // its sort/filter row) instead of the shell swapping in a shared one,
    // so the nav chrome stays put and usable regardless of selection state.
    //
    // Each tab also builds its own [AppTopBar] (labelled for that tab, not
    // just whichever is currently selected) and plants it as that tab's own
    // first sliver - see `buildAppTabView`'s doc comment and `topBarSliver`
    // in `tabs/tab_state_slivers.dart` - instead of one shared instance
    // living in `Scaffold.appBar`. That's what gives each tab's top bar
    // Material's native floating-away-on-scroll-down/reappear-on-scroll-up
    // behavior, tied to that tab's own `ScrollController`: a fixed
    // `Scaffold.appBar` can't do that (no per-tab scroll signal reaches
    // it), and a shared single instance can't show 7 different tab labels
    // at once now that every tab keeps its own independent scroll state.
    // Null on desktop (which shows `NooToolbar` instead - embedding it here
    // too, since `tabStack` is shared by both layouts below, would double
    // up the top chrome there) and while picking (no top bar at all, same
    // as this screen's old `Scaffold.appBar: pickRequest == null ? ... :
    // null`).
    final tabStack = Stack(
      children: [
        AvatarNavigationBody(
          child: IndexedStack(
            index: selectedIndex,
            children: displayTabs
                .map(
                  (tab) => TabRefreshScope(
                    refreshKey: _refreshKeys[tab]!,
                    child: buildAppTabView(
                      tab,
                      _scrollControllers[tab]!,
                      onSelectionChanged: (selecting) {
                        if (!mounted ||
                            selecting == _selectionActiveTabs.contains(tab)) {
                          return;
                        }
                        setState(() {
                          if (selecting) {
                            _selectionActiveTabs.add(tab);
                          } else {
                            _selectionActiveTabs.remove(tab);
                          }
                        });
                      },
                      topBar: isDesktop || pickRequest != null
                          ? null
                          : AppTopBar(
                              style: navStyle,
                              tab: tab,
                              searchInBottomBar: showBottomBarSearch,
                              navMenuStyle: settings.navMenuStyle,
                              avatarPosition: settings.avatarPosition,
                              uploadButtonStyle: settings.fabStyle,
                            ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        if (pick.isDownloadingForPick) const _PickingProgressOverlay(),
      ],
    );

    final canUpload =
        pickRequest == null &&
        (selectedTab == AppTab.files || selectedTab == AppTab.photos);

    Widget scaffold;
    if (isDesktop) {
      scaffold = Scaffold(
        backgroundColor: colors.bg,
        // Tablets keep the system bars, so inset for them (desktop's
        // insets are zero).
        body: SafeArea(
          child: Row(
            children: [
              NooSidebar(
                // Split at the crease on an unfolded foldable.
                width: NooLayout.foldSplitWidth(context),
                account: const TabletAccountMenu(),
                search: const ShellSearchLauncher(onSurface: true),
                groupItems: true,
                items: [
                  for (final tab in pinnedTabs)
                    NooSidebarItem(
                      icon: tab.icon,
                      label: tab.label,
                      count: trashBadge(tab),
                      selected: tab == selectedTab,
                      onTap: () => selectTab(tab),
                    ),
                  for (final tab in hiddenTabs)
                    NooSidebarItem(
                      icon: tab.icon,
                      label: tab.label,
                      count: trashBadge(tab),
                      selected: tab == selectedTab,
                      onTap: () => selectTab(tab),
                    ),
                ],
                storage: NooSidebarStorage(
                  value: quotaFraction(quota),
                  detail: quotaDetail(quota),
                ),
                settings: NooSidebarItem(
                  icon: LucideIcons.settings,
                  label: 'Settings',
                  onTap: () => openSettings(context),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    NooToolbar(
                      title: selectedTab.label,
                      backgroundColor: colors.bg,
                      framed: false,
                      actions: [
                        Tooltip(
                          message: 'Refresh',
                          child: NooButton(
                            variant: NooButtonVariant.secondary,
                            icon: LucideIcons.refreshCw,
                            iconOnly: true,
                            onTap: () =>
                                _refreshKeys[selectedTab]?.currentState?.show(),
                          ),
                        ),
                        if (canUpload)
                          NooButton(
                            icon: LucideIcons.plus,
                            onTap: () => showCreateMenu(context),
                            child: const Text('Upload'),
                          ),
                      ],
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(NooRadii.card),
                          child: ColoredBox(
                            color: colors.surface2,
                            child: FadeTransition(
                              opacity: Tween<double>(begin: .65, end: 1)
                                  .animate(
                                    CurvedAnimation(
                                      parent: _paneTransition,
                                      curve: Curves.easeOutCubic,
                                    ),
                                  ),
                              child: SizedBox.expand(child: tabStack),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final bottomBarStyle = settings.bottomBarStyle;
      scaffold = Scaffold(
        backgroundColor: colors.bg,
        drawerScrimColor: colors.scrim,
        // The top bar itself no longer lives here - see `tabStack` above.
        drawer: pickRequest == null ? const AppDrawer() : null,
        // The avatar menu replaces the drawer, so the edge swipe must not
        // open it either.
        drawerEnableOpenDragGesture:
            settings.navMenuStyle == NooNavMenuStyle.drawer,
        // Floating needs the body to draw behind the bar's own transparent
        // margin (see NooBottomBarStyle's doc comment) instead of stopping
        // short of it like attached does; a frosted bar needs it too, or
        // there'd be nothing behind it to blur.
        extendBody: NooBottomBar.drawsBehindBody(
          bottomBarStyle,
          settings.bottomBarFrosted,
        ),
        // Android-only extended Upload FAB - iOS uses the top bar's Upload
        // instead (see AppTopBar). Stays mounted across every tab (picking
        // aside) and collapses to an icon-only circle off Files/Photos,
        // rather than the Scaffold popping it fully in/out on every tab
        // switch - see NooFab's [collapsed].
        floatingActionButton:
            pickRequest == null &&
                navStyle == NooNavStyle.android &&
                !_selectionActiveTabs.contains(selectedTab)
            ? NooFab(
                collapsed: switch (settings.fabStyle) {
                  FabStyle.auto => !canUpload,
                  FabStyle.mini => true,
                  FabStyle.expanded => false,
                },
                barStyle: bottomBarStyle,
                onTap: () => showCreateMenu(context),
              )
            : null,
        body: TweenAnimationBuilder<double>(
          tween: Tween(
            end: switch (settings.fabStyle) {
              FabStyle.auto => canUpload ? 1.0 : 0.0,
              FabStyle.mini => 0.0,
              FabStyle.expanded => 1.0,
            },
          ),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : NooMotion.base,
          curve: NooMotion.ease,
          child: tabStack,
          builder: (context, progress, child) =>
              UploadButtonAnimation(progress: progress, child: child!),
        ),
        bottomNavigationBar: BottomNavBar(
          style: navStyle,
          barStyle: bottomBarStyle,
          frosted: settings.bottomBarFrosted,
          frostedBlur: settings.bottomBarFrostedBlur,
          frostedOpacity: settings.bottomBarFrostedOpacity,
          tabs: pinnedTabs,
          selectedIndex: pinnedIndex,
          onSearchTap: showBottomBarSearch ? () => openSearch(context) : null,
          avatarInBottomBar:
              pickRequest == null &&
              settings.navMenuStyle == NooNavMenuStyle.avatarMenu &&
              settings.avatarPosition == AvatarPosition.bottom,
          onDestinationSelected: (index) {
            final tappedTab = pinnedTabs[index];
            if (tappedTab == _currentTab) {
              if (settings.tapTabToScrollTop) {
                final controller = _scrollControllers[tappedTab];
                // `hasClients` only means a position is attached - not that
                // it's finished its first layout. Calling animateTo before
                // that throws deep inside Flutter's ballistic-scroll code
                // (min/maxScrollExtent are still null), and since this
                // fires synchronously from the nav bar's tap handler, the
                // exception corrupts that tab's scroll view instead of
                // just being logged - a real crash seen in the wild
                // (Files rendering empty after re-tapping its own tab).
                if (controller != null &&
                    controller.hasClients &&
                    controller.position.hasContentDimensions) {
                  controller.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
              return;
            }
            selectTab(tappedTab);
          },
        ),
      );
    }

    return PopScope(
      // While picking, system back cancels the pick (and tells the caller
      // nothing was chosen) instead of exiting the app from under it -
      // there's no Navigator route to pop at this, the root screen.
      canPop: pickRequest == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && pickRequest != null) pick.cancelPick();
      },
      child: isDesktop ? scaffold : AvatarNavigationHost(child: scaffold),
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
    final colors = context.nooColors;
    return Positioned.fill(
      child: ColoredBox(
        color: colors.scrim,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(NooRadii.dialog),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: colors.accent),
                const SizedBox(height: 16),
                Text(
                  'Preparing file…',
                  style: NooText.body.copyWith(color: colors.fg1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
