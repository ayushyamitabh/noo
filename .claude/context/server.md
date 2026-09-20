# Server integration

## Auth: Login Flow v2

The app **never** collects a Nextcloud password directly. It implements
[Login Flow v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2)
via [`LoginFlowService`](../../lib/services/login_flow_service.dart):

1. `LoginFlowService.initiate(serverUrl)` POSTs to
   `{server}/index.php/login/v2`, gets back a browser login URL + a poll
   endpoint/token.
2. The app opens the login URL for the user to authenticate/authorize in
   [`LoginWebViewView`](../../lib/views/login_webview_view.dart), a normal
   screen this app owns (`package:webview_flutter`) - pushed by `LoginView`
   the moment `loginFlowStatus` flips to `awaitingBrowser`, for every login
   (first account or an additional one), not just add-account. This used
   to be split: first login went through a Chrome Custom Tab
   (`url_launcher`, `LaunchMode.inAppBrowserView`) for Chrome's own
   autofill, and only add-account used the embedded WebView, specifically
   to avoid a Custom Tab silently reusing Chrome's existing session for a
   different account. But a Custom Tab has real costs even for the first
   login - no way to close it automatically on success (the user has to
   switch back manually), and it's a separate task outside this app's own
   navigation entirely - so both paths now use the same owned screen.
   `url_launcher` is no longer a dependency. The cost is no
   Chrome-autofill (Android's own system Autofill framework, e.g. a
   password manager, may still work in the WebView; Chrome's own
   saved-password autofill specifically cannot, since that's Chrome-only).
   `LoginWebViewView` also clears cookies (`WebViewCookieManager().
   clearCookies()`) before every load, not just once - Android's WebView
   `CookieManager` is a single store shared/persisted across every WebView
   instance in the app process, not scoped per-controller, so without this
   a second/"Add Account" login silently reuses whichever account's
   Nextcloud session cookie is already there instead of prompting for
   credentials (the same class of bug the Custom-Tab-reuse issue above
   was, just recurring one layer down once everything moved to the owned
   WebView).
3. `SessionController` polls `LoginFlowService.poll(pollEndpoint, token)` every
   2 seconds (`Timer.periodic`, see `_pollTimer`/`_pollTimeoutTimer` in
   `session_controller.dart`) until it gets a 200 with `server`/`loginName`/
   `appPassword`, a non-404 error, or a 10-minute timeout. A single dropped
   connection mid-poll (`http.ClientException`) is swallowed and retried on
   the next tick rather than aborting the whole flow.
4. The returned **app password** (scoped, revocable) is what gets stored and
   used for every subsequent request — real user passwords are never in
   memory or on disk.

`LoginFlowStatus` (`idle` → `initiating` → `awaitingBrowser` → `error`)
drives `LoginView`'s UI; see `LoginFlowService`'s doc comment for the full
flow rationale before changing it.

`startLoginFlow(serverUrl, {addAccount = false})` is reused verbatim for
both the first/only login and "add another account" (pushed from Settings
while already logged into a different account, `LoginView(isAddingAccount:
true)`) — `addAccount` only flags `isAddAccountFlow` for the UI (so the
pushed screen knows to auto-pop on success and cancel the flow on
back-swipe); the persistence path on success is identical either way, see
below.

## Talking to the server

[`NextcloudService`](../../lib/services/nextcloud_service.dart) is the
client for an authenticated session — constructed with `serverUrl` +
`username` + the app password, one instance per login (held as
`SessionController.service`, recreated on every login/switch/logout). It's
effectively stateless per-instance (three final fields, headers rebuilt per
request), which is what makes it trivial to have one saved per account
rather than needing a rewrite for multi-account support.

- **Files**: WebDAV (`PROPFIND`/`MKCOL`/`DELETE`/`MOVE`/`PUT` etc. against
  `/remote.php/dav/files/{username}/...`) via raw `http`/`dio` calls with a
  hand-rolled XML request body and `package:xml` for parsing responses —
  there is no WebDAV client dependency. `_parseDavDate`/`_davPath` in this
  file exist because WebDAV responses use RFC 1123 dates and either bare
  paths or full URLs for `href`; reuse them rather than re-deriving.
- **Everything else** (shares, activity, trash, favorites, quota, user info,
  file versions) goes through Nextcloud's OCS APIs (`/ocs/v2.php/...`), JSON
  in, with the `OCS-APIRequest: true` header required on every OCS call.
  *Toggling* a favorite is OCS; *listing* every favorite (`fetchFavorites`,
  for the Favorites tab) is WebDAV instead - the same `SEARCH` mechanism
  `fetchAllMedia`/`fetchRecentFiles` use, filtered by `oc:favorite` instead
  of mimetype/date. Favorites is a real tab
  (`views/favorites_view.dart`/`FavoritesController.items`/
  `fetchAll`/`_allFavorites`), not a filter toggle scoped to
  whatever folder the Files tab happens to be browsing (that's what it
  used to be - see the note below on why that didn't work). It shares
  Files' own sort/hidden/storage-scope/grid-list display prefs
  (`applyFilesDisplayPrefs`, also used by the Move/Copy destination
  picker) rather than a separate parallel settings dimension. Tapping a
  favorited folder switches to the Files tab, navigated there
  (`FilesController.navigateToAbsoluteFolder` +
  `SettingsController.requestTab`); a favorited file opens directly from
  the Favorites tab itself. `ItemOperations.deleteItem`/`renameItem`/move/
  copy all re-sync `FavoritesController._allFavorites` afterward via
  `FavoritesController.syncIfLoaded` (only once Favorites has actually been
  opened this session, tracked by `_everFetched`, so those actions don't
  pay for an extra request on every edit for an account that's never
  visited the tab) since none of them know how to patch `_allFavorites` in
  place the way `ItemOperations.toggleItemFavorite` does (added/removed/
  updated by id, right inline via `FavoritesController.applyFavoriteToggle`).
  **Note**: this used to be a "favorites-only" filter toggle on the Files
  tab's controls row instead of its own tab, filtering the currently
  browsed folder's `_items`. That had two real bugs in sequence: first,
  the filter dropped every non-favorited item *including folders*, so a
  non-favorited folder (containing a favorited item nested inside)
  vanished from the listing entirely, with no way to navigate into it;
  fixing that by exempting folders from the filter was itself wrong,
  because the actual intent was for favorites-only to show every
  favorited item *account-wide*, not just direct children of whatever
  folder was open - a strict filter over the wrong scope. Converting it to
  a real tab, backed by an account-wide fetch, was the actual fix; keep
  favorites account-wide rather than reintroducing a current-folder-scoped
  filter.
- Auth header is HTTP Basic (`username:appPassword`, base64), built in
  `_headers`/exposed as `authHeaders` for widgets that need to hit URLs
  directly (e.g. `Image.network(url, headers: service.authHeaders)` for
  thumbnails/previews).
- `NextcloudService.downloadToFile` (`Dio`, progress callbacks) is still
  used for small in-app-only downloads: text/PDF previews (`fetchBytes` via
  `package:http`) and "open externally" (`FileViewerScreen._downloadToTemp`
  streams to the app's own cache dir so `open_file` can hand it to another
  app). Explicitly saving a file **to the device** - the "Download" action
  in Files/Photos' selection toolbar and the media viewer's download button
  - instead hands off to `DownloadService.kt`, an Android foreground
  service, the same way "Share to Noo" hands its upload off to
  `ShareUploadService.kt` (see that section below) rather than downloading
  in Dart and prompting `file_saver` per file: a real Service survives the
  app being closed mid-download, with one cancellable notification for the
  whole batch. `DownloadService.kt` re-implements a plain WebDAV GET in
  Kotlin for the same reason `ShareUploadService.kt`'s PUT does - keep
  `NextcloudService.downloadToFile` in sync manually if download semantics
  change - and writes straight into the device's public Downloads
  collection via `MediaStore.Downloads` (API 29+; a background Service
  can't prompt `file_saver`'s SAF picker the way the Flutter/Activity side
  can, so this is the direct equivalent) with a legacy
  `Environment.DIRECTORY_DOWNLOADS` file-write fallback pre-Android-10.
  Folders are filtered out client-side before handing off (no recursive/
  zip download support); `DetailsVersionsTab`'s version-restore download
  and `ShareSheet`'s "Share file directly" (native OS share, not saved to
  Downloads) keep using `downloadToFile` directly instead, since both need
  the bytes in-app rather than saved to Downloads.
- **Move/Copy** (`moveItem`/`copyItem(itemPath, destFolderPath, {overwrite,
  newName})`) share one private `_moveOrCopy` helper with `renameItem`
  (itself just a same-folder MOVE) - WebDAV `MOVE`/`COPY` are the same
  request shape, just a different verb, and both are recursive by default
  for a folder ("collection"), so no extra `Depth` header is needed. They
  return the raw HTTP status rather than a bool: `412 Precondition Failed`
  is WebDAV's standard signal for "something's already there" when
  `Overwrite: F`, which is exactly the conflict `ItemOperations.moveItems`/
  `copyItems` need to detect without a separate existence-check request
  per item. `ItemOperations` attempts every item in the batch first,
  collects conflicts into `MoveCopyResult.conflicts`
  (`models/move_copy_result.dart`), and only then shows one summary
  (`MoveCopyConflictSheet`) instead of prompting per conflict as they're
  hit; resolving picks overwrite/keep-both (auto-renamed via
  `_nextAvailableName` against a fresh listing of the destination, fetched
  once up front, not per item)/skip per item via `resolveConflicts`. The
  destination-picker screen behind this
  (`views/move_copy_destination_picker.dart`) is covered in
  `architecture.md`, including why it can't reuse the Files tab's shared
  navigation state the way `ShareUploadView` does.
- **Uploads**: there's no more in-app-only upload path - `NextcloudService`'s
  own `uploadFileFromPath` was removed once the Files tab's "+" → "Upload
  File" was unified with the share-to-upload flow (below). Every upload,
  however it's triggered, now goes through `ShareUploadView` (caller-chosen
  destination via `FilesController.navigateToAbsoluteFolder`, then
  `UploadService`/`ShareUploadService.kt`).
