# Code standards

## Linting

`analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` with
no rules added/relaxed. Run `flutter analyze` before considering a change
done; it should stay clean.

## Comments

Comments are used sparingly and only for non-obvious *why* — a hidden
constraint, a workaround, or the rationale for overriding a framework
default. See `AppTheme._pageTransitionsTheme`/`_sliderTheme`,
`NextcloudService._parseDavDate`/`_davPath`, and `LoginFlowService`'s class
doc comment for the house style: one short doc comment on the
class/function explaining *why* it exists, not what each line does. Don't
add comments that restate the code or describe what a well-named
class/method already makes obvious.

## Widget structure

- Screens (`views/`) are typically `StatefulWidget` when they own
  controllers/local UI state (e.g. `LoginView`'s form key + text
  controller); presentation is frequently split into small private
  `StatelessWidget`s in the same file (`_ServerForm`, `_WaitingForBrowser`
  in `login_view.dart`) rather than inlined in one large `build`. Follow
  this split for any view complex enough to have more than one visual
  "mode".
- Private helpers/widgets are prefixed with `_` and live in the same file as
  their one caller; promote to `widgets/` only once something is reused
  across files.
- Read controller state with `context.watch<XController>()` in `build`, and
  `context.read<XController>()` for one-off calls from callbacks (matches
  `LoginView._handleContinue`). Pull in only the specific controller(s) a
  widget actually needs (e.g. `FilesController` + `SyncStatusController`
  for a Files tile), not a catch-all — see `architecture.md`'s "State
  management" section for the full controller split and what each one owns.

## Controller conventions

- Any method that fetches data and writes it into a shared field
  (`FilesController.refreshData`, `PhotosController.fetchAllMedia`,
  `TrashController.fetchAll`, `SharesController.fetchAll`,
  `RecentController.fetchAll`, `SessionController._applyCredentialsForAccount`)
  must guard against a stale write from an account the user has since
  switched away from: capture `final gen = session.sessionGeneration;` at
  entry, and check `if (gen != session.sessionGeneration) return;`
  immediately after each `await` before touching any field or calling
  `notifyListeners()`. Follow this pattern for any new fetch method added
  to any controller.
