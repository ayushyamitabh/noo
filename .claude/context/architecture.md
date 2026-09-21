# Architecture

## Layout

```
lib/
  main.dart          # app root, theme wiring, top-level navigation switch,
                      # MainShellView (bottom-nav shell), share-intent listener
  models/             # plain data classes (NextcloudItem, NextcloudShare,
                       # SavedAccount, AppTab, ...)
  providers/           # per-domain ChangeNotifiers (SessionController,
                       # FilesController, PhotosController, ...) plus
                       # ItemOperations, a plain cross-domain coordinator
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
owns app state itself; it reads whichever controller(s) it needs via
`context.watch`/`context.read`.

## State management

State used to live in one 2300+ line `ServerProvider` god object. It's now
split into ten focused `ChangeNotifier`s plus one plain coordinator, all
registered in `main()`'s `MultiProvider` in dependency order (later
providers read earlier ones via `context.read` in their `create` callback —
safe since none of these providers are ever recreated for the app's
lifetime; account switching is internal state on `SessionController`, not a
new provider instance):

- [`SessionController`](../../lib/providers/session_controller.dart) — the
  foundation everything else depends on. Owns multi-account state (the
  saved-accounts list, which one is active, `sessionGeneration` — see
  below), auth/login-flow state (`isLoggedIn`, `isRestoringSession`,
  `loginFlowStatus`), the active `NextcloudService` instance, and login lock
  (`loginLockEnabled`/`lockAccountSwitching`/`lockHiddenFiles`/
  `needsUnlock`/`passGate`). Exposes `addAccountClearedListener`/
  `addAccountActivatedListener` (plain `List<VoidCallback>`) so sibling
  controllers — constructed after `SessionController` and unable to hold a
  forward reference to it — can react to login/logout/account-switch
  without a circular dependency.
- [`SettingsController`](../../lib/providers/settings_controller.dart) —
  global UI prefs independent of login state: theme mode/seed color/dynamic
  color, bottom-bar opacity/blur, tap-tab-to-scroll-top, seek bar style, tab
  order/visibility/default (`requestedTab`/`requestTab`/
  `consumeRequestedTab`), swipe actions.
- [`FilesController`](../../lib/providers/files_controller.dart) — the
  Files tab: `items`/`currentFolderPath`/`pathStack`, the in-memory
  `_directoryCache` (see `CachePolicy`), per-account display prefs
  (grid/list, hidden files, storage scope, sort field/order, per-folder
  sort map), and the shared `applyCommonFilters`/`applyFilesDisplayPrefs`
  helpers Photos/Favorites reuse rather than duplicating the same
  filter/sort logic. `refreshData` refreshes **in place** when a listing is
  already on screen (pull-to-refresh, periodic refresh, post-mutation): no
  spinner, the list is swapped once the server answers, and a failed
  refresh keeps the old list. The spinner/error page only appear when there
  is nothing to show (first load, `_navigateTo` clears the outgoing folder
  first, retry after an error). Keep that invariant - blanking the list to
  a spinner made refreshes look like files vanishing and reappearing.
- [`PhotosController`](../../lib/providers/photos_controller.dart) /
  [`FavoritesController`](../../lib/providers/favorites_controller.dart) —
  each depends on `FilesController` for the shared storage-scope toggle and
  display-prefs helpers, but owns its own account-wide item list and
  independent favorites-only/hidden/sort state.
- [`TrashController`](../../lib/providers/trash_controller.dart) /
  [`SharesController`](../../lib/providers/shares_controller.dart) /
  [`RecentController`](../../lib/providers/recent_controller.dart) — one
  per remaining tab, each just `items`/`isLoading`/`errorMessage` plus that
  tab's own fetch/mutate methods. All three (plus Photos/Favorites) share
  one shape: capture `session.sessionGeneration` at fetch entry, set
  loading/clear error, fetch, check the generation before writing the
  result, `notifyListeners()`.
- [`SyncStatusController`](../../lib/providers/sync_status_controller.dart)
  — device-sync settings and live status (`syncStatusFor(item)`,
  `syncHeaderStatus`, conflicts), subscribed to `SyncService`'s status
  stream directly rather than living inside the same object as the item
  lists it decorates. Depends on `FilesController` (declared before it in
  `main()`) because synced files refresh by the Files Cache rule - it owns
  the foreground timer/resume/pull triggers and background scheduling; see
  `server.md`'s "Keeping synced files current automatically".
- [`PickController`](../../lib/providers/pick_controller.dart) — "being
  picked by another app" state (`pickRequest`/`isPicking`/`confirmPick`/
  `itemMatchesPickFilter`) — see `server.md`.
- [`FolderBrowser`](../../lib/providers/folder_browser.dart) — the small
  interface (`pathStack`/`currentFolderPath`/`items`/`isLoading`/
  `errorMessage`/navigation/`reload`) `FilesView` needs from whatever
  supplies its folder. `FilesController` (server) and `OfflineController`
  (local mirror) both implement it, which is what lets the Offline tab be
  `FilesView(offline: true)` - literally the Files tab over the device-sync
  mirror, not a second view. `offline` only swaps the data source, reads
  images from the local file (`localFileFor`) instead of a server preview,
  and turns off what needs the server: selection and bulk actions, swipe
  actions, sync badges, "+" (replaced by "Manage synced folders"), pick
  mode. The two `FilesView`s are keyed in `buildAppTabView` so the
  `IndexedStack` never hands one's State to the other.
- [`OfflineController`](../../lib/providers/offline_controller.dart) — the
  Files tab's folder listing read from local storage instead of the
  server. Owns no display prefs: `items` runs the
  listing through `FilesController.applyFilesDisplayPrefs` (hidden files,
  files/folders filter, per-folder sort keyed by the same remote path,
  minus the cloud/external scope) and `FilesView` reads grid/list from
  `FilesController`, so both tabs share one set of controls
  (`FilesControlsRow`). `FilesController` restores those prefs on the
  account-*ready* event too (memoized `_restoreDisplayPrefs`) so they apply
  offline. Refreshed (see `server.md`'s "Device sync" section) automatically whenever a sync pass
  finishes. Listens for `SessionController.addAccountReadyListener`, not
  `addAccountActivatedListener` - its work is local-only, so it's safe to
  run even on a provisional/offline login (see `ConnectivityController`
  below). Registered with `lazy: false` in `main.dart` (as is
  `SyncStatusController`) - the ready event fires once at startup, before
  any widget reads a lazily-created provider, so a lazy one would register
  its listener too late and never load its persisted state.
- [`ConnectivityController`](../../lib/providers/connectivity_controller.dart)
  — wraps `connectivity_plus`, exposing just `isOffline`. The one thing
  every network-touching controller (indirectly, via `SessionController`)
  and `MainShellView` consult before making a request or deciding what to
  show - see `server.md`'s "Working offline" section.
- [`ItemOperations`](../../lib/providers/item_operations.dart) — not a
  `ChangeNotifier`; a plain, `const`-constructible class holding direct
  references to `SessionController`/`FilesController`/`PhotosController`/
  `FavoritesController`. The one place that knows how a mutation
  (delete/rename/move/copy/favorite-toggle/create-folder) ripples across
  those three tabs' independent item lists — deliberately direct
  references rather than a generic event bus, so a caller can `await` a
  mutation and know every affected list has already been reconciled by the
  time it returns, the same guarantee the old god object gave for free.
  Also home to the file-details sheet's per-item pass-throughs
  (shares/activity/versions/restore) — stateless, so they don't need a
  controller of their own.

`sessionGeneration` (on `SessionController`, read by every other
controller) is incremented on every account switch so an in-flight fetch
from the account just left can recognize it's stale and discard its result
instead of writing into the newly-active account's state — see `server.md`
for the full account-switch/storage story.

New **global** state belongs on `SettingsController` as a private field +
getter + a method that mutates it, calls `notifyListeners()`, and persists
via its own prefs future. New **per-account** state follows the same shape
on whichever controller owns that domain, but persists through
`_persistAccountPref` (namespaces the pref key under
`acct_<activeAccountId>_...` via `AccountStore.accountPrefKey`) and must be
reset/reloaded on `SessionController`'s account-activated listener so it's
correct after a switch. Screen-local state (e.g. a `TextEditingController`,
an expanded/collapsed flag) stays in that view's own `State` class — see
`standards.md` for the split.

There's no separate repository/data layer: views call controller methods
directly, which call `NextcloudService`/`LoginFlowService`/`AccountStore`/
`AppLockService`.

## Navigation / screen flow

`main.dart`'s `NextcloudApp` picks the app's `home` screen from
`SessionController` state, no named routes:

- `session.isRestoringSession` → `_SplashView` (monochrome app icon,
  tinted via `ColorFiltered` to the theme's `onSurface` so it works in both
  light/dark, plus a small spinner, while `flutter_secure_storage`/
  `shared_preferences` are read on startup)
- else `!session.isLoggedIn` → `LoginView` (server-address entry + Login
  Flow v2) — `isLoggedIn` is only ever false here or after the last saved
  account is removed; switching between multiple saved accounts never
  routes through this screen (see `server.md`)
- else `session.needsUnlock` → `LockScreenView` (login lock — see above)
- else `MainShellView`

`MainShellView` is a bottom-nav `IndexedStack` over up to 8 tabs — Files,
Photos, Favorites, Activity, Trash, Shares, Recent, Offline — user-configurable
(order, visibility up to `maxVisibleTabs`, default tab) via
`AppTab`/`SettingsController` and rendered through `buildAppTabView`
(`widgets/app_tab_view_builder.dart`). `maxVisibleTabs` (5) is less than the
total tab count, and `SettingsController._enforceMaxVisibleTabs` already
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
another app" story) that feeds `PickController.pickRequest`; while
`isPicking`, the visible tab list is overridden to just Files and Photos
regardless of the user's own hidden/reordered tab settings, since those
are the only two views that know how to handle a picking-mode tap and the
only two that make sense as external "choose a file" sources. The same
override mechanism restricts the visible tabs to just Offline while
`ConnectivityController.isOffline` - see `server.md`'s "Working offline"
section for the full story, including why session restore itself has to
avoid making a network request in that case. `MoreTabsButton` hides
entirely in both cases (picking, offline) for the same reason - there's
nothing it could usefully open.
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

All eight tabs, plus `ShareUploadView` (the share-to-upload destination
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
`FilesController`'s shared `currentFolderPath`/`pathStack`/`items`, and
owns its own local navigation state instead, fetching through the
stateless `FilesController.fetchFolderListing`/`applyFilesDisplayPrefs`
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
