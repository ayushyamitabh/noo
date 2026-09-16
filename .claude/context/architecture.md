# Architecture

## Layout

```
lib/
  main.dart          # app root, theme wiring, top-level navigation switch
  models/             # plain data classes (NextcloudItem, NextcloudShare, ...)
  providers/           # ServerProvider — the single app-wide ChangeNotifier
  services/             # network/IO: NextcloudService, LoginFlowService
  theme/                 # AppTheme (Material 3 ThemeData)
  views/                  # one screen each (FilesView, PhotosView, ...)
  widgets/                 # reusable pieces shared across views
    details/                # the file-details bottom sheet and its tabs
```

`views/` files are screens routed to directly (a tab, or pushed via
`Navigator`). `widgets/` files are building blocks used by more than one
view (or complex enough to warrant their own file) — nothing in `widgets/`
owns app state itself; it reads it from the `ServerProvider` passed down or
read via `context.watch`/`context.read`.

## State management

There is exactly one `ChangeNotifier`: [`ServerProvider`](../../lib/providers/server_provider.dart).
It is created once in `main()` and provided at the root with `provider`'s
`ChangeNotifierProvider`. It owns:

- auth/session state (`isLoggedIn`, `isRestoringSession`, login-flow status)
- the active `NextcloudService` instance (null until logged in)
- all fetched data (`items`, `quota`, `activities`)
- navigation-within-files state (`currentFolderPath`, `pathStack`)
- UI settings that persist across launches (theme mode, seed color, dynamic
  color toggle, bottom-bar opacity/blur, sort/filter/view-mode prefs)

New app-wide state belongs on `ServerProvider` as a private field + getter +
a method that mutates it and calls `notifyListeners()`. Screen-local state
(e.g. a `TextEditingController`, an expanded/collapsed flag) stays in that
view's own `State` class — see `standards.md` for the split.

There's no separate repository/data layer: views call `ServerProvider`
methods directly, which call `NextcloudService`/`LoginFlowService`.

## Navigation / screen flow

`main.dart`'s `NextcloudApp` picks the app's `home` screen from provider
state, no named routes:

- `provider.isRestoringSession` → `_SplashView` (spinner while
  `flutter_secure_storage`/`shared_preferences` are read on startup)
- else `!provider.isLoggedIn` → `LoginView` (server-address entry + Login
  Flow v2)
- else `MainShellView`

`MainShellView` is a bottom-nav `IndexedStack` with three persistent tabs —
Files, Photos, Activity — each keeping its own `ScrollController` so state
(scroll position, `IndexedStack`'s built-but-hidden trees) survives tab
switches. `SearchView` and the file-details sheet are pushed on top via
`Navigator`/`showModalBottomSheet` rather than being tabs.
