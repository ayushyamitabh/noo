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
  `creationdate` specifically needs `_parseDavCreationDate`, not
  `_parseDavDate` directly - Nextcloud has no real per-file creation-time
  tracking for most setups, so that property routinely comes back as a
  placeholder Unix-epoch date rather than being omitted, which
  `_parseDavDate` alone parses "successfully" into a real (if bogus)
  January 1970 `DateTime`. `_parseDavCreationDate` treats that placeholder
  as absent instead, so `NextcloudItem.dateCreated` falls back to
  `lastModified` (its constructor's default) the same as it would for a
  missing/unparseable value.
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
  extras, a one-way handoff for the start of the upload - the Kotlin side
  never asks Dart anything mid-upload, since the app may not even be
  running by then. Keep the two upload implementations in sync manually if
  upload semantics change. Progress/cancellation is entirely notification-
  driven (one ongoing, updatable notification for the whole batch; its
  Cancel action re-delivers an Intent to the same running service instance,
  which an `AtomicBoolean` the copy/upload loops poll) - the notification is
  the only UI a closed app gets.
  There is one thing that *does* come back, when the app is still running:
  once a batch finishes with at least one success, `ShareUploadService.kt`
  publishes into `UploadEventBus` (an in-process pub/sub, same shape as
  `SyncStatusBus` below), which `MainActivity.kt` forwards to Dart over the
  `dev.ayushya.noo/upload_service/status` `EventChannel` -
  `UploadService.completions`. `FilesController` subscribes in its own
  constructor and calls `refreshData()` when the event's folder matches
  `currentFolderPath`, so a file uploaded into the folder currently on
  screen shows up without a manual pull-to-refresh. Follows
  `SyncService.statusStream`'s "one shared `static final` stream" rule (see
  its own doc comment) - a second `receiveBroadcastStream()` subscriber
  would silently steal the single native-side listener from the first.

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
  server-side, unchanged locally), re-download a file whose local copy is
  missing even though state says it was mirrored (stale state from an
  earlier sync of the path - treating that as "user deleted it" used to
  skip the download and report phantom removals), or flag a
  **conflict** (both changed since the last recorded state). The
  "removed" count in the summary notification only counts local files that
  actually existed and were deleted.
