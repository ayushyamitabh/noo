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
