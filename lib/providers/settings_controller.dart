import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_tab.dart';
import '../theme/app_theme.dart';

/// What swiping a Files list-view item left/right does, user-configurable
/// in Settings.
enum SwipeAction { none, favorite, delete, share }

/// Thumb/track presets for the video player's seek bar, matching the four
/// combinations offered by other Material You media players: a Material 3
/// slider-style thumb ([classic]), an animated travelling wave with a round
/// thumb ([wavy]), a thin flat bar with no distinct thumb ([slim]), and an
/// animated wave with a tick-mark thumb ([squiggly]).
enum MediaProgressBarStyle { classic, wavy, slim, squiggly }

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
  static const _prefHiddenTabs = 'ui_hidden_tabs';
  static const _prefDefaultTab = 'ui_default_tab';
  static const _prefSwipeLeftAction = 'ui_swipe_left_action';
  static const _prefSwipeRightAction = 'ui_swipe_right_action';
  static const _prefAmoledDark = 'ui_amoled_dark';
  static const _prefMediaProgressBarStyle = 'ui_media_progress_bar_style';
  static const _prefTapTabToScrollTop = 'ui_tap_tab_to_scroll_top';

  final Future<SharedPreferences> _prefsFuture =
      SharedPreferences.getInstance();

  Color _seedColor = AppTheme.defaultNextcloudBlue;
  ThemeMode _themeMode = ThemeMode.system;
  bool _useDynamicColor = true;
  bool _amoledDark = false;
  MediaProgressBarStyle _mediaProgressBarStyle = MediaProgressBarStyle.wavy;

  bool _tapTabToScrollTop = true;

  List<AppTab> _tabOrder = AppTab.values.toList();
  Set<AppTab> _hiddenTabs = {};
  AppTab _defaultTab = AppTab.files;

  SwipeAction _swipeLeftAction = SwipeAction.delete;
  SwipeAction _swipeRightAction = SwipeAction.favorite;

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
  bool get useDynamicColor => _useDynamicColor;
  bool get amoledDark => _amoledDark;
  MediaProgressBarStyle get mediaProgressBarStyle => _mediaProgressBarStyle;
  bool get tapTabToScrollTop => _tapTabToScrollTop;

  /// Every tab in the user's configured order, including hidden ones — used
  /// by the reorder/visibility settings UI.
  List<AppTab> get tabOrder => _tabOrder;
  Set<AppTab> get hiddenTabs => _hiddenTabs;
  AppTab get defaultTab => _defaultTab;

  /// The tabs the bottom nav bar should actually show, in order.
  List<AppTab> get visibleTabs =>
      _tabOrder.where((t) => !_hiddenTabs.contains(t)).toList();

  SwipeAction get swipeLeftAction => _swipeLeftAction;
  SwipeAction get swipeRightAction => _swipeRightAction;

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

  void setTabOrder(List<AppTab> order) {
    _tabOrder = order;
    notifyListeners();
    _prefsFuture.then(
      (p) => p.setStringList(_prefTabOrder, order.map((t) => t.name).toList()),
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
}