- [`SyncWorker.kt`](../../android/app/src/main/kotlin/dev/ayushya/noo/SyncWorker.kt)
  (`CoroutineWorker`) is both the periodic job and the one-off "Sync now":
  for each configured path, `propfindSelf`s it first to check whether it's
  a file or a folder - a folder gets the full recursive
  `walkRemoteTree`, a file is diffed directly as a one-item list (nothing
  else about `diffFolder`/download/upload/delete cares whether its entries
  came from a walk or a single lookup, so single-file sync needed no engine
  changes, just this one branch) - applies `diffFolder`'s decisions, then
  posts a summary notification (files updated/uploaded/removed) and, for
  any conflicts, one notification per file with two actions. A progress
  notification (`notifyProgress`) is shown lazily - only once the first
  actual download/upload starts, not unconditionally at the top of every
  run, so a periodic pass that finds nothing to transfer never flashes a
  notification at all. It shares the summary's notification ID
  (`SUMMARY_NOTIFICATION_ID`) on purpose: the final `notifySummary` call
  naturally replaces the ongoing progress notification in place once the
  run finishes (no flicker of two separate notifications), and if nothing
  ended up changing, `doWork` explicitly cancels that ID since there's no
  summary to replace it with.
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
  drift - which is also why `SyncWorker.doWork()` saves state *before*
  its final `SyncStatusBus.setSyncing(accountId, false)` publish, not
  after: that publish is what tells Dart's live listener to recompute
  `syncedFileIds`, so publishing first would hand back a snapshot still
  missing every file the run just downloaded, with no further event ever
  arriving afterward to correct it - newly-synced files would sit with no
  badge until the app restarted and force-refreshed via `getStatus()`.
  `SyncService.getStatus(accountId)` (one-shot, seeds `SyncStatusController`
  right after login/account-switch - the account id is passed explicitly
  because `SyncStatusBus` only learns an account once a sync pass has run
  in this process, so on a fresh app start it'd report empty
  `syncedFileIds`; `SyncStatusController._applySnapshot` likewise ignores
  the bus's initial null-account emission so it can't wipe that seed) and `SyncService.statusStream` (live)
  both return the same snapshot shape. `SyncStatusController.syncHeaderStatus`
  (off/syncing/done/alert - drives `SyncedHeaderScaffold`'s persistent
  chip/panel, replacing what used to be the WebDAV-refresh-loading
  indicator there) and `syncStatusFor(item)` (none/syncing/synced/conflict
  - drives the small corner badge on Files' tiles, `SyncStatusBadge`) are
  both computed from this state, not fetched per-item. Folders never get
  their own entry in the native state map (`diffFolder` only ever tracks
  individual files - `if (entry.isFolder) continue`), so `syncStatusFor`
  derives a folder's badge differently than a file's: `synced` once the
  folder's own path (or an ancestor of it) is in sync scope
  (`_isPathInSyncScope`, shared with `localSyncedFilePath`), `syncing`
  while any sync pass is running, `conflict` if a pending conflict's
  `remotePath` falls under it - not from `syncedFileIds`, which only ever
  contains individual files.
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
- **Keeping synced files current automatically - no "Sync now" needed.**
  Synced paths follow the Files Cache rule (Settings, right under Device
  Sync; default *Refresh periodically, 15 min*), driven by
  `SyncStatusController` (see its doc comment): *periodically* = a
  WorkManager `PeriodicWorkRequest` at `max(interval, 15)` min (Android's
  floor) via `reschedule(intervalMinutes:)`, plus an in-app `Timer` at the
  exact interval and a pass on app resume if one is due; *never cache* = no
  background job, a pass on each app open/resume; *manual* = only
  pull-to-refresh (`SyncedHeaderScaffold` calls `syncOnPull`, on any tab) and
  "Sync now". **There's no server push:** Nextcloud's push options
  (`notify_push` needs a server app plus a persistent WebSocket, which
  Android kills in the background without a foreground service; Nextcloud's
  FCM/UnifiedPush proxy needs a registered app identity) aren't viable for
  a self-hosted-server client, so it polls - and polling is made cheap by the
  **root-etag shortcut**: Nextcloud propagates any descendant change up
  through every ancestor folder's `getetag`, so each run first does one
  Depth-0 PROPFIND per synced root and skips the recursive walk if the etag
  matches the stored `SyncEngine.RootMarker` *and* every local file still
  matches its recorded size/mtime (`localMatchesState` - nothing to upload or
  re-download). A root is only marked after a fully clean pass (no failed
  transfer, no conflict), a full walk is forced at least every 6 h
  (`FULL_WALK_MAX_AGE_MS`; etag propagation is unreliable on external
  storage), and "Sync now" (`KEY_FORCE`) always walks. Automatic/pull passes
  are `force: false`: silent (progress notification only once a transfer
  starts), `ExistingWorkPolicy.KEEP` (never cancel a run in progress), and
  automatic ones also carry the Wi-Fi-only constraint. **Safety:** PROPFIND
  failures (network error, 5xx) throw `RemoteUnavailableException` and the
  path is skipped that run - previously they returned an empty listing,
  which made every synced file look deleted server-side and the diff deleted
  the local copies (a real risk once passes run every few minutes). Only a
  clean 404 means "gone".
- `MainActivity.kt`'s `dev.ayushya.noo/sync_service` channel
  (`reschedule`/`cancel`/`syncNow`/`removeLocalSync`) is the only bridge
  from Dart: a periodic `WorkRequest`'s input `Data` and `Constraints` are
  fixed at enqueue time, so changing the synced-folder list, the active
  account, or the Wi-Fi-only setting means cancelling and re-enqueueing,
  not updating in place. [`SyncService`](../../lib/services/sync_service.dart)
  (Dart) wraps this - `SyncStatusController` calls `SyncService.reschedule`
  after every successful login/account switch and every synced-folder/
  cache-rule/`syncOnCellular` change. `reschedule` covers **every saved
  account**, not just the active one: each account with sync enabled gets its
  own periodic job (`SyncWorker.periodicNameFor(accountId)`) carrying that
  account's own credentials (read from `AccountStore`), paths and interval -
  the active account's from live `SyncStatusController` state, the others'
  from their persisted per-account prefs (`_SyncConfig.fromPrefs`). Logging
  out stops that account's background sync: `SessionController.logout`
  records it in `AccountStore`'s signed-out set (so a later `reschedule` for
  another account doesn't resurrect its job) and cancels it via
  `SyncService.cancelAccount`; activating the account again clears the flag.
  Removing an account cancels its job too. One-off runs are per-account
  (`oneOffNameFor`).
- **Folders, not just files, are mirrored.** After applying a path's diff,
  `SyncWorker` calls `SyncEngine.mirrorFolders` (a local directory for every
  remote folder, so an empty folder created on the web appears on device) and
  `pruneRemovedFolders` (removes local directories the server no longer has,
  but only *empty* ones - the diff has already deleted the files that were in
  them - and never the sync root). Root-etag markers carry a version
  (`ROOTS_VERSION`) so bumping it forces one full walk after a change like this.
  A configured path the server 404s (deleted on the web) is recorded via
  `setRootMissing`; the snapshot's `missingRoots` lets
  `SyncStatusController._applySnapshot` drop it from the synced list.
- **Notifications.** Sync notifications are silent (channel `device_sync_v2`,
  `IMPORTANCE_LOW` + `setSilent`), with ids and titles scoped per account
  (`summaryNotificationId`/`conflictNotificationId`) so accounts don't
  overwrite each other. "Background sync notifications" (Settings, global,
  default on) gates progress/summary for automatic runs (`KEY_NOTIFY`,
  baked into the periodic job input so it needs a reschedule); conflicts and
  user-initiated "Sync now" always notify. Manual download/upload
  notifications use `file_downloads_v2`/`share_upload_v2` at default importance
  (progress silent, completion audible). Channel importance can't be changed
  once created, so changing it means a new channel id plus
  `NooNotificationChannels.ensure(legacyIds = ...)` deleting the old one.
- **One sync at a time.** `SyncEngine.syncLock` (a process-wide coroutine
  `Mutex`) wraps both `SyncWorker` and `ConflictResolveWorker`. WorkManager
  runs differently-named jobs concurrently, and both workers load the whole
  sync-state map, mutate it and save it back - so overlapping runs (periodic
  + a pull, two accounts due at once) silently discarded each other's
  updates, and `SyncStatusBus` only tracks one account at a time. A run that
  has to wait simply starts when the current one finishes. The network constraint is `NetworkType.UNMETERED` by default
  (`!syncOnCellular`, Wi-Fi only) or `NetworkType.CONNECTED` if the user's
  opted into cellular sync. Turning sync off for a path
  (`SyncStatusController.removeSyncedPath`) also calls
  `SyncService.removeLocalSync`, which runs `SyncEngine.removeLocalSync` on
  a background thread (deletes the local mirror files under that path
  *and* their entries in the native sync-state map - clearing state too,
  not just the files, matters because a bare "file's gone but the server
  hasn't changed" without a state reset reads as a user-initiated local
  deletion to `diffFolder`, so a later re-add wouldn't re-download
  anything).
- Synced-path list (`SyncStatusController.syncedPaths` - files or folders, not
  just folders despite the name of the underlying pref/native `Data` key,
  which stayed `ui_synced_folders`/`folders` to avoid a storage-key
  migration for a rename) follows the standard per-account-pref pattern
  (JSON-encoded string list, in `AccountStore.perAccountPrefKeys`); a
  parallel `_syncedPathTypes` map (path -> isFolder, `ui_synced_folder_types`)
  tracks which of those paths are folders vs individual files for the sync
  header's folder/item counts, defaulting missing entries to folder (the
  common case, and what any path added before this map existed will look
  like). **`addSyncedPaths`/`removeSyncedPaths` gate on
  `_accountLoadedGate`** (a `Completer`, deliberately starting
  *incomplete* - not pre-completed - completed once
  `_onAccountActivated`'s async per-account prefs load actually finishes,
  re-armed on `_onAccountCleared`) before touching `_syncedPaths` at all -
  without this, syncing a folder soon enough after opening the app (or an
  account switch) could race that load: the mutator spreads the *current
  in-memory* `_syncedPaths` (still `[]`, the pre-load default) and
  immediately persists the result, silently overwriting the
  previously-saved list and losing every other folder that had been
  synced before. Starting the gate pre-completed was an actual bug here -
  it meant only account *switches* (which call `_onAccountCleared`,
  re-arming it) were protected, leaving the very first cold-start load
  completely exposed to the race. A second, related guard,
  `_hasLoadedSyncedPathsForAccount`, stops `_onAccountActivated` from
  re-reading `_syncedPaths` from storage more than once per account -
  activation can fire again for the same account (e.g.
  `SessionController` re-verifying a provisional/offline login once
  connectivity returns), and a second read could clobber an in-memory
  mutation made between the first load and that one if its own persist
  hadn't landed yet. `syncEverything`
  (`ui_sync_everything`, per account) works the
  same way - when on, `SyncService` sends `['/']` as the path list instead
  of `syncedPaths`, mirroring the whole account rather than requiring
  per-item opt-in. `syncOnCellular` is a plain global pref. `syncEverything`
  and `syncOnCellular` are managed from Settings → Device Sync (a "Sync
  everything" switch, the cellular toggle, a manual "Sync now", and a
  "View offline files" row that pushes the Offline tab - see below); the
  configured path list itself, with its remove buttons, lives on the
  Offline tab now, not Settings. Individual files or folders are toggled
  from Files' selection toolbar ("Sync to device", works over the whole
  selection at once - either item type, folders or files - not just a
  single item; the action reads as "stop syncing" only once every selected
  item is already synced, otherwise it syncs whichever ones aren't yet,
  and either direction ends with a confirmation SnackBar). Multi-item
  add/remove goes through `SyncStatusController.addSyncedPaths`/
  `removeSyncedPaths` (batched), never a per-item loop of
  `addSyncedPath`/`removeSyncedPath` - looping was an actual bug: each
  `addSyncedPath` call fires its own `SyncService.syncNow`, and
  `syncNow`'s native side enqueues via `WorkManager.enqueueUniqueWork(...,
  ExistingWorkPolicy.REPLACE, ...)`, so a second item's call cancelled the
  first item's still-in-flight sync pass instead of letting it finish -
  only ever syncing the last item enqueued. The batched methods mutate
  `_syncedPaths` for the whole set and call `reschedule`/`syncNow` exactly
  once, with the complete folder list, so `SyncWorker` handles every item
  in one run (it already loops its whole `folders` list sequentially
  within a single `doWork()` call - see above).
- **The Offline tab** (`FilesView(offline: true)` over
  [`OfflineController`](../../lib/providers/offline_controller.dart), see
  `architecture.md`'s `FolderBrowser`) is the Files tab itself - same
  breadcrumbs, controls, tiles and thumbnails - over whatever device-sync
  has actually landed on disk - deliberately no selection/multi-select
  toolbar, since delete/share/move don't make sense for an already-synced
  local mirror.
  Reads straight off `<externalFilesDir>/sync/<accountId>/<currentFolder>`
  (non-recursive `Directory.list()` per folder) via `dart:io`, not fetched
  from the server (mirrors `SyncEngine.kt#syncRoot`'s layout exactly), so
  it works with no connection and never round-trips through a
  MethodChannel just to list files. `OfflineController` refetches the
  current folder automatically whenever a `SyncService.statusStream`
  snapshot shows syncing just stopped, so newly-downloaded files show up
  without a manual pull-to-refresh. Tapping an item opens
  `FileViewerScreen` with `localPath` set (see below) - same in-app viewer
  Files uses, just reading from disk instead of the server; tapping a
  folder navigates into it, same as Files. Resolves the local path via
  `OfflineController.localPathFor(item)`, a pure function of the item's
  path - deliberately *not*
  `SyncStatusController.localSyncedFilePath`, which additionally
  re-verifies the item falls under a configured sync target
  (`_isPathInSyncScope`). That check is redundant and was actually a bug
  here: every item this controller ever hands out already came from
  listing this exact directory tree, so it's definitionally already
  local, and re-deriving "is this still in scope" from `syncedPaths`
  could disagree with what's genuinely sitting on disk (e.g. nested
  paths, timing right after a scope change) and report a visibly-listed
  file as "no longer available". Pull-to-refresh triggers
  `SyncService.syncNow` followed by a re-list. The
  configured sync targets themselves (with "stop syncing" per target, what
  used to be Settings' Device Sync card's own inline list) live in a
  bottom sheet behind the app bar's sync icon (`_ManageSyncedFoldersSheet`)
  rather than inline in the main view, so the browser itself stays a plain
  Files-style listing; Settings' own "View offline files" row just pushes
  this whole tab.
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