- **Receiving a shared file from another app**: hand-rolled in
  `MainActivity.kt` (Android `ACTION_SEND`/`ACTION_SEND_MULTIPLE`,
  `android:launchMode` `singleTask` in the manifest so a second share while
  running hits `onNewIntent` instead of spawning a new instance) plus
  [`ShareIntentService`](../../lib/services/share_intent_service.dart) on
  the Dart side - not the `receive_sharing_intent` plugin, which this used
  to be. That plugin resolves a shared `content://` Uri by synchronously
  copying the *entire* file into the cache dir on the main thread during
  activity startup; for a large file that blocks long enough that Android
  kills the newly-launched activity for failing to draw a first frame,
  dropping the user straight back to the home screen with no error and no
  Dart code ever running. `MainActivity.kt`'s doc comment has the full
  story. The fix: `getInitialShare`/`onNewShare` only ever query cheap Uri
  metadata (name/size/mime, not content) so `ShareUploadView`'s destination
  picker - which mirrors the Files tab's own controls/filters/listing,
  reusing the same `FilesController` fields and `widgets/item_icon.dart` -
  always appears instantly regardless of file size.
- **Uploading a shared file**: once the user picks a destination in
  `ShareUploadView`, [`UploadService`](../../lib/services/upload_service.dart)
  hands the whole batch off to `ShareUploadService.kt`, an Android
  foreground service, rather than uploading from Dart in that screen. This
  is deliberate, not just an implementation detail: the point is that
  closing the app right after confirming a destination doesn't interrupt
  the upload, the same guarantee a real file-manager app's upload
  notification gives you - a plain Dart `Future` (even one kept alive by a
  singleton service class) stops running once the Flutter engine/Activity
  are gone, only an actual Android `Service` survives that. The service
  re-implements the WebDAV PUT itself in Kotlin (`HttpURLConnection`, no
  new HTTP dependency) since it can't reach the Dart-side `NextcloudService`/
  Dio from a separate process lifecycle - `UploadService.startUpload` passes
  everything the Kotlin side needs (the pre-built `Authorization` header
  from `NextcloudService.authHeaders`, not the raw password) as Intent
  extras, a one-way handoff with no channel back to Dart afterward. Keep
  the two upload implementations in sync manually if upload semantics
  change. Progress/cancellation is entirely notification-driven (one
  ongoing, updatable notification for the whole batch; its Cancel action
  re-delivers an Intent to the same running service instance, which an
  `AtomicBoolean` the copy/upload loops poll) - there's no plumbing back to
  the Dart UI, by design, since the app may not even be running.

