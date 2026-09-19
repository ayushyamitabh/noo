# Architecture

## Layout

```
lib/
  main.dart          # app root, theme wiring, top-level navigation switch,
                      # MainShellView (bottom-nav shell), share-intent listener
  models/             # plain data classes (NextcloudItem, NextcloudShare,
                       # SavedAccount, AppTab, ...)
  providers/           # ServerProvider — the single app-wide ChangeNotifier
  services/             # network/IO: NextcloudService, LoginFlowService,
                         # AccountStore, AppLockService
  theme/                 # AppTheme (Material 3 ThemeData)
  views/                  # one screen each (FilesView, PhotosView, TrashView,
                           # SharesView, RecentView, ActivityView, SearchView,
                           # AccountView, LoginView, FileViewerScreen,
                           # ShareUploadView, LockScreenView)
  widgets/                 # reusable pieces shared across views
    details/                # the file-details bottom sheet and its tabs
```

`views/` files are screens routed to directly (a tab, or pushed via
`Navigator`). `widgets/` files are building blocks used by more than one
view (or complex enough to warrant their own file) — nothing in `widgets/`
owns app state itself; it reads it from the `ServerProvider` passed down or
read via `context.watch`/`context.read`.

## State management

There is exactly one `ChangeNotifier`: [`ServerProvider`](../../lib/providers/server_provider.dart)
(~1500 lines). It is created once in `main()` and provided at the root with
`provider`'s `ChangeNotifierProvider`. It owns:

- **Multi-account state**: the list of saved accounts (`accounts`), which one
  is active (`activeAccountId`/`activeAccount`), and a `_sessionGeneration`
  counter incremented on every account switch so an in-flight fetch from the
  account just left can recognize it's stale and discard its result instead
  of writing into the newly-active account's state — every method that
  writes fetched data into a shared field (`refreshData`, `fetchAllMedia`,
  `fetchTrash`, `fetchShares`, `fetchRecent`,
  `_applyCredentialsForAccount`) captures the generation at entry and checks
  it before each write. See `server.md` for the full account-switch/storage
  story.
- auth/session state for whichever account is active (`isLoggedIn`,
  `isRestoringSession`, login-flow status)