## Working offline

[`ConnectivityController`](../../lib/providers/connectivity_controller.dart)
wraps `connectivity_plus` (OS-level route detection - Wi-Fi/mobile/none,
not a guarantee the Nextcloud server itself is reachable) and is the
single source of truth every offline-aware decision in the app consults.
**Its very first `checkConnectivity()` call is re-verified once more,
~2 seconds later** - that first check can spuriously report "no network"
while Android's connectivity stack is still attaching callbacks to a
just-started process (a real cold-start quirk, not a genuine transition),
and since `onConnectivityChanged` only fires on actual transitions, a
false initial "offline" read would otherwise stick for the rest of the
session with no further event ever correcting it - `SessionController`
would keep treating the login as provisional indefinitely, and every
network-fetching controller (Files/Photos/Favorites/Trash/Shares/Recent)
would simply never receive its real activation signal, leaving every tab
permanently empty despite the device being online the whole time. This
was a real, previously-shipped regression, not a hypothetical.

- **Session restore never makes a doomed HTTP request.**
  `SessionController._applyCredentialsForAccount` checks
  `connectivity.isOffline` *before* calling `NextcloudService.testConnection()`
  - if there's no route at all, it skips the request entirely rather than
  letting it fail (fast or slow) and parsing the exception. Either way (no
  route, or a network-level exception once a request is attempted -
  timeout, DNS, unreachable host, a transient 5xx), the session logs in
  *provisionally*: `_isLoggedIn = true` with the already-constructed
  `_service` kept around, `_isProvisionalLogin = true`. Only an actual 401
  (`_errorMessage` contains "401") is treated as a real rejection - drops
  the stored password and logs out for real. Provisional login exists
  specifically so a genuinely offline cold start still lands on
  `MainShellView` (restricted to the Offline tab - see below) instead of
  bouncing to `LoginView`, which would strand the user with no way back in
  short of Login Flow v2 again (`switchAccount` no-ops when "switching" to
  the account that's already nominally active, and `activeAccountId` is
  never cleared by a network failure).