## Being picked by other apps (photo/file picker)

Noo can also be launched *by* another app as a `GET_CONTENT` picker (e.g.
Google Drive/Instagram's "choose a file" flow), the reverse direction of
"Share to Noo" above - hand-rolled the same way, not a plugin.

- `MainActivity.kt` matches `ACTION_GET_CONTENT` (`OPENABLE`, any
  mimeType - a single `*/*` filter, since Android matches it against
  whatever the caller actually requested) alongside its existing
  `ACTION_SEND`/`SEND_MULTIPLE` filters, and exposes the caller's requested
  mimeType/multi-select flag/app label via the
  `dev.ayushya.noo/pick_intent` method+event channel pair
  ([`PickIntentService`](../../lib/services/pick_intent_service.dart)/
  [`PickRequest`](../../lib/models/pick_request.dart)) - same
  cold-start-vs-already-running split as the share-intent channels.
- `PickController.pickRequest`/`isPicking` drive picking mode app-wide once
  `MainShellView` learns about a request at startup or via
  `onNewPickRequest`. While picking, `MainShellView` restricts the visible
  bottom-nav tabs to just Files and Photos (see `architecture.md`) -
  `FilesView`/`PhotosView` route taps through
  `itemMatchesPickFilter`/`confirmPick` instead of their normal
  open/select behavior (folders still navigate; a mime-mismatched file is
  rejected with a snackbar; matching files toggle-select or immediately
  confirm depending on `PickRequest.allowMultiple`).
- `PickController.confirmPick` downloads the selected item(s) to a
  `picker/` scratch subfolder in the app's cache dir (`downloadToFile`,
  same as any other download) - each item into its own `picker/<item.id>/`
  subfolder, keeping the on-disk filename as plain `item.name` rather than
  prefixing it with the id to dodge collisions between same-named items;
  the caller reads that on-disk name back as the display name, so
  prefixing it there was a real bug (Drive showing e.g. `163332_photo.jpg`
  instead of `photo.jpg`) - then hands the local paths to
  `PickIntentService.finishPick`, which calls back into
  `MainActivity.kt.finishPick`: it wraps each file in a `content://` Uri
  via this app's own `FileProvider` (`${applicationId}.picker.fileprovider`,
  scoped to just that cache subfolder - see `android/app/src/main/res/xml/
  file_paths.xml`) and returns it to the caller via `setResult`. Single
  file uses `setDataAndType` (never `.data =`/`.type =` as two separate
  calls - each one silently nulls out the other field on a plain
  `Intent`); multiple files use `ClipData`. `cancelPick` mirrors this for
  backing out (system back while picking, or a picked-item mismatch) with
  `RESULT_CANCELED` instead.

