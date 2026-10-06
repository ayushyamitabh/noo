import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_tab.dart';
import '../models/selection_action.dart';
import '../theme/app_theme.dart';
import '../widgets/noo/nav/noo_nav_style.dart';

/// What swiping a Files list-view item left/right does, user-configurable
/// in Settings.
enum SwipeAction { none, favorite, delete, share }

/// How the Android Upload FAB is sized: [auto] expands on Files/Photos and
/// shrinks to an icon elsewhere, [mini] is always icon-only, [expanded]
/// always shows the label.
enum FabStyle { auto, mini, expanded }

/// Thumb/track presets for the video player's seek bar, matching the four
/// combinations offered by other Material You media players: a Material 3
/// slider-style thumb ([classic]), an animated travelling wave with a round
/// thumb ([wavy]), a thin flat bar with no distinct thumb ([slim]), and an
/// animated wave with a tick-mark thumb ([squiggly]).
enum MediaProgressBarStyle { classic, wavy, slim, squiggly }

/// The frosted-glass bottom bar's blur sigma and surface opacity, in three
/// ready-made strengths (Settings, Appearance). Moving either slider off all
/// three leaves no preset selected (a custom mix).
enum FrostedGlassPreset {
  less(blur: 10, opacity: 0.88, label: 'Less'),
  standard(blur: 20, opacity: 0.72, label: 'Default'),
  more(blur: 32, opacity: 0.55, label: 'More');

  final double blur;
  final double opacity;
  final String label;

  const FrostedGlassPreset({
    required this.blur,
    required this.opacity,
    required this.label,
  });
}

const double minFrostedBlur = 0;
const double maxFrostedBlur = 40;
const double minFrostedOpacity = 0.3;
const double maxFrostedOpacity = 1.0;

/// Global (not per-account) UI settings: theme, bottom-nav appearance, tab
/// configuration, swipe actions. Independent of login state - these mean
/// the same thing whether any account is signed in or not, unlike
/// [FilesController]'s/etc. per-account display prefs. Split out of the
/// former single `ServerProvider` god object.
class SettingsController extends ChangeNotifier {
  static const _prefThemeMode = 'ui_theme_mode';
  static const _prefUseDynamicColor = 'ui_use_dynamic_color';
  static const _prefSeedColor = 'ui_seed_color';
  static const _prefTabOrder = 'ui_tab_order';
  static const _prefSelectionActionOrder = 'ui_selection_action_order';
  static const _prefHiddenTabs = 'ui_hidden_tabs';
  static const _prefDefaultTab = 'ui_default_tab';
  static const _prefSwipeLeftAction = 'ui_swipe_left_action';
  static const _prefSwipeRightAction = 'ui_swipe_right_action';
  static const _prefFabStyle = 'ui_fab_style';
  static const _prefBottomBarStyle = 'ui_bottom_bar_style';
  static const _prefBottomBarFrosted = 'ui_bottom_bar_frosted';
  static const _prefFrostedBlur = 'ui_bottom_bar_frosted_blur';
  static const _prefFrostedOpacity = 'ui_bottom_bar_frosted_opacity';
  static const _prefNavMenuStyle = 'ui_nav_menu_style';
  static const _prefSearchInBottomBar = 'ui_search_in_bottom_bar';
  static const _prefAmoledDark = 'ui_amoled_dark';
  static const _prefMediaProgressBarStyle = 'ui_media_progress_bar_style';
  static const _prefTapTabToScrollTop = 'ui_tap_tab_to_scroll_top';

  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Color _seedColor = AppTheme.defaultAccent;
  ThemeMode _themeMode = ThemeMode.system;
  NooBottomBarStyle _bottomBarStyle = NooBottomBarStyle.attached;
  NooNavMenuStyle _navMenuStyle = NooNavMenuStyle.drawer;
  bool _bottomBarFrosted = false;
  double _frostedBlur = FrostedGlassPreset.standard.blur;
  double _frostedOpacity = FrostedGlassPreset.standard.opacity;
  bool _searchInBottomBar = false;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  MediaProgressBarStyle _mediaProgressBarStyle = MediaProgressBarStyle.wavy;

  bool _tapTabToScrollTop = true;

  List<AppTab> _tabOrder = AppTab.values.toList();
  Set<AppTab> _hiddenTabs = {};
  AppTab _defaultTab = AppTab.files;

  List<SelectionActionKind> _selectionActionOrder = SelectionActionKind.values
      .toList();

  SwipeAction _swipeLeftAction = SwipeAction.delete;
  SwipeAction _swipeRightAction = SwipeAction.favorite;
  FabStyle _fabStyle = FabStyle.auto;

  // A one-shot request for the shell to switch its active bottom-nav tab
  // (e.g. a search result landing on Files) - consumed and cleared by
  // MainShellView the next time it builds, not a persisted preference.
  AppTab? _requestedTab;
  AppTab? get requestedTab => _requestedTab;