- New persisted state must be classified global vs. per-account (see
  `architecture.md`/`server.md`) up front and live on whichever controller
  owns that domain — global state (`SettingsController`) uses a plain
  `_prefsFuture.then((p) => p.setX(key, value))`; per-account state goes
  through `_persistAccountPref(key, (p, namespacedKey) =>
  p.setX(namespacedKey, value))` and must also be handled in that
  controller's own `_onAccountCleared`/`_onAccountActivated` listeners
  (registered via `SessionController.addAccountClearedListener`/
  `addAccountActivatedListener` in the controller's constructor) so it's
  correct immediately after a switch, not just at startup.

## Testing

- Widget tests must mock platform channels that the app touches on startup
  — `SharedPreferences.setMockInitialValues({})`, a mock
  `MethodChannel('plugins.it_nomads.com/flutter_secure_storage')` handler,
  and `connectivity_plus`'s `MethodChannel('dev.fluttercommunity.plus/
  connectivity')` (`'check'` → a result list, e.g. `['wifi']`) plus its
  `EventChannel('dev.fluttercommunity.plus/connectivity_status')` (a
  `MockStreamHandler.inline` with a no-op `onListen` is enough) — and
  disable Google Fonts network fetching
  (`GoogleFonts.config.allowRuntimeFetching = false`) in `setUpAll`. Without
  these, `SessionController`'s session restore never resolves in the test
  sandbox (no plugin implementation is registered, so the read future just
  never completes) and the app stays on `_SplashView`'s indeterminate
  spinner, which makes `pumpAndSettle()` hang until its own timeout instead
  of failing fast. See `test/widget_test.dart` for the reference setup.
- Design-system components (`lib/widgets/noo/`) are tested in
  `test/widgets/noo/`, one file per component folder. Use the helpers in
  `noo_test_utils.dart`:
  - `setUpNooTests()` turns off font fetching.
  - `testNooWidgets(...)` runs a body once per theme, light and dark, built
    through the real `AppTheme`, and hands it the `NooColors`.
  - `pumpNoo(...)` mounts the widget.

  Build themes inside the test body, not at file level, because `AppTheme`
  touches Google Fonts before the test binding exists. `pumpNoo` centers
  the child, which loosens its constraints. To catch a widget stretching to
  fill its parent, put it in a bounded box (for example, `SizedBox` +
  `Align`).
- Run with `flutter test`.

## Local install/deploy

Never use `flutter install` to push a build to a test device — it always
does a full **uninstall-then-install** (prints "Uninstalling old
version..."), and Android deletes all app data (SharedPreferences, secure
storage — every saved account/preference) on uninstall. This wipes the app
clean on every single deploy, which looks like an account/settings-loss bug
but is actually just the install method.

Instead, build then install with `adb`'s replace flag, which updates the
APK in place and preserves app data:

```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

This only preserves data if the new APK's signature matches what's already
on the device. `android/app/build.gradle.kts` picks a release signing key
in this order: a local `android/key.properties` (gitignored — points at a
gitignored keystore file, e.g. `android/app/release-keystore.jks`), then
CI env vars (`RELEASE_KEYSTORE_PATH`/`_PASSWORD`, `RELEASE_KEY_ALIAS`/
`_PASSWORD`, set from the same repo secrets by both `.gitea/workflows/
build.yml`, triggered by `RC-Android-*` tags and producing a sideloadable
APK, and `.gitea/workflows/release.yml`, triggered by `Release-*` tags and
producing the `.aab` Play Console wants; `.gitea/workflows/ios.yml` builds
and uploads the signed iOS app to TestFlight on `RC-iOS-*` and `Release-*`
tags, on a self-hosted macOS runner), then falls back to the debug key if neither
is configured. As long as the same dedicated release keystore backs both
`key.properties` locally and the Gitea secrets, local release builds and
CI-built release APKs share one signature, so `adb install -r` works
cleanly either way. A local checkout with no `key.properties` set up falls
back to the (per-machine, ungitted) debug key, which won't match a
CI-signed APK — installing one over the other still forces a full
uninstall, since there's no way around Android's signature check from the
tooling side.

## Dependencies

Networking is deliberately split: `package:http` for simple JSON/XML
request-response calls, `package:dio` only where streaming/progress is
needed (downloads). Don't introduce a third HTTP client — extend the
existing split instead.

## Play Store upload (CI)

`.gitea/workflows/release.yml` (on `Release-*` tags) first checks the tag
equals `Release-<pubspec version>`, builds the signed `.aab`, attaches it to a
Gitea release, then uploads it with `r0adkll/upload-google-play` to the
`internal` track with `status: completed`, so it rolls out to internal
testers automatically (promote to other tracks in Play Console). Requires the `PLAY_SERVICE_ACCOUNT_JSON`
repo secret (service account with release permissions; the app's first
release must be uploaded manually). Play rejects a repeated `versionCode`, so
bump the `+N` in `pubspec.yaml` for every tag - re-tagging the same version
will fail the upload. Release notes come from
`distribution/whatsnew/whatsnew-en-US` is a plain text list: one item per
line starting with "- ", with no headings or blank lines. Keep the entire
file within 500 characters, including bullet prefixes and newlines. Maintain
this format when appending or replacing notes, and keep the list current
with every user-facing push, not just at release time (see CLAUDE.md
"Before pushing").

## Community PR flow

Gitea is the source of truth; GitHub is a push mirror (never commit to GitHub
`main`) and the public issue tracker. `scripts/sync-github-prs.sh` (cron on the
home server) imports open GitHub PRs into Gitea via Agit
(`refs/for/main`, topic `gh-pr-N`), where `.gitea/workflows/pr.yml` runs
analyze + tests. That workflow must never use secrets; signing and Play
credentials stay on the tag-triggered `build.yml`/`release.yml`. Issue
templates are in `.github/ISSUE_TEMPLATE/`.