## Device sync

Mirrors selected folders to app-private local storage
(`getExternalFilesDir(null)/sync/<accountId>/...` - wiped on uninstall, no
extra storage permission needed) and keeps them updated in the background,
even with the app fully closed. Same rationale as the upload/download
services for going native instead of a Dart background-task plugin (see
above): a periodic job has to run without the Flutter engine loaded, and a
notification action has to resolve without launching the UI. Rather than
add `workmanager` (whose Dart `callbackDispatcher` spins up a second,
minimal Flutter engine that has to re-register every plugin it touches),
the whole engine is plain Kotlin using Android's WorkManager directly.

- [`SyncEngine.kt`](../../android/app/src/main/kotlin/dev/ayushya/noo/SyncEngine.kt)
  holds the shared primitives, reused by both workers below: a Depth-1 (or
  Depth-0, for refreshing one item) PROPFIND (`propfindChildren`/
  `propfindSelf`) requesting `d:getetag` alongside the usual props - unlike
  every PROPFIND in `nextcloud_service.dart`, which never requests it
  (`etag` is a dead field on `NextcloudItem` today); plain
  `HttpURLConnection` GET/PUT (`downloadFile`/`uploadFile`, same style as
  `DownloadService.kt`/`ShareUploadService.kt`); and `diffFolder`, which
  compares one folder's freshly-walked manifest against the persisted
  per-account sync-state map (native `SharedPreferences`, JSON keyed by
  `oc:fileid` - stable across renames/moves, unlike `path`) to decide, per
  file: download (new, or server `etag` changed), upload (local file's
  mtime/size changed and the server didn't), delete locally (missing
  server-side, unchanged locally), respect a local deletion (file's gone
  and the server didn't change either - don't recreate it), or flag a
  **conflict** (both changed since the last recorded state).