  /// Asks the shell to switch its active bottom-nav tab to [tab] - e.g. so
  /// tapping a search result lands the user on the Files tab even if they
  /// opened search from somewhere else.
  void requestTab(AppTab tab) {
    _requestedTab = tab;
    notifyListeners();
  }

  /// Called by the shell once it's consumed [requestedTab].
  void consumeRequestedTab() {
    _requestedTab = null;
  }

  SettingsController() {
    _load();
  }

  Color get seedColor => _seedColor;
  ThemeMode get themeMode => _themeMode;
  NooBottomBarStyle get bottomBarStyle => _bottomBarStyle;
  bool get bottomBarFrosted => _bottomBarFrosted;
  double get bottomBarFrostedBlur => _frostedBlur;
  double get bottomBarFrostedOpacity => _frostedOpacity;

  /// The preset the current blur/opacity match exactly, or null when the
  /// sliders have been moved to something custom.
  FrostedGlassPreset? get frostedPreset => FrostedGlassPreset.values
      .where((p) => p.blur == _frostedBlur && p.opacity == _frostedOpacity)
      .firstOrNull;
  NooNavMenuStyle get navMenuStyle => _navMenuStyle;
  bool get searchInBottomBar => _searchInBottomBar;
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  MediaProgressBarStyle get mediaProgressBarStyle => _mediaProgressBarStyle;
  bool get tapTabToScrollTop => _tapTabToScrollTop;

  /// The cap a screen should actually enforce for the *regular*, user-
  /// reorderable tabs - one below [defaultMaxVisibleTabs] while
  /// [searchInBottomBar] is on, since Search then takes that freed-up slot
  /// itself (the row's last tab when attached, its own satellite circle
  /// when floating - see `NooBottomBar`) rather than counting against it.
  int get maxVisibleTabs =>
      defaultMaxVisibleTabs - (_searchInBottomBar ? 1 : 0);

  /// Every tab in the user's configured order, including hidden ones — used
  /// by the reorder/visibility settings UI.
  List<AppTab> get tabOrder => _tabOrder;
  Set<AppTab> get hiddenTabs => _hiddenTabs;
  AppTab get defaultTab => _defaultTab;

  /// The priority order bulk actions (favorite, share, download, ...) show
  /// in on the multi-select action bar - see [orderSelectionActions]. Every
  /// [SelectionActionKind] is always present here (nothing is hidden, only
  /// reordered), so [NooSelectionBar]'s fixed inline slots are always full.
  List<SelectionActionKind> get selectionActionOrder => _selectionActionOrder;

  /// The tabs the bottom nav bar should actually show, in order.
  List<AppTab> get visibleTabs =>
      _tabOrder.where((t) => !_hiddenTabs.contains(t)).toList();

  SwipeAction get swipeLeftAction => _swipeLeftAction;
  SwipeAction get swipeRightAction => _swipeRightAction;
  FabStyle get fabStyle => _fabStyle;

