# Server integration

## Auth: Login Flow v2

The app **never** collects a Nextcloud password directly. It implements
[Login Flow v2](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html#login-flow-v2)
via [`LoginFlowService`](../../lib/services/login_flow_service.dart):

1. `LoginFlowService.initiate(serverUrl)` POSTs to
   `{server}/index.php/login/v2`, gets back a browser login URL + a poll
   endpoint/token.
2. The app opens the login URL in the system browser (`url_launcher`); the
   user authenticates and authorizes there.
3. `ServerProvider` polls `LoginFlowService.poll(pollEndpoint, token)` every
   2 seconds (`Timer.periodic`, see `_pollTimer`/`_pollTimeoutTimer` in
   `server_provider.dart`) until it gets a 200 with `server`/`loginName`/
   `appPassword`, a non-404 error, or a 10-minute timeout.
4. The returned **app password** (scoped, revocable) is what gets stored and
   used for every subsequent request — real user passwords are never in
   memory or on disk.

`LoginFlowStatus` (`idle` → `initiating` → `awaitingBrowser` → `error`)
drives `LoginView`'s UI; see `LoginFlowService`'s doc comment for the full
flow rationale before changing it.

## Talking to the server

[`NextcloudService`](../../lib/services/nextcloud_service.dart) is the
client for an authenticated session — constructed with `serverUrl` +
`username` + the app password, one instance per login (held as
`ServerProvider.service`, recreated on login/logout).

- **Files**: WebDAV (`PROPFIND`/`MKCOL`/`DELETE`/`MOVE` etc. against
  `/remote.php/dav/files/{username}/...`) via raw `http`/`dio` calls with a
  hand-rolled XML request body and `package:xml` for parsing responses —
  there is no WebDAV client dependency. `_parseDavDate`/`_davPath` in this
  file exist because WebDAV responses use RFC 1123 dates and either bare
  paths or full URLs for `href`; reuse them rather than re-deriving.
- **Everything else** (shares, activity, trash, favorites, quota, user info)
  goes through Nextcloud's OCS APIs (`/ocs/v2.php/...`), JSON in, with the
  `OCS-APIRequest: true` header required on every OCS call.
- Auth header is HTTP Basic (`username:appPassword`, base64), built in
  `_headers`/exposed as `authHeaders` for widgets that need to hit URLs
  directly (e.g. `Image.network(url, headers: service.authHeaders)` for
  thumbnails/previews).
- Downloads stream through `Dio` (`downloadToFile`) for progress callbacks;
  small in-app previews (text/PDF) use `fetchBytes` via `package:http`.

## Session persistence

- **Credentials** (`server`, `loginName`, `appPassword`) live in
  `flutter_secure_storage` — OS keychain/keystore-backed, never
  `shared_preferences`.
- **UI/app preferences** (theme mode, seed color, dynamic-color toggle,
  bottom-bar opacity/blur, grid vs. list, sort field, hidden-files toggle,
  etc.) live in `shared_preferences` — see the `_pref*` key constants at the
  top of `server_provider.dart`.
- On startup, `ServerProvider._restoreSession()` reads the secure-storage
  keys and, if all three are present, rebuilds a `NextcloudService` without
  re-hitting the login flow (`_applyCredentials(..., persist: false)`).
  `isRestoringSession` gates the splash screen until this resolves — see
  `standards.md` for why widget tests must mock both storage channels
  rather than relying on this async path throwing naturally.