- [`SyncWorker.kt`](../../android/app/src/main/kotlin/dev/ayushya/noo/SyncWorker.kt)
  (`CoroutineWorker`) is both the periodic job and the one-off "Sync now":
  for each configured path, `propfindSelf`s it first to check whether it's
  a file or a folder - a folder gets the full recursive
  `walkRemoteTree`, a file is diffed directly as a one-item list (nothing
  else about `diffFolder`/download/upload/delete cares whether its entries
  came from a walk or a single lookup, so single-file sync needed no engine
  changes, just this one branch) - applies `diffFolder`'s decisions, then
  posts a summary notification (files updated/uploaded/removed) and, for
  any conflicts, one notification per file with two actions.
- **Live status reaches Dart via a push channel, not polling** -
  [`SyncStatusBus.kt`](../../android/app/src/main/kotlin/dev/ayushya/noo/SyncStatusBus.kt)
  is a plain in-process pub/sub (no IPC needed - the workers and
  `MainActivity` share one process) that `SyncWorker`/`ConflictResolveWorker`
  publish into (syncing started/stopped, which `fileId`s are mid-transfer
  right now, new/resolved conflicts) and `MainActivity.kt`'s
  `dev.ayushya.noo/sync_service/status` `EventChannel` forwards to Dart,
  same pattern as the share/pick-intent channels. It deliberately does
  *not* track "which files are already synced" itself - that's read fresh
  from `SyncEngine`'s durable per-account state map
  (`SyncEngine.loadState(accountId).keys`) each time a snapshot is built,
  so there's one source of truth for "synced" instead of two that could
  drift. `SyncService.getStatus()` (one-shot, seeds `SyncStatusController`
  right after login/account-switch) and `SyncService.statusStream` (live)
  both return the same snapshot shape. `SyncStatusController.syncHeaderStatus`
  (off/syncing/done/alert - drives `SyncedHeaderScaffold`'s persistent
  chip/panel, replacing what used to be the WebDAV-refresh-loading
  indicator there) and `syncStatusFor(item)` (none/syncing/synced/conflict
  - drives the small corner badge on Files' tiles, `SyncStatusBadge`) are
  both computed from this state, not fetched per-item.
- **In-app conflict resolution reuses the exact same enqueue path as the
  notification actions** - `ConflictResolveWorker.enqueue(...)` is a
  shared companion function; `SyncConflictReceiver` (the notification
  action) and `MainActivity.kt`'s `resolveConflict` MethodChannel method
  (the sync header's "Keep local"/"Use server" buttons,
  `SyncStatusController.resolveSyncConflict`) both just call it, so there's
  one resolution code path regardless of which surface triggered it.
- **Conflicts are never auto-resolved.** The notification's "Keep local"/
  "Use server" actions are `PendingIntent.getBroadcast`s (same shape as the
  Cancel action on upload/download notifications, just broadcast instead of
  service-targeted) to
  [`SyncConflictReceiver`](../../android/app/src/main/kotlin/dev/ayushya/noo/SyncConflictReceiver.kt)
  - a manifest-registered `BroadcastReceiver` (works even with the app
  process dead) that can't itself block on network, so it just dismisses
  the notification and enqueues a one-shot
  [`ConflictResolveWorker`](../../android/app/src/main/kotlin/dev/ayushya/noo/ConflictResolveWorker.kt)
  to actually push the local copy up or pull the server copy down and
  refresh that file's recorded state.
- `MainActivity.kt`'s `dev.ayushya.noo/sync_service` channel
  (`reschedule`/`cancel`/`syncNow`) is the only bridge from Dart: a periodic
  `WorkRequest`'s input `Data` and `Constraints` are fixed at enqueue time,
  so changing the synced-folder list, the active account, or the Wi-Fi-only
  setting means cancelling and re-enqueueing, not updating in place.
  [`SyncService`](../../lib/services/sync_service.dart) (Dart) wraps this -
  `SyncStatusController` calls `SyncService.reschedule` after every
  successful login/account switch and every synced-folder/`syncOnCellular`
  change, and `SyncService.cancel` on logout/last-account-removed. The
  network constraint is `NetworkType.UNMETERED` by default
  (`!syncOnCellular`, Wi-Fi only) or `NetworkType.CONNECTED` if the user's
  opted into cellular sync.
- Synced-path list (`SyncStatusController.syncedPaths` - files or folders, not
  just folders despite the name of the underlying pref/native `Data` key,
  which stayed `ui_synced_folders`/`folders` to avoid a storage-key
  migration for a rename) follows the standard per-account-pref pattern
  (JSON-encoded string list, in `AccountStore.perAccountPrefKeys`); so does
  `syncEverything` (`ui_sync_everything`, per account) - when on,
  `SyncService` sends `['/']` as the path list instead of `syncedPaths`,
  mirroring the whole account rather than requiring per-item opt-in.
  `syncOnCellular` is a plain global pref. All three are managed from
  Settings → Device Sync (a "Sync everything" switch, the path list with
  remove buttons - hidden while "Sync everything" is on - the cellular
  toggle, and a manual "Sync now"); individual files or folders are
  additionally toggled from Files' selection toolbar ("Sync to device",
  single-selection, either item type).