  Future<void> _load() async {
    try {
      final prefs = await _prefsFuture;

      final themeModeName = prefs.getString(_prefThemeMode);
      if (themeModeName != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == themeModeName,
          orElse: () => ThemeMode.system,
        );
      }
      final bottomBarStyleName = prefs.getString(_prefBottomBarStyle);
      if (bottomBarStyleName != null) {
        _bottomBarStyle = NooBottomBarStyle.values.firstWhere(
          (s) => s.name == bottomBarStyleName,
          orElse: () => _bottomBarStyle,
        );
      }
      final navMenuStyleName = prefs.getString(_prefNavMenuStyle);
      if (navMenuStyleName != null) {
        _navMenuStyle = NooNavMenuStyle.values.firstWhere(
          (s) => s.name == navMenuStyleName,
          orElse: () => _navMenuStyle,
        );
      }
      _bottomBarFrosted =
          prefs.getBool(_prefBottomBarFrosted) ?? _bottomBarFrosted;
      _frostedBlur = (prefs.getDouble(_prefFrostedBlur) ?? _frostedBlur).clamp(
        minFrostedBlur,
        maxFrostedBlur,
      );
      _frostedOpacity =
          (prefs.getDouble(_prefFrostedOpacity) ?? _frostedOpacity).clamp(
            minFrostedOpacity,
            maxFrostedOpacity,
          );
      _searchInBottomBar =
          prefs.getBool(_prefSearchInBottomBar) ?? _searchInBottomBar;
      _useDynamicColor =
          prefs.getBool(_prefUseDynamicColor) ?? _useDynamicColor;
      _amoledDark = prefs.getBool(_prefAmoledDark) ?? _amoledDark;
      final progressBarStyleName = prefs.getString(_prefMediaProgressBarStyle);
      if (progressBarStyleName != null) {
        _mediaProgressBarStyle = MediaProgressBarStyle.values.firstWhere(
          (s) => s.name == progressBarStyleName,
          orElse: () => _mediaProgressBarStyle,
        );
      }
      final seedColorValue = prefs.getInt(_prefSeedColor);
      if (seedColorValue != null) _seedColor = Color(seedColorValue);
      _tapTabToScrollTop =
          prefs.getBool(_prefTapTabToScrollTop) ?? _tapTabToScrollTop;

      final savedOrderNames = prefs.getStringList(_prefTabOrder);
      if (savedOrderNames != null) {
        final order = <AppTab>[];
        for (final name in savedOrderNames) {
          final match = AppTab.values.where((t) => t.name == name).firstOrNull;
          if (match != null) order.add(match);
        }
        // Forward-compat: a tab added in a later app update won't be in an
        // older saved order yet, so append anything missing.
        for (final tab in AppTab.values) {
          if (!order.contains(tab)) order.add(tab);
        }
        _tabOrder = order;
      }

      final savedActionOrderNames = prefs.getStringList(
        _prefSelectionActionOrder,
      );
      if (savedActionOrderNames != null) {
        final order = <SelectionActionKind>[];
        for (final name in savedActionOrderNames) {
          final match = SelectionActionKind.values
              .where((k) => k.name == name)
              .firstOrNull;
          if (match != null) order.add(match);
        }
        // Forward-compat: a kind added in a later app update won't be in an
        // older saved order yet, so append anything missing.
        for (final kind in SelectionActionKind.values) {
          if (!order.contains(kind)) order.add(kind);
        }
        _selectionActionOrder = order;
      }

      final savedHiddenNames = prefs.getStringList(_prefHiddenTabs);
      if (savedHiddenNames != null) {
        _hiddenTabs = savedHiddenNames
            .map(
              (name) => AppTab.values.where((t) => t.name == name).firstOrNull,
            )
            .whereType<AppTab>()
            .toSet();
        // Never let every tab end up hidden.
        if (_hiddenTabs.length >= AppTab.values.length) {
          _hiddenTabs = {};
        }
      }

      final savedDefaultName = prefs.getString(_prefDefaultTab);
      if (savedDefaultName != null) {
        final match = AppTab.values
            .where((t) => t.name == savedDefaultName)
            .firstOrNull;
        if (match != null) _defaultTab = match;
      }
      if (_hiddenTabs.contains(_defaultTab)) {
        _defaultTab = _tabOrder.firstWhere(
          (t) => !_hiddenTabs.contains(t),
          orElse: () => _tabOrder.first,
        );
      }
      _enforceMaxVisibleTabs();

      final swipeLeftName = prefs.getString(_prefSwipeLeftAction);
      if (swipeLeftName != null) {
        _swipeLeftAction = SwipeAction.values.firstWhere(
          (a) => a.name == swipeLeftName,
          orElse: () => _swipeLeftAction,
        );
      }
      final swipeRightName = prefs.getString(_prefSwipeRightAction);
      if (swipeRightName != null) {
        _swipeRightAction = SwipeAction.values.firstWhere(
          (a) => a.name == swipeRightName,
          orElse: () => _swipeRightAction,
        );
      }

      final fabName = prefs.getString(_prefFabStyle);
      if (fabName != null) {
        _fabStyle = FabStyle.values.firstWhere(
          (f) => f.name == fabName,
          orElse: () => _fabStyle,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[SettingsController] Preference restore failed: $e');
    }
  }

  void setSeedColor(Color color) {
    _seedColor = color;
    _useDynamicColor = false;
    notifyListeners();
    _prefsFuture.then((p) {
      p.setInt(_prefSeedColor, color.toARGB32());
      p.setBool(_prefUseDynamicColor, false);
    });
  }

  void setUseDynamicColor(bool value) {
    _useDynamicColor = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefUseDynamicColor, value));
  }

  void setAmoledDark(bool value) {
    _amoledDark = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefAmoledDark, value));
  }

  void setMediaProgressBarStyle(MediaProgressBarStyle style) {
    _mediaProgressBarStyle = style;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setString(_prefMediaProgressBarStyle, style.name),
    );
  }

  void setTapTabToScrollTop(bool value) {
    _tapTabToScrollTop = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefTapTabToScrollTop, value));
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefThemeMode, mode.name));
  }

  void setBottomBarStyle(NooBottomBarStyle style) {
    if (_bottomBarStyle == style) return;
    _bottomBarStyle = style;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefBottomBarStyle, style.name));
  }

  void setFrostedBlur(double value) {
    final v = value.clamp(minFrostedBlur, maxFrostedBlur);
    if (_frostedBlur == v) return;
    _frostedBlur = v;
    notifyListeners();
    _prefsFuture.then((p) => p.setDouble(_prefFrostedBlur, v));
  }

  void setFrostedOpacity(double value) {
    final v = value.clamp(minFrostedOpacity, maxFrostedOpacity);
    if (_frostedOpacity == v) return;
    _frostedOpacity = v;
    notifyListeners();
    _prefsFuture.then((p) => p.setDouble(_prefFrostedOpacity, v));
  }

  void setFrostedPreset(FrostedGlassPreset preset) {
    setFrostedBlur(preset.blur);
    setFrostedOpacity(preset.opacity);
  }

  void setBottomBarFrosted(bool value) {
    if (_bottomBarFrosted == value) return;
    _bottomBarFrosted = value;
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefBottomBarFrosted, value));
  }

  void setNavMenuStyle(NooNavMenuStyle style) {
    if (_navMenuStyle == style) return;
    _navMenuStyle = style;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefNavMenuStyle, style.name));
  }

  /// Turning this on lowers [maxVisibleTabs] by one, so re-enforces the cap
  /// immediately in case the user already has a full 5 regular tabs pinned
  /// - same cleanup [_enforceMaxVisibleTabs] already does for a fresh
  /// install/an app update adding a new tab.
  void setSearchInBottomBar(bool value) {
    if (_searchInBottomBar == value) return;
    _searchInBottomBar = value;
    if (value) _enforceMaxVisibleTabs();
    notifyListeners();
    _prefsFuture.then((p) => p.setBool(_prefSearchInBottomBar, value));
  }

  void setTabOrder(List<AppTab> order) {
    _tabOrder = order;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(_prefTabOrder, order.map((t) => t.name).toList()),
    );
  }

  void setSelectionActionOrder(List<SelectionActionKind> order) {
    _selectionActionOrder = order;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(
        _prefSelectionActionOrder,
        order.map((k) => k.name).toList(),
      ),
    );
  }

  /// Shows or hides a tab in the bottom nav bar. Refuses to hide the last
  /// remaining visible tab. If the tab being hidden is the current default,
  /// the default falls back to the next visible tab.
  /// Returns null on success, or a user-facing reason the change was
  /// refused (hiding the last visible tab, or showing a 6th).
  String? setTabHidden(AppTab tab, bool hidden) {
    if (hidden) {
      final remaining = _tabOrder
          .where((t) => t != tab && !_hiddenTabs.contains(t))
          .length;
      if (remaining == 0) return 'At least one tab must stay visible';
      _hiddenTabs = {..._hiddenTabs, tab};
      if (_defaultTab == tab) {
        _defaultTab = _tabOrder.firstWhere((t) => !_hiddenTabs.contains(t));
        _prefsFuture.then(
          (p) => p.setString(_prefDefaultTab, _defaultTab.name),
        );
      }
    } else {
      final currentlyVisible = _tabOrder
          .where((t) => !_hiddenTabs.contains(t))
          .length;
      if (currentlyVisible >= maxVisibleTabs) {
        return 'You can only show up to $maxVisibleTabs tabs at once';
      }
      _hiddenTabs = {..._hiddenTabs}..remove(tab);
    }
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(
        _prefHiddenTabs,
        _hiddenTabs.map((t) => t.name).toList(),
      ),
    );
    return null;
  }

  /// If more than [maxVisibleTabs] end up visible (e.g. a fresh install, or
  /// an existing saved config from before a new tab was added to the app),
  /// hide the overflow automatically rather than exceeding the cap.
  void _enforceMaxVisibleTabs() {
    final visible = _tabOrder.where((t) => !_hiddenTabs.contains(t)).toList();
    if (visible.length <= maxVisibleTabs) return;
    _hiddenTabs = {..._hiddenTabs, ...visible.sublist(maxVisibleTabs)};
    if (_hiddenTabs.contains(_defaultTab)) {
      _defaultTab = _tabOrder.firstWhere((t) => !_hiddenTabs.contains(t));
    }
  }

  void setDefaultTab(AppTab tab) {
    if (_hiddenTabs.contains(tab) || _defaultTab == tab) return;
    _defaultTab = tab;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefDefaultTab, tab.name));
  }

  void setSwipeLeftAction(SwipeAction action) {
    if (_swipeLeftAction == action) return;
    _swipeLeftAction = action;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefSwipeLeftAction, action.name));
  }

  void setSwipeRightAction(SwipeAction action) {
    if (_swipeRightAction == action) return;
    _swipeRightAction = action;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefSwipeRightAction, action.name));
  }

  void setFabStyle(FabStyle style) {
    if (_fabStyle == style) return;
    _fabStyle = style;
    notifyListeners();
    _prefsFuture.then((p) => p.setString(_prefFabStyle, style.name));
  }
}
