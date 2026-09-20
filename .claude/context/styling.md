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
- **Scrollbars are deliberately not shown** — every scrollable list in the
  app is a plain `ListView`/`CustomScrollView` with no `Scrollbar` wrapper
  and no `scrollbarTheme` override (tried once, explicitly reverted). Don't
  reintroduce one without being asked.

## Reusable chrome

- [`getItemIcon`/`getIconColor`/`ItemThumbnail`](../../lib/widgets/item_icon.dart)
  — the icon/color/thumbnail treatment for a file or folder, shared by any
  screen that lists `NextcloudItem`s the way the Files tab does (currently
  `files_view.dart` and `share_upload_view.dart`'s destination picker).
  Extend this rather than re-deriving per-type icons/colors at a new call
  site.
- [`DetailsHeader`](../../lib/widgets/details/details_sheet.dart) — the
  icon-box/name/meta row every per-item bottom sheet opens on
  (`DetailsSheet`, the media viewer's collapsed peek state, and
  `ShareSheet`). Takes a `padding` override for callers whose own scroll
  view already applies horizontal insets (`ShareSheet`'s `ListView`), so it
  doesn't get doubled up. Reuse this instead of a bare title `Text` for any
  new per-item sheet - a plain title reads as under-designed next to the
  other sheets (a real instance: `ShareSheet` used to be just that).
- [`FrostedGlassContainer`](../../lib/widgets/frosted_glass_container.dart) —
  the blurred/translucent pill background shared by all floating chrome
  (bottom nav bar, media-viewer top/bottom bars and video transport
  controls). Reuse this for any new floating overlay instead of building a
  new blur/shadow combo.
- [`FloatingBottomNavBar`](../../lib/widgets/floating_bottom_bar.dart) — the
  main tab bar; opacity/blur are user-adjustable settings
  (`SettingsController.bottomBarOpacity`/`bottomBarBlur`), not constants —
  pull new adjustable visual knobs from `SettingsController` the same way
  rather than hardcoding them.
- [`SyncedHeaderScaffold`](../../lib/widgets/synced_header_scaffold.dart) —
  the pull-to-sync `CustomScrollView` header shared by 5 of the 6 tabs (see
  `architecture.md`); also where the pull-to-refresh gesture thresholds and
  the classic Material refresh spinner live. Its persistent compact chip
  (icon + "Sync off"/"Syncing…"/"Synced"/"Sync issue") reflects device-sync
  status (`SyncStatusController.syncHeaderStatus`), not the WebDAV-refresh
  loading state the pull gesture itself triggers - that has its own,
  separate floating spinner bubble, so nothing was lost by handing the
  persistent text/icon over. The expanded panel's headline is a separate,
  more detailed string (`_syncSummary` in `synced_header_scaffold.dart`) -
  actual folder/item counts ("2 folders & 5 items synced") rather than
  just repeating the chip's generic label, which would otherwise read
  "Synced" even when a folder's just been added and nothing's downloaded
  yet.
- [`SyncStatusBadge`](../../lib/widgets/sync_status_badge.dart) — the small
  corner badge over a thumbnail showing per-item device-sync status
  (`cloud_done`/`sync`, nothing for not-synced/conflict); used in Files'
  list and grid tiles today. Reuse this rather than a new ad hoc badge if
  another view starts showing sync status per item.
- [`SeekBarPainter`/`SeekBarPreview`](../../lib/widgets/seek_bar_painter.dart)
  — the four `MediaProgressBarStyle` presets (Default/Wavy/Slim/Squiggly)
  for the video player's seek bar, plus a perpetually-animated
  `SeekBarPreview` wrapper used by the Settings style picker so every
  preview always matches the real widget exactly (same painter, just fed
  demo `progress`/`phase` values). Add new seek-bar presets here, not by
  forking the painter.
- Chrome inside the media viewer (`file_viewer_screen.dart` — the top bar's
  back button + filename, the bottom action bar, the video transport
  controls) all share one small hand-rolled icon-button pattern
  (`_ActionIconButton`: `InkWell` + `Icon` at a fixed 22px, colored from
  `colorScheme.onSurface` unless overridden) rather than plain `IconButton`s
  — match this instead of adding a bare `IconButton` in that screen, since a
  default-styled one visibly stands out against the rest (this was a real
  bug: an unstyled back button read as "too large" next to everything else).
- A title/label that might overflow a fixed-width chrome bar (e.g. the media
  viewer's filename) should use `_MarqueeTitle`-style logic — measure with
  `TextPainter` first and only switch to a scrolling `Marquee` when the text
  actually doesn't fit, rather than marqueeing unconditionally.
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
- **Anywhere the app shows its own icon in-app** (splash, lock screen,
  login screen) uses `assets/icon/app_icon_monochrome.png` — a plain white
  silhouette on transparent, tinted via `ColorFiltered(colorFilter:
  ColorFilter.mode(colorScheme.onSurface, BlendMode.srcIn), ...)` so it
  reads correctly in both light and dark mode. Never the full-color
  `app_icon.png`/adaptive-icon assets for in-app UI — those are for the
  launcher icon only (`flutter_launcher_icons` in `pubspec.yaml`).