- **`android/app/proguard-rules.pro` exists specifically for this feature,
  and keeps `androidx.work.**` wholesale rather than naming individual
  classes.** Flutter's own Gradle plugin auto-enables R8 minification for
  release builds (`FlutterPlugin.kt` sets `isMinifyEnabled = true`
  unconditionally for the `release` build type, and auto-wires this exact
  file if it exists - nothing in this project's own `build.gradle.kts`
  opts into it), which broke device sync on real-device testing **twice**
  in a row: first `WorkDatabase` (WorkManager locates its bundled Room
  database by reflecting off the abstract database class's own,
  possibly-renamed, name), then - after narrowly keeping just that class -
  `OverwritingInputMerger` (WorkManager's default input merger, also
  reflection-instantiated) broke the exact same way and silently ate every
  `enqueueUniqueWork` call, including "Sync now", with zero indication
  beyond a `WM-InputMerger` `NoSuchMethodException` in logcat - no crash,
  no Dart-visible error, just a folder that stayed empty. R8's member-level
  shrinking strips whatever a class's *reflection-only* callers don't
  reference directly, even when the class itself survives a plain `-keep
  class` with no wildcard, and WorkManager reflects into more of its own
  internals than any one test pass is likely to exercise - hence the
  wholesale keep instead of chasing individual classes one crash at a
  time. If adding another native background component reached only via
  reflection (not a manifest-declared component, which AGP already keeps
  automatically), don't assume default AndroidX consumer rules cover it -
  verify on an actual release build, not just `flutter analyze`/a debug
  build, since minification only applies to release.
