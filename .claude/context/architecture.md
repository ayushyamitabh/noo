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
  theme/                 # AppTheme (Material 3 ThemeData, pre-rework
                         # screens) + design_tokens.dart (NooColors/NooText/
                         # NooSpace/NooRadii/NooSizes/NooMotion - see
                         # styling.md's "Noo design-system components")
  views/                  # one screen each (FilesView, PhotosView, TrashView,
                           # SharesView, RecentView, ActivityView, SearchView,
                           # AccountView, LoginView, FileViewerScreen,
                           # ShareUploadView, LockScreenView)
  widgets/                 # reusable pieces shared across views
    noo/                    # the Noo design-system component kit - see
                            # styling.md's catalog
    details/                # the file-details bottom sheet and its tabs
    shell/                  # pieces shared by the phone/tablet app shell
    settings/               # Settings' section widgets
    tabs/                   # loading/error/empty slivers + grouping helpers
                            # shared by Recent/Activity/Trash/Shares
    files/                  # pieces split out of FilesView (e.g. the
                            # breadcrumb row)
```

`views/` files are screens routed to directly (a tab, or pushed via
`Navigator`). `widgets/` files are building blocks used by more than one
view (or complex enough to warrant their own file) — nothing in `widgets/`
owns app state itself; it reads whichever controller(s) it needs via
`context.watch`/`context.read`. Most tabs, the app shell, and Settings are
now built from `widgets/noo/` rather than raw Material widgets - see
`styling.md`'s "Noo design-system components" for the token/component
catalog and the current rebuild status.

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
  actions, per-item sync status icons, "+" (replaced by "Manage synced
  folders"), pick mode. The two `FilesView`s are keyed in `buildAppTabView`
  so the
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

**Guardrail - the "empty list on first load" failure class.** This bug has
recurred more than once, always the same shape: a tab's list is empty after
login even though the account is fine, because the controller behind it
never ran its initial fetch. The cause is a race, not a network bug:
`addAccountActivatedListener`/`addAccountReadyListener` fire *once*, at the
moment login is verified/ready, to whichever listeners are registered at
that exact instant - and most per-domain controllers (`FilesController`,
`PhotosController`, `FavoritesController`, `TrashController`,
`SharesController`, `RecentController`) are lazy `ChangeNotifierProvider`s,
only constructed (and so only registering their listener) whenever
something first reads them. If that first read happens to land *after*
the one-shot event already fired - e.g. `ConnectivityController`
misreporting offline for its first couple of seconds after a cold Android
start (see its own doc comment) collapses `main.dart`'s bottom nav to just
the Offline tab, delaying construction of every other tab's controller
until connectivity corrects itself and login has already finished
verifying - that controller's listener registers too late and its initial
fetch simply never happens. `SessionController.addAccountActivatedListener`/
`addAccountReadyListener` now close this at the root: registering either
one calls back **immediately** if the account is already in the state
being subscribed to, not just on the next fresh event, so a late-registering
controller always gets its initial fetch regardless of when its lazy
`Provider` happens to be built. Some views (`FilesView`/`PhotosView`, not
`FavoritesView` - see `FavoritesController`'s own doc comment) additionally
carry a build-time fallback (`_requestedInitialLoad` et al.: reload if
items are empty and not loading, once, after first build) predating this
fix; they're now redundant but harmless, and not worth touching for
cleanup alone. **Guardrail for new code:** any new network-fetching
controller that needs a one-time fetch on login must register through
`addAccountActivatedListener`/`addAccountReadyListener` in its constructor
and rely on their catch-up behavior - don't reach for a per-view
build-time "fetch if empty" fallback as the primary mechanism, since that
pattern is exactly what let this bug keep recurring silently (three
near-duplicate, slightly-diverging implementations, none of them fixing
the actual race).

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

`MainShellView` is an `IndexedStack` over up to 8 tabs — Files, Photos,
Favorites, Activity, Trash, Shares, Recent, Offline — user-configurable
(order, visibility up to `maxVisibleTabs`, default tab) via
`AppTab`/`SettingsController` and rendered through `buildAppTabView`
(`widgets/app_tab_view_builder.dart`). `maxVisibleTabs` (5) is less than the
total tab count, and `SettingsController._enforceMaxVisibleTabs` already
auto-hides overflow on load (fresh install, or - as when Favorites was
added - an existing saved tab order from before a new tab existed), so
adding a tab to the `AppTab` enum needs no extra migration. Only the (up
to) 5 pinned tabs (`settings.visibleTabs`) become bottom-nav/sidebar
destinations; the rest sit in the "More" section of the drawer (mobile) or
sidebar (wide tablet) - see below.
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
avoid making a network request in that case. The drawer/sidebar's "More"
section is empty in both cases (picking, offline) for the same reason -
there's nothing useful in it to switch to - and the mobile drawer doesn't
open at all while picking (`Scaffold.drawer` is null).
`MainShellView` also fires a one-time notification-permission prompt on
its first mount (`_maybeRequestNotificationPermission`, gated by a plain
`shared_preferences` flag so it only ever asks once, not on every
launch): a plain-language dialog (`showNooDialog`, two `NooButton`s)
explaining why Noo wants it (upload/download progress notifications - see
`ShareUploadService.kt`/`DownloadService.kt`) before the OS's own
`permission_handler`-driven `Permission.notification.request()`, since the
bare system prompt gives no context on its own.

`MainShellView` builds its chrome from the Noo nav kit
(`widgets/noo/nav/`) and switches between two layouts on
`NooLayout.isDesktop` (width >= 900dp *and* shortest side >= 600dp, so a
phone in landscape keeps the mobile layout and only tablet-class viewports get
the sidebar):

- **Mobile:** `AppTopBar` (`widgets/app_top_bar.dart`) wraps `NooTopBar`
  for *every* tab (previously only Files had shell-level top chrome, with
  the rest building their own via `SyncedHeaderScaffold`) - iOS gets a
  large title, an inline search field, a `plus` action on Files only (no
  other tab has a create/upload flow), and the account avatar; Android
  gets a compact title row with `search`/avatar actions, relying on an
  extended `NooFab` ("Upload", Files/Photos only) instead of a top-bar
  icon for upload. Rather than one shared instance in `Scaffold.appBar`,
  `MainShellView` builds a separate `AppTopBar` per tab (labelled for that
  tab) and each tab plants its own as the first sliver in its own
  `CustomScrollView` (`topBarSliver` in `widgets/tabs/tab_state_slivers.dart`,
  wrapping it in the framework's `SliverFloatingHeader`) instead of passing
  it to `Scaffold.appBar` - see that file's doc comment for why (Material's
  native "floating" app bar behavior, tied to that tab's own
  `ScrollController`: scrolls away as the list scrolls down and reappears
  the moment the drag reverses, not only once scrolled back to the top).
  `topBar` is null (no top bar rendered) on wide tablet and while picking,
  matching `Scaffold.appBar`'s old `pickRequest == null` guard - see
  `buildAppTabView`'s doc comment. It sits above each tab's own pinned
  in-content header (the sort/filter controls row, or Files/Photos'
  selection bar - see below); the two float/scroll independently - each
  tab also wraps its whole `CustomScrollView` in `SafeArea(top: true,
  bottom: false, ...)` so that pinned header stays clear of the status bar
  once the floating top bar above it fully collapses (see
  `topBarSliver`'s own doc comment for why that reservation can't live
  inside the top bar itself). `BottomNavBar` (`widgets/bottom_nav_bar.dart`)
  adapts the pinned `AppTab`s onto `NooBottomBar`. `AppDrawer`
  (`widgets/app_drawer.dart`) builds a `NooDrawer`: account block, storage
  meter, a "More" list of the hidden tabs, Settings, and an "Edit tabs"
  link (opens Settings - there's no in-page anchor to scroll to its Tabs
  section yet). `SettingsController.navMenuStyle` (Settings → Appearance →
  "Navigation menu") offers an alternative to the hamburger/drawer pair:
  the avatar button opens `showAvatarMenu` (`widgets/avatar_menu.dart`)
  instead, a dropdown holding the same hidden-tabs + Settings content -
  see `styling.md`'s Gotchas for the wiring.
- **Wide tablet:** a `NooSidebar` (account card, pinned tabs, divider,
  remaining tabs, storage meter, Settings) sits beside a `NooToolbar`
  (tab title, search, an "Upload" action on Files/Photos) over the same
  `IndexedStack`, both built inline in `main.dart` rather than as separate
  widgets.

Both layouts share one detail: tapping a hidden ("More") tab calls
`SettingsController.requestTab` - the same one-shot request
`SearchView`/`FavoritesView`/`ShareUploadView` already use to jump the
shell to a tab from outside it - instead of pushing that tab as its own
screen. `MainShellView` then shows it as the active tab (still just an
entry in the `IndexedStack`) with no bottom-bar/sidebar destination
highlighted, since it isn't one of the pinned five, until the user taps a
pinned or another "More" tab. `widgets/shell/shell_common.dart` holds the
pieces both layouts share: account/storage formatting, `openSettings`/
`openSearch`, `showAccountSwitcher` (the saved-accounts list behind the
drawer's chevron and the sidebar's account card - a sheet on mobile, a
dialog on wide tablet), `ShellAvatarButton` and `ShellSearchLauncher`.

All eight tabs used to share
[`SyncedHeaderScaffold`](../../lib/widgets/synced_header_scaffold.dart) - a
`CustomScrollView` with a pull-down "sync status" header (Google
Photos-style) and a classic Material refresh spinner shown during a
pull-triggered sync. Now that every tab is rebuilt on Noo, each renders its
own content directly in a plain `RefreshIndicator` + `CustomScrollView`
instead (`ColoredBox(colors.bg)` background, no shared header widget);
device-sync status shows per-row (`NooFileRow`/`NooFileTableRow`'s
`NooStatusIcon`s) or in the Offline tab's `NooSummaryCard`, not a shared
pinned chip. `SyncedHeaderScaffold` is now unused - the last two screens on
it, `ShareUploadView` (the share-to-upload destination picker, pushed
rather than a tab - see below) and `MoveCopyDestinationPicker`, are
rebuilt too: both are a `Scaffold` with a `NooTopBar`+`NooTopBarBack`
(mobile) / `NooToolbar` (wide tablet) top bar, a noo-styled
[`Breadcrumbs`](../../lib/widgets/breadcrumbs.dart) row + folder list
(`NooFileRow` mobile, `NooFileTableRow` wide tablet - both pickers only ever
browse *folders*, so the old dimmed-but-visible file rows are gone; a
`RefreshIndicator`+`CustomScrollView`) for a body, and a `colors.surface`
bottom bar with a top `line` (no more rounded-top elevated `Material`
sheet) holding the primary CTA. `ShareUploadView` is pushed from outside
`MainShellView` (a cold share-intent launch, or Files' "+" → "Upload
file"), so it builds its own top bar rather than relying on the shell's -
its `actions` are `[ShellAvatarButton()]` only (no `MoreTabsButton`:
there's nowhere useful for it to go mid-upload, since jumping to another
tab would abandon the destination picker); `ShellAvatarButton` is the same
tap-to-Settings/swipe-to-cycle-accounts widget the shell itself uses, and a
straight replacement for the old `ProfileAvatarButton` (now unused
anywhere, since this was its last call site). Its bottom bar holds the
uploading-file-name summary (single line, auto-scrolling via
`MarqueeTitle` if it doesn't fit) above the "Upload to {folder}" CTA.
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
they were, untouched. Unlike `ShareUploadView`, it keeps `MoreTabsButton`
in its top bar: that button pushes a hidden tab as its own stacked screen
rather than jumping the shell there, so it doesn't abandon this picker the
way jumping tabs would. Its bottom bar shows a "Moving/Copying N item(s)"
summary line (replaced by a danger-colored warning when the current folder
is an invalid destination) above a "Move here"/"Copy here" CTA - the
per-item conflict follow-up, if any, is
[`MoveCopyConflictSheet`](../../lib/widgets/move_copy_conflict_sheet.dart).
`SearchView`, `AccountView` (Settings), the file-details sheet
(`DetailsSheet`), and the share sheet (`ShareSheet`) are pushed on top via
`Navigator`/`showNooSheet`/`showNooDialog` rather than being tabs (the two
per-item sheets pick between the mobile sheet and the wide tablet dialog via
`NooLayout.isDesktop`, same as every other overlay in the app;
`showGradualBottomSheet`, the custom drag-to-resize sheet they used before,
has no remaining callers). On mobile, `ShellAvatarButton`
(`widgets/shell/shell_common.dart`,
shown in `AppTopBar`'s trailing actions on every tab, and reused directly by
`ShareUploadView`) opens Settings on tap and cycles between saved accounts
on a vertical swipe. Wide tablet has no avatar in the
toolbar; `NooSidebarAccount`'s account card opens the full switcher instead
(`showAccountSwitcher`, the same one behind the mobile drawer's chevron).

Files and Photos (the two tabs with multi-select) render their selection
bar as a `pinned: true` sliver at the top of their own `CustomScrollView`,
swapped in for the controls row/type-chips row while `_isSelecting` -
selecting reads as replacing that row in place, not adding a strip
beneath it. (An earlier version of this routed the selection bar through
`SyncedHeaderScaffold`'s `selectionBar` param; that's gone along with the
scaffold itself in these two tabs.)