- **Two account-activation signals, not one**, precisely so a provisional
  login doesn't cascade into a pile of doomed requests from every other
  controller: `addAccountActivatedListener` (fires *only* on a real,
  verified login - what `FilesController`/`PhotosController`/
  `FavoritesController`/`TrashController`/`SharesController`/
  `RecentController` all register for, since their own activation work is
  a network fetch) vs. `addAccountReadyListener` (fires on *either* a
  verified or a provisional login - what `SyncStatusController`/
  `OfflineController` register for instead, since their own activation
  work - loading prefs, listing local files, calling the native sync
  MethodChannel - is local/native-only and safe with no connection at
  all). A provisional login fires only `ready`, never `activated`; a
  verified login fires both.
- **Reconnecting re-verifies automatically.** `SessionController` listens
  to `connectivity` itself; the moment it flips from offline to online
  while `_isProvisionalLogin` is still true, it re-runs
  `_applyCredentialsForAccount` with the same cached account/password. On
  success this is what finally fires `_notifyAccountActivated` for real,
  so Files/Photos/etc. get their first actual fetch without the user
  having to force-quit/restart the app.
- **`MainShellView` collapses the bottom nav to just the Offline tab**
  while `connectivity.isOffline`, the same override mechanism already used
  for picking mode (see `architecture.md`) - every other tab would just
  show its own loading spinner or error state with no connection, so
  there's nothing useful to switch to. `MoreTabsButton` hides entirely in
  this state too, for the same reason it hides while picking - there's no
  hidden tab it could usefully open either.