- **Files land under `Android/data/<package>/files/sync/...`
  (`getExternalFilesDir`), which no third-party file manager can browse
  without root** - Android's scoped storage sandboxes that whole directory
  tree from other apps by design, same as any app-private storage. This
  surprised real-device testing (a file manager app logged "Can't read
  directory ... trying su" and came up empty even though the sync had
  actually worked) - it's expected, not a bug. Confirm synced files
  landed via `adb shell run-as`/a rooted shell, not a regular file
  manager UI.
- **Already-synced files skip the network** in two places:
  `SyncStatusController.localSyncedFilePath(item)` is a pure function of the
  remote path (mirrors `SyncEngine.kt`'s `syncRoot` layout exactly, so Dart
  never needs to read the native sync-state `SharedPreferences`) that
  returns the local mirror path if it exists on disk. `ShareSheet`'s "Share
  file directly" and `FilesView._downloadSelected` (only when *every*
  selected file is already synced - a mixed selection still goes through
  the normal `DownloadService` batch) both check it first.

## Multi-account storage & session persistence

[`AccountStore`](../../lib/services/account_store.dart) owns everything
account-identity-related; `SessionController` owns everything about which
account is *currently* live (see `architecture.md`).

- **Per-account secrets**: one `flutter_secure_storage` key per account,
  `nc_app_password_<accountId>` — never `shared_preferences`. `accountId` is
  deterministic (`SavedAccount.makeId(serverUrl, username)`, a slug of both),
  so re-adding the same account refreshes its password instead of creating a
  duplicate.
- **Account identity list** (non-secret: id/serverUrl/username) and
  **which one is active** live in `shared_preferences` as `accounts_list`
  (JSON array) and `active_account_id`.
- **Global UI prefs** (theme, dynamic color, AMOLED, bottom-bar
  opacity/blur, tap-to-scroll-top, seek bar style, tab order/hidden/default,
  swipe actions) stay flat, un-namespaced `shared_preferences` keys — same
  as before multi-account, untouched by switching.
