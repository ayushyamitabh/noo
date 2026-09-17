# Server integration

## Auth: Login Flow v2

The app **never** collects a Nextcloud password directly. It implements
[Login Flow v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2)
via [`LoginFlowService`](../../lib/services/login_flow_service.dart):

1. `LoginFlowService.initiate(serverUrl)` POSTs to
   `{server}/index.php/login/v2`, gets back a browser login URL + a poll
   endpoint/token.
2. The app opens the login URL for the user to authenticate/authorize.
   Which browser depends on whether this is the first login or an
   add-account flow (`addAccount`, see below):
   - First/only login: a Chrome Custom Tab (`url_launcher`,
     `LaunchMode.inAppBrowserView`) — real Chrome, so saved
     passwords/autofill work, unlike Flutter's own embedded web view.
     There's no way to close the tab automatically on success (Login Flow
     v2 never redirects back into the app, and a Custom Tab belongs to
     Chrome's own task) — the user switches back manually.
   - Adding another account: [`LoginWebViewView`](../../lib/views/login_webview_view.dart),
     a normal screen this app owns, backed by `package:webview_flutter`
     rather than a Custom Tab - pushed by `LoginView` the moment
     `loginFlowStatus` flips to `awaitingBrowser`. Two reasons this isn't
     a Custom Tab: (1) a Custom Tab shares Chrome's actual browser
     profile/cookie jar - if the user is still logged into the first
     account on the Nextcloud web UI in Chrome, it would silently reuse
     that session and authorize the wrong account instead of prompting
     fresh credentials; (2) `url_launcher`'s own `LaunchMode.inAppWebView`
     (tried first) is a bare native WebView Activity with no chrome of its
     own - no close button, and on at least some devices it draws
     edge-to-edge and hides the status bar. Owning the screen fixes both -
     isolated cookies, a normal `AppBar`/close button/safe area - and lets
     it close itself automatically on success (it watches
     `loginFlowStatus` itself), unlike the Custom Tab case. The cost is no
     Chrome-autofill for this one flow (Android's own system Autofill
     framework, e.g. a password manager, may still work in the WebView;
     Chrome's own saved-password autofill specifically cannot, since
     that's Chrome-only).
3. `ServerProvider` polls `LoginFlowService.poll(pollEndpoint, token)` every
   2 seconds (`Timer.periodic`, see `_pollTimer`/`_pollTimeoutTimer` in
   `server_provider.dart`) until it gets a 200 with `server`/`loginName`/
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
`ServerProvider.service`, recreated on every login/switch/logout). It's
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
- Auth header is HTTP Basic (`username:appPassword`, base64), built in
  `_headers`/exposed as `authHeaders` for widgets that need to hit URLs
  directly (e.g. `Image.network(url, headers: service.authHeaders)` for
  thumbnails/previews).
- Downloads stream through `Dio` (`downloadToFile`) for progress callbacks;
  small in-app previews (text/PDF) use `fetchBytes` via `package:http`.
- **Uploads** (`uploadFileFromPath(folderPath, fileName, localFilePath,
  {onProgress})`) stream the local file via `Dio().put()` with an explicit
  `Content-Length` and `onSendProgress`, mirroring the download path. The
  `ServerProvider` wrapper always uploads into `_currentFolderPath` — the
  share-to-upload flow (`ShareUploadView`) gets a caller-chosen destination
  by navigating there first (`navigateToAbsoluteFolder`), then uploading.
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
  reusing the same `ServerProvider` fields and `widgets/item_icon.dart` -
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

## Multi-account storage & session persistence

[`AccountStore`](../../lib/services/account_store.dart) owns everything
account-identity-related; `ServerProvider` owns everything about which
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
  and reloaded on every switch via `ServerProvider._applyAccountPrefs`.
- **Legacy migration**: `AccountStore.migrateLegacyIfNeeded` runs once ever
  (guarded by the `account_migration_v1_done` flag), turning a pre-multi-
  account install's 3 flat secure-storage keys + flat browsing prefs into
  the first saved (and active) account, so upgrading users are never logged
  out. Never assume the legacy keys are gone — always check the migration
  flag rather than the keys' absence.
- On startup, `ServerProvider._init()` awaits the migration, loads the
  account list + active id, then `_restoreSession()` looks up the active
  account's password and calls `_applyCredentialsForAccount` (the renamed,
  generation-guarded, account-aware version of what used to be
  `_applyCredentials`) to rebuild the session without re-hitting the login
  flow.
- **Switching accounts** (`switchAccount`/`cycleToNextAccount`/
  `cycleToPreviousAccount`/`removeAccount`'s fallback, plus landing on a
  freshly-added account) all funnel through the single `_activateAccount`
  engine: bump `_sessionGeneration`, cancel any pending login flow, clear
  every content field *without* ever setting `isLoggedIn` false (that's the
  detail that keeps `main.dart`'s root routing from bouncing through
  `LoginView` mid-switch), reload the target account's prefs, then verify
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
    check `!provider.isLoggedIn` afterward and `Navigator.popUntil((r) =>
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
extend `AppLockService`/the `ServerProvider` gates described in
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
