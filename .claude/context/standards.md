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
- Read provider state with `context.watch<ServerProvider>()` in `build`,
  and `context.read<ServerProvider>()` for one-off calls from callbacks
  (matches `LoginView._handleContinue`).

## `ServerProvider` conventions

- Any method that fetches data and writes it into a shared field
  (`refreshData`, `fetchAllMedia`, `fetchTrash`, `fetchShares`,
  `fetchRecent`, `_applyCredentialsForAccount`) must guard against a stale
  write from an account the user has since switched away from: capture
  `final gen = _sessionGeneration;` at entry, and check
  `if (gen != _sessionGeneration) return;` immediately after each `await`
  before touching any field or calling `notifyListeners()`. Follow this
  pattern for any new fetch method added to the provider.
- New persisted state on `ServerProvider` must be classified global vs.
  per-account (see `architecture.md`/`server.md`) up front — global state
  uses a plain `_prefsFuture.then((p) => p.setX(key, value))`; per-account
  state goes through `_persistAccountPref(key, (p, namespacedKey) =>
  p.setX(namespacedKey, value))` and must also be handled in
  `_applyAccountPrefs` (both the "reset to default when no account" and the
  "load for this account" branches) so it's correct immediately after a
  switch, not just at startup.

## Testing

- Widget tests must mock platform channels that the app touches on startup
  — `SharedPreferences.setMockInitialValues({})` and a mock
  `MethodChannel('plugins.it_nomads.com/flutter_secure_storage')` handler —
  and disable Google Fonts network fetching
  (`GoogleFonts.config.allowRuntimeFetching = false`) in `setUpAll`. Without
  these, `ServerProvider`'s session restore never resolves in the test
  sandbox (no plugin implementation is registered, so the read future just
  never completes) and the app stays on `_SplashView`'s indeterminate
  spinner, which makes `pumpAndSettle()` hang until its own timeout instead
  of failing fast. See `test/widget_test.dart` for the reference setup.
- Run with `flutter test`.

## Dependencies

Networking is deliberately split: `package:http` for simple JSON/XML
request-response calls, `package:dio` only where streaming/progress is
needed (downloads). Don't introduce a third HTTP client — extend the
existing split instead.