- **The sync header's "Offline" label wins over everything else.**
  `_syncHeaderDisplay`/`_syncSummary` (`synced_header_scaffold.dart`) both
  take a `bool isOffline` and check it first, ahead of conflicts/syncing/
  configured-targets - with no connection, *why* nothing's syncing right
  now matters more than what would otherwise be shown, so "Sync off"
  (nothing configured) and "Offline" (nothing *can* sync right now,
  regardless of configuration) stay distinct messages.
- **`FileViewerScreen` can read a file straight from disk.** Its optional
  `localPathResolver` param (`Future<String?> Function(NextcloudItem)`,
  only ever set by the Offline tab, passing `OfflineController.
  localPathFor`) swaps every preview widget's data source -
  `_ImagePreview`/`_VideoPreview` use `Image.file`/
  `VideoPlayerController.file` instead of the `.network`/`.networkUrl`
  variants, `_PdfPreview`/`_TextPreview` read via
  `File(path).readAsBytes()` instead of `NextcloudService.fetchBytes` -
  same in-app viewer either way, no separate "offline preview" screen.
  Unlike a single up-front path, a *resolver* is what makes `siblings`
  (swipe-between-media) behave identically to Files/Photos while offline:
  the swipeable `PageView.builder` calls it again for whichever sibling
  you've swiped to (wrapped in a `FutureBuilder`, since each resolution
  is an async disk check), not just the item the viewer opened on - the
  Offline tab passes its whole current folder's `items` as `siblings`,
  same as Files does with its own. The action bar hides Favorite/Delete/
  Download-to-device (`showServerActions: false`) since those need a live
  server - Share and Open-externally still work (`_openExternally` calls
  the resolver directly instead of downloading to a temp file first;
  Share already prefers a local copy when one exists, see
  `ShareSheet._shareFileDirectly`).

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

