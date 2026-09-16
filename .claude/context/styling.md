# Styling

## Theme

All theming goes through [`AppTheme`](../../lib/theme/app_theme.dart)
(`AppTheme.light`/`AppTheme.dark`) — don't set colors/fonts ad hoc in
widgets. Key points:

- **Material 3**, seed-color based. `AppTheme.seedColors` is the picker list
  users choose from; `defaultNextcloudBlue` (`#0082C9`) is the fallback.
- **Dynamic color** (Android 12+ Material You / desktop accent color) is
  supported via `package:dynamic_color`'s `DynamicColorBuilder` wrapping the
  whole app in `main.dart`. When available and `useDynamicColor` is on, the
  OS-provided `ColorScheme` wins over the seed color — always thread both
  `dynamicScheme` and `useDynamicColor` through when adding a theme knob.
- **Font**: Inter via `google_fonts`, applied through
  `GoogleFonts.interTextTheme(...)`. In tests, set
  `GoogleFonts.config.allowRuntimeFetching = false` in `setUpAll` — without
  it, the font-fetch call to Google's CDN can stall `pumpAndSettle`
  indefinitely (see `standards.md`).
- **Cards**: flat (`elevation: 0`), 20px rounded corners,
  `surfaceContainerLow`.
- **App bars**: flat, not centered, `surface` background.
- Two Flutter defaults are deliberately overridden app-wide rather than
  per-widget, each with a comment explaining why in `app_theme.dart`:
  Android predictive-back page transitions, and the non-2023 `SliderTheme`.
  Follow that pattern (a themed default + a comment) instead of overriding
  per-instance if you need the same behavior elsewhere.
- Dark theme supports an `amoled` flag that flattens every surface tone to
  pure black — extend `colorScheme.copyWith(...)` there if a new surface
  role needs the same treatment, don't hardcode `Colors.black` at call sites.

## Reusable chrome

- [`FrostedGlassContainer`](../../lib/widgets/frosted_glass_container.dart) —
  the blurred/translucent pill background shared by all floating chrome
  (bottom nav bar, media-viewer action bar). Reuse this for any new floating
  overlay instead of building a new blur/shadow combo.
- [`FloatingBottomNavBar`](../../lib/widgets/floating_bottom_bar.dart) — the
  main tab bar; opacity/blur are user-adjustable settings
  (`ServerProvider.bottomBarOpacity`/`bottomBarBlur`), not constants — pull
  new adjustable visual knobs from the provider the same way rather than
  hardcoding them.
- Icons: prefer `Icons.*_rounded` (matches the rest of the app) or
  `material_symbols_icons` where Material Symbols are already in use; avoid
  mixing in the sharp/outlined default set.

## Conventions

- No hardcoded colors for anything themeable — pull from
  `Theme.of(context).colorScheme`, not `Colors.blue` etc. (per-file-type
  icon tinting in `files_view.dart`'s `_getIconColor` is the one deliberate
  exception, since those colors are content-identity cues, not theme).
- Use `colorScheme.surfaceContainer*`/`onSurfaceVariant` tokens for
  elevation/secondary text rather than manual opacity on black/white.