- the active `NextcloudService` instance (null until logged in)
- all fetched data, scoped to the active account (`items`, `quota`,
  `activities`, `photoItems`, `trashItems`, `shares`, `recentItems`) — all
  torn down and refetched fresh on every account switch (no simultaneous
  multi-account state; only one account's content is ever live in memory)
- navigation-within-files state (`currentFolderPath`, `pathStack`), plus an
  in-memory `_directoryCache` keyed by folder path (see `CachePolicy`)
- UI settings that persist across launches — split into **global** (theme
  mode, seed color, dynamic-color toggle, bottom-bar opacity/blur,
  tap-tab-to-scroll-top, seek bar style, tab order/visibility/default, swipe
  actions, login lock, sync-on-cellular — see below) and **per-account**
  (grid/list view, favorites-only, show-hidden, storage scope, Photos sort,
  Files' per-folder sort map, cache policy, synced folders) — see
  `server.md` for exactly which is which and why
- **Login lock** (`loginLockEnabled`/`lockAccountSwitching`/
  `lockHiddenFiles`/`needsUnlock`): an app-wide PIN/biometric gate via
  `AppLockService` (a thin wrapper over `local_auth` — this app never
  stores or hashes a PIN itself, it delegates entirely to whatever
  credential the OS already has configured). `needsUnlock` is
  `loginLockEnabled && !_isUnlocked`, where `_isUnlocked` is transient
  (never persisted) and reset to `false` on every backgrounding
  (`didChangeAppLifecycleState`, `AppLifecycleState.paused`) so the lock has
  real value rather than only firing once per cold start. `switchAccount`/
  `cycleToNextAccount`/`cycleToPreviousAccount` and *enabling* (not
  disabling) `showHiddenFiles`/`showHiddenPhotos` each call the shared
  `_passGate` helper, which no-ops unless both `loginLockEnabled` and the
  relevant per-feature toggle are on.

New **global** state belongs on `ServerProvider` as a private field + getter
+ a method that mutates it, calls `notifyListeners()`, and persists via
`_prefsFuture`. New **per-account** state follows the same shape but
persists through `_persistAccountPref` (namespaces the pref key under
`acct_<activeAccountId>_...` via `AccountStore.accountPrefKey`) and must be
reset/reloaded in `_applyAccountPrefs` so it's correct after a switch.
Screen-local state (e.g. a `TextEditingController`, an expanded/collapsed
flag) stays in that view's own `State` class — see `standards.md` for the
split.

There's no separate repository/data layer: views call `ServerProvider`
methods directly, which call `NextcloudService`/`LoginFlowService`/
`AccountStore`/`AppLockService`.

## Navigation / screen flow

`main.dart`'s `NextcloudApp` picks the app's `home` screen from provider
state, no named routes:

- `provider.isRestoringSession` → `_SplashView` (monochrome app icon,
  tinted via `ColorFiltered` to the theme's `onSurface` so it works in both
  light/dark, plus a small spinner, while `flutter_secure_storage`/
  `shared_preferences` are read on startup)
- else `!provider.isLoggedIn` → `LoginView` (server-address entry + Login
  Flow v2) — `isLoggedIn` is only ever false here or after the last saved
  account is removed; switching between multiple saved accounts never
  routes through this screen (see `server.md`)
- else `provider.needsUnlock` → `LockScreenView` (login lock — see above)
- else `MainShellView`

`MainShellView` is a bottom-nav `IndexedStack` over up to 7 tabs — Files,
Photos, Favorites, Activity, Trash, Shares, Recent — user-configurable
(order, visibility up to `maxVisibleTabs`, default tab) via
`AppTab`/`ServerProvider` and rendered through `buildAppTabView`
(`widgets/app_tab_view_builder.dart`). `maxVisibleTabs` (5) is less than the
total tab count, and `ServerProvider._enforceMaxVisibleTabs` already
auto-hides overflow on load (fresh install, or - as when Favorites was
added - an existing saved tab order from before a new tab existed), so
adding a tab to the `AppTab` enum needs no extra migration.
Each tab keeps its own `ScrollController` (survives tab switches via
`IndexedStack`'s built-but-hidden trees) and tapping the already-active tab
scrolls it back to top (`tapTabToScrollTop` setting). `MainShellView` also
owns the app's share-intent listener (`ShareIntentService`, backed by
hand-rolled native handling in `MainActivity.kt` - see `server.md` for why
this isn't the `receive_sharing_intent` plugin): both `getInitialShare()`
(cold start via another app's "Share to...") and `onNewShare` (already
running) push `ShareUploadView`. `FilesView`'s own "+" → "Upload File"
(`_pickAndUploadFile`) reaches the exact same `ShareUploadView` screen
through the same `SharedFileRef`-based path (wrapping `file_picker`'s
result `Uri`s instead of a share intent's) rather than a separate
in-app-only upload, so both entry points get the same destination picker
and the same durable background-service upload. It similarly owns the pick-intent listener
(`PickIntentService` - see `server.md` for the full "being picked by
another app" story) that feeds `ServerProvider.pickRequest`; while
`isPicking`, the visible tab list is overridden to just Files and Photos
regardless of the user's own hidden/reordered tab settings, since those
are the only two views that know how to handle a picking-mode tap and the
only two that make sense as external "choose a file" sources.
`MainShellView` also fires a one-time notification-permission prompt on
its first mount (`_maybeRequestNotificationPermission`, gated by a plain
`shared_preferences` flag so it only ever asks once, not on every
launch): a plain-language `AlertDialog` explaining why Noo wants it
(upload/download progress notifications - see `ShareUploadService.kt`/
`DownloadService.kt`) before the OS's own `permission_handler`-driven
`Permission.notification.request()`, since the bare system prompt gives
no context on its own.

`FloatingBottomNavBar` (`widgets/floating_bottom_bar.dart`) wraps its
pill's item row in a horizontal `SingleChildScrollView` rather than a
plain `Row`, so a wide selected-item label plus several icon-only tabs
scrolls instead of overflowing on narrower screens.

All six tabs, plus `ShareUploadView` (the share-to-upload destination
picker, pushed rather than a tab - see below), share
[`SyncedHeaderScaffold`](../../lib/widgets/synced_header_scaffold.dart) — a
`CustomScrollView` with a pull-down "sync status" header (Google
Photos-style) and a classic Material refresh spinner shown during a
pull-triggered sync. `ShareUploadView` mirrors the Files tab's own
controls-row/breadcrumbs sticky header almost exactly, so arriving via
another app's "Share to..." sheet still lands on the same top chrome
instead of a plain `AppBar` - its `actions` are `[ProfileAvatarButton()]`
only (no `MoreTabsButton`: there's nowhere useful for it to go mid-upload,
since jumping to another tab would abandon the destination picker);
backing out is the system back gesture/button, not a bespoke close icon in
the app bar. Its bottom action - "Upload to
{folder}" - and the uploading-file-name summary above it (single line,
auto-scrolling via `MarqueeTitle` if it doesn't fit) live together in one
rounded-top, elevated `Material` bar as `bottomNavigationBar`, reading as a
sheet peeking up from the bottom edge rather than a plain flat bar.
[`MarqueeTitle`](../../lib/widgets/marquee_title.dart) (`package:marquee`) is
shared with `FileViewerScreen`'s title - falls back to a plain ellipsized
`Text` when the content already fits, so short text never marquees.

The Move/Copy destination picker
([`MoveCopyDestinationPicker`](../../lib/views/move_copy_destination_picker.dart),
pushed from Files/Photos' selection toolbar - see `server.md` for the
backend side) visually mirrors `ShareUploadView`'s browser the same way,
but is a deliberately different case for state: it does **not** reuse
`ServerProvider`'s shared `currentFolderPath`/`pathStack`/`items`, and
owns its own local navigation state instead, fetching through the
stateless `ServerProvider.fetchFolderListing`/`applyFilesDisplayPrefs`
pair. `ShareUploadView` can get away with hijacking the shared state
because it always resets to root on entry and pops all the way to the
app's root route on completion - fine for a cold share-intent launch with
no prior browsing session to preserve. The Move/Copy picker is pushed
*while the user is actively browsing a specific Files-tab folder*, so
reusing the shared state would strand that folder's `pathStack` under it;
its local state means popping back always lands the user exactly where
they were, untouched.
`SearchView`, `AccountView` (Settings), the file-details sheet, and the
share sheet are pushed on top via
`Navigator`/`showModalBottomSheet`/`showGradualBottomSheet` rather than
being tabs. `ProfileAvatarButton` (top-right on every tab) opens Settings on
tap and cycles between saved accounts on a vertical swipe.

Files and Photos (the two tabs with multi-select) pass their selection
toolbar into `SyncedHeaderScaffold`'s `selectionBar` param rather than
rendering it as a second sliver app bar inside their own content: while
non-null, it fully takes over the pinned top bar in place of the
sync-status chip/`actions`/pull-to-reveal quota panel, so selecting reads
as replacing the whole top chrome rather than adding a strip beneath it.