- `putBytes(path, bytes)` does a WebDAV `PUT` to overwrite a file; used by the text/markdown editor (`MediaTextPreview`).

## Changing a share's permissions

`NextcloudService.updateSharePermissions` does `PUT
/ocs/v2.php/apps/files_sharing/api/v1/shares/{id}` with a `permissions`
bitmask (1 read, 2 update, 4 create, 8 delete, 16 reshare). The share
sheet's per-person pill opens a menu with Can view (1) / Can edit (3 for
files, 15 for folders), keeping the existing reshare bit, plus Remove access.

## Native services on iOS (in progress)

The five `dev.ayushya.noo/*` channels (`share_intent`, `pick_intent`,
`upload_service`, `download_service`, `sync_service`, plus their status
`EventChannel`s) were written for Android in Kotlin. iOS implements
`upload_service` (+ its status stream) and `download_service` so far
(`ios/Runner/Native/`, see below); for the other three there's no handler, so
calls throw `MissingPluginException`. `lib/services/native_channel.dart`
makes that safe until each one is built in Swift:

- `invokeIfAvailable` - a missing implementation returns null. For cold-start
  checks (`getInitialShare`, `getPickRequest`, `getSyncStatus`) and
  scheduling/cleanup (`reschedule`, `cancel`, `removeLocalSync`,
  `finishPick`/`cancelPick`).
- `invokeOrExplain` - throws `NativeServiceUnavailable("<Feature>")`, whose
  message callers already show in a snackbar ("Uploading isn't available on
  this platform yet."). For things the user just asked for: `startUpload`,
  `startDownload`, `syncNow`, `resolveConflict`.
- `quietEvents` - wraps an `EventChannel` so the missing-implementation error
  is dropped instead of surfacing as an unhandled stream error.

When a channel gets a real iOS implementation nothing changes on the Dart
side - the helpers only act on `MissingPluginException`.

`SyncService.baseDirectory()` is where the `sync/<accountId>/...` mirror
lives: `getExternalStorageDirectory()` on Android (what `SyncEngine.kt`
writes), the app support directory elsewhere, because that call throws on
iOS. `OfflineController` and `localSyncedFilePath` both go through it.
### iOS upload/download (`ios/Runner/Native/`)

- `NativeServices.swift` registers the channels from
  `AppDelegate.didInitializeImplicitFlutterEngine` (via
  `engineBridge.applicationRegistrar.messenger()`) and forwards
  `startUpload`/`startDownload` to `TransferManager`; a batch's completion
  goes back over `upload_service/status` so `FilesController` refreshes the
  folder like on Android.
- `TransferManager.swift` runs everything on one *background* `URLSession`
  (`dev.ayushya.noo.transfers`, `sessionSendsLaunchEvents`), so transfers
  finish after the app is suspended/closed; `AppDelegate` hands the system's
  `handleEventsForBackgroundURLSession` completion handler to it and calls
  `reconnect()` at launch. Each task carries its info in `taskDescription`
  and its batch's running totals live in `UserDefaults`, so the one summary
  local notification ("Uploaded 3 files") still fires after a relaunch.
- Uploads: one `PUT` per file to `<server>/remote.php/dav/files/<user>/...`
  from a staged copy in Caches (no chunking, so very large files are bound by
  the server's single-request limit; an existing file with the same name is
  overwritten). Sends `X-OC-Mtime`. Downloads: `GET` into
  `Documents/Downloads`, with `UIFileSharingEnabled` +
  `LSSupportsOpeningDocumentsInPlace` set so it shows in the Files app under
  "On My iPhone > Noo"; a name clash becomes `a (1).txt`.
- No progress notification (iOS can't update one from a background session
  the way Android's foreground service does) and no cancel yet - only the
  final summary. The Dart snackbar text still says "see the notification for
  progress".
- `WebDAV.swift` (URL building) and `LocalFiles.uniqueURL` are pure and
  covered by `ios/RunnerTests` (`xcodebuild test -workspace
  ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS
  Simulator,id=<udid>'`).

Not built on iOS yet: Share Extension (needs an App Group), the picker
(File Provider), and sync (`BGTaskScheduler`) - see the iOS handoff notes.