- **Per-account browsing prefs** (grid/list view, favorites-only ×2,
  storage scope, show-hidden ×2, Photos sort field/ascending, Files'
  per-folder sort map, cache policy/interval — the full list is
  `AccountStore.perAccountPrefKeys`) are namespaced `acct_<accountId>_<key>`
  and owned by whichever controller that domain belongs to (e.g.
  `FilesController` for grid/list/storage-scope/sort,
  `PhotosController` for Photos' own sort/filter). Each reloads its own
  slice in its `_onAccountActivated` listener, registered via
  `SessionController.addAccountActivatedListener` in its constructor -
  there's no longer one central method that reloads every domain's prefs at
  once; `SessionController` just fires the notification, and every sibling
  controller reacts independently.
- **Legacy migration**: `AccountStore.migrateLegacyIfNeeded` runs once ever
  (guarded by the `account_migration_v1_done` flag), turning a pre-multi-
  account install's 3 flat secure-storage keys + flat browsing prefs into
  the first saved (and active) account, so upgrading users are never logged
  out. Never assume the legacy keys are gone — always check the migration
  flag rather than the keys' absence.
- On startup, `SessionController`'s constructor awaits the migration, loads
  the account list + active id, then `_restoreSession()` looks up the
  active account's password and calls `_applyCredentialsForAccount`
  (generation-guarded, account-aware) to rebuild the session without
  re-hitting the login flow - firing `_notifyAccountActivated()` on
  success, which is what triggers every sibling controller's own initial
  fetch.
- **Switching accounts** (`switchAccount`/`cycleToNextAccount`/
  `cycleToPreviousAccount`/`removeAccount`'s fallback, plus landing on a
  freshly-added account) all funnel through the single `_activateAccount`
  engine: bump `sessionGeneration`, cancel any pending login flow, call
  `_notifyAccountCleared()` (every sibling controller's registered
  `addAccountClearedListener` callback resets that controller's own state)
  *without* ever setting `isLoggedIn` false (that's the detail that keeps
  `main.dart`'s root routing from bouncing through `LoginView` mid-switch),
  then verify
  its credentials and refetch everything. This is a full teardown-and-reload
  every time — there is deliberately no simultaneous multi-account state or
  background sync; only one account's content is ever live.
- **`logout()` vs `removeAccount()`** are deliberately different actions,
  both funneling into a shared `_deactivateSession()` helper for the
  teardown/pointer-clearing part:
  - `logout()` ends the active session but keeps the account itself fully
    intact (password, prefs, its entry in `accounts` all untouched) —
    always lands on `LoginView` even if other accounts are saved (it does
    *not* fall back to one of them the way `removeAccount` does). This
    exists so `LoginView` can offer a "Continue as ..." one-tap resume list
    (`_SavedAccountsSection` in `login_view.dart`) with no Login Flow v2
    needed - logging out must never be mistaken for forgetting an account.
  - `removeAccount(id)` deletes everything for that account (secure-storage
    password, namespaced prefs, its `accounts` entry) and, only if it was
    the active one, falls back to another saved account or - if none
    remain - calls the same `_deactivateSession()`. This is the only path
    (besides `logout()`) that can set `isLoggedIn` false, and the only one
    that's actually destructive/irreversible - UI call sites (`AccountView`)
    gate it behind a confirmation dialog; `logout()` doesn't need one.
  - Any UI code that calls either and might have ended the session should
    check `!session.isLoggedIn` afterward and `Navigator.popUntil((r) =>
    r.isFirst)` if so — otherwise a screen pushed on top (Settings) is left
    stranded over a root route that's silently swapped to `LoginView`
    underneath it. Don't pop unconditionally — removing a *non-active*
    account, or one that fell back to another, keeps the user logged in and
    Settings should just stay open.

## App lock (login lock)

An orthogonal, app-wide security layer on top of the Nextcloud
login/session above — not account credentials, just a gate on *using* the
app. [`AppLockService`](../../lib/services/app_lock_service.dart) wraps
`local_auth`; this app never implements its own PIN entry/storage/hashing —
`authenticate()` always delegates to whatever the OS already has configured
(biometric, or device PIN/pattern/password as fallback, via
`biometricOnly: false`). Never build a custom in-app PIN screen for this —
extend `AppLockService`/the `SessionController` gates described in
`architecture.md` instead.

**Android native requirements** (both already done, keep them if you touch
these files): `MainActivity.kt` must extend `FlutterFragmentActivity`, not
the default `FlutterActivity` — `local_auth`'s Android implementation hosts
its prompt via a Fragment and silently fails to build/crashes without it.
`AndroidManifest.xml` needs `<uses-permission
android:name="android.permission.USE_BIOMETRIC"/>` (also declared by the
plugin's own manifest via merge, but kept explicit here too).
`android/app/build.gradle.kts` floors `minSdk` at 24 (`local_auth_android`'s
own requirement) via `maxOf(24, flutter.minSdkVersion)` rather than trusting
Flutter's own default to already be high enough.

`isRestoringSession` still gates the splash screen until the above resolves
— see `standards.md` for why widget tests must mock both storage channels
rather than relying on this async path throwing naturally.
