# Styling

**Migration in progress:** the target look is
[`design-system/DESIGN_SYSTEM.md`](design-system/DESIGN_SYSTEM.md) — warm
neutrals, one violet accent, pill controls, Schibsted Grotesk/Instrument
Sans, no gradients/shadows — built from the `widgets/noo/` component kit
(see "Noo design-system components" below). Rebuilt so far: the app shell
(top/bottom bars, drawer, sidebar, toolbar), Files/Offline, Photos,
Favorites, Recent, Activity, Trash, Shares, Settings, the lock screen,
login, `ShareUploadView`, `MoveCopyDestinationPicker`,
`MoveCopyConflictSheet`, the shared `Breadcrumbs` widget, and the file
details/share bottom sheets/dialogs (`DetailsSheet`/`ShareSheet`). **Still on
the pre-rework Material 3 theme** documented in "Theme" and "Reusable
chrome" below: `FileViewerScreen` (the media viewer), `SearchView`, and
`LoginWebviewView`. Update this file to describe each area as it gets
reworked, rather than leaving stale Material 3 guidance next to a design
system that's already superseded it.

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

## Noo design-system components

The rebuilt UI is assembled from `lib/widgets/noo/`, which implements
`DESIGN_SYSTEM.md` §2–3. Build new screens from these rather than from raw
Material widgets or the pre-rework chrome below.

- **Tokens** live in [`design_tokens.dart`](../../lib/theme/design_tokens.dart):
  colors via `context.nooColors` (a `NooColors` `ThemeExtension`), plus
  `NooText`, `NooSpace`, `NooRadii`, `NooSizes`, `NooMotion` and
  `nooDialogShadow`. `NooText` styles set no color; callers add it with
  `copyWith(color: ...)`. Flutter's `TextStyle.height` is a multiple of font
  size, so the spec's CSS line-height maps to it directly (for example,
  0.9 → `height: 0.9`).
- **Icons are Lucide** (`lucide_icons_flutter`, `LucideIcons.*`) inside
  `noo/`, never Material `Icons.*`.
- **Components are data-agnostic.** They take strings, icons, colors and
  callbacks, not `NextcloudItem`/`AppTab`, so the screen layer maps models
  onto them.
- **Platform differences** are chosen with a flag rather than by reading the
  platform inside the widget: `NooNavStyle` (`ios`/`android`, with
  `NooNavStyle.fromPlatform`) for nav chrome, and `iosStyle` on rows and
  cards for the ellipsis vs. vertical-ellipsis overflow icon.

Catalog:

| Folder | Components |
|---|---|
| `core/` | `NooButton`, `NooFab`, `NooChip`, `NooSegmentedControl`, `NooToggle`, `NooSearchField`, `NooAvatar`, `NooBadge`, `NooProgressBar` |
| `lists/` | `NooGroupedList`, `NooSettingsRow`, `NooTabOrderRow`, `NooBanner`, `NooSummaryCard`, `NooSelectionBar` |
| `files/` | `NooFileKind` (spec §1.2 tiles; `NooFileKind.from(name:, mimeType:, isDirectory:)`), `NooFileTile`, `NooStatusIcon`/`NooSyncStatus`, `NooFileRow` (mobile 64px), `NooFileTableHeader`/`NooFileTableRow` (desktop), `NooSwipeAction` |
| `media/` | `NooGridCard`, `NooPhotoTile` (video badge, selection), `NooPhotoGroupHeader`/`NooPhotoGrid` (sliver, or `.box`), `NooActivityItem`, `NooStatCard` |
| `nav/` | `NooBottomBar`, `NooTopBar` (a `PreferredSizeWidget`) with `NooTopBarButton`/`NooTopBarBack`, `NooDrawer` with its `Account`/`Storage`/`Item`/`Link` parts, `NooSidebar` with `NooSidebarItem`/`Divider`/`Account`/`Storage`, `NooToolbar` |
| `overlays/` | `showNooSheet`, `showNooDialog`/`NooDialog`, `NooOverlayHeader`, `NooTextField`, and the share parts `NooShareSection`, `NooPersonAccessRow`, `NooPermissionPill` |

Gotchas:
- `NooDrawer` can't set its own scrim. The host `Scaffold` needs
  `drawerScrimColor: context.nooColors.scrim`.
- `NooGroupedList` draws dividers by showing `line` through 1px gaps, so each
  child must paint its own surface (`NooSettingsRow` and `NooTabOrderRow`
  do). Its `collapsible`/`initiallyExpanded` params (off by default) make
  `label` a tap target that shows/hides the card - no current caller opts
  in (Settings' mobile sections used to, when every section rendered
  inline in one long column; now each section is its own pushed screen -
  see `account_view.dart`'s doc comment - so there's nothing left to
  collapse). The params stay on the component itself since it's otherwise
  generic.
- `NooSwipeAction` only reveals its action. The user has to tap the block to
  trigger it; a full swipe never deletes.
- Window chrome (macOS traffic lights, the Windows 40px title bar) isn't
  built yet. `NooSidebar.windowControls` is the slot for it.
- Always read colors through `context.nooColors`, never
  `Theme.of(context).colorScheme` - the latter is Flutter's own Material 3
  scheme, reseeded by the user's accent color choice (`AppTheme.light`/
  `.dark`), so anything painted from it carries a faint hue of whatever
  accent is picked instead of the app's neutral palette. `sticky_header_delegate.dart`
  shipped with this bug once already (a pinned controls-row header tinted
  by the accent instead of matching its screen's plain `colors.bg`).
- `NooSegmentedControl` defaults to `onSurface: false` (`colors.surface`
  fill) - right when it's sitting directly on `colors.bg` (List/Grid
  toggle, Shares' scope switcher), but pass `onSurface: true` for one
  placed inside a sheet or dialog (already `colors.surface`), or its pill
  track blends invisibly into the sheet instead of reading as a grouped
  control (Files'/Photos' sort and type-filter sheets do this).
- Any `RefreshIndicator` needs `physics: const AlwaysScrollableScrollPhysics()`
  on its scrollable child, or pull-to-refresh silently can't be triggered
  once the list is short enough to fit the viewport (empty, or one item) -
  every tab's `CustomScrollView` sets this explicitly for exactly that
  reason.

## Reusable chrome

**Rebuilt on the Noo design system** (Files/Offline, Photos, Favorites,
Recent, Activity, Trash, Shares, Settings, the app shell, lock screen,
login, `ShareUploadView`, `MoveCopyDestinationPicker`, `DetailsSheet` and
`ShareSheet`): these no longer use the pieces below. Their own building
blocks are noted where they matter:

- `FilesControlsRow` (`lib/widgets/files_controls_row.dart`) — now built from
  `NooChip`/`NooSegmentedControl`; still the sort/hidden/scope/type-filter/
  view-mode row shared by Files and Offline (`showStorageScope: false` for
  Offline), and reused as-is by Favorites.
- `lib/widgets/files/file_breadcrumb_row.dart` — the noo-styled breadcrumb
  trail Files uses in place of the shared
  [`Breadcrumbs`](../../lib/widgets/breadcrumbs.dart) widget. `Breadcrumbs`
  is now also noo-styled (same tokens, private-widget-turned-shared) — it's
  used only by `ShareUploadView`/`MoveCopyDestinationPicker`, which is why
  it was safe to restyle directly instead of forking another
  `FileBreadcrumbRow`-style copy; don't move Files back onto it.
  `lib/widgets/tabs/` (`tab_state_slivers.dart`, `tab_day_groups.dart`,
  `tab_location.dart`) — the loading/error/empty-state slivers and
  day/month grouping helpers shared by Recent/Activity/Trash/Shares.
  `lib/widgets/settings/` — Settings' 8 section widgets plus
  `settings_section.dart`'s `SettingsSection`/`showSettingsPicker` and
  `settings_dialogs.dart`'s `confirmRemoveAccount`.
  `lib/widgets/shell/shell_common.dart` — account/storage formatting,
  `openSettings`/`openSearch`, `showAccountSwitcher`, `ShellAvatarButton`,
  `ShellSearchLauncher`, shared by the mobile and desktop shell chrome.
- [`getItemIcon`/`getIconColor`/`ItemThumbnail`](../../lib/widgets/item_icon.dart)
  — `getItemIcon`/`getIconColor` are superseded by `NooFileKind` in
  rebuilt screens; `ItemThumbnail` is still reused as-is, fed into
  `NooFileTile`/`NooFileRow`/`NooFileTableRow`/`NooGridCard`'s `thumbnail`
  slot. `ShareUploadView`/`MoveCopyDestinationPicker` don't use any of the
  three any more - both destination pickers now list folders only (see
  below), and a folder never gets a real thumbnail (only image/video do),
  so a plain `NooFileTile(kind: NooFileKind.folder)` covers every row.
- `DetailsSheet`/`ShareSheet` (`lib/widgets/details/details_sheet.dart`,
  `lib/widgets/share_sheet.dart`) are rebuilt: `showNooSheet`/`showNooDialog`
  per `NooLayout.isDesktop`, with the header built from `detailsFileTile`
  (a `NooFileTile` keyed by `NooFileKind.from`) and `detailsMetaLine` -
  shared top-level helpers in `details_sheet.dart` so both sheets open on
  the same header, replacing the old `DetailsHeader` widget. Neither sheet
  uses `showGradualBottomSheet`'s drag-to-resize any more: `DetailsSheet`
  swaps Info/Versions/Activity with a `NooSegmentedControl` (there's no
  tab-strip component in the noo kit) instead of a `TabBar`/`TabBarView`,
  and both sheets' content sits in one `Column` so `showNooSheet`'s/
  `showNooDialog`'s own `SingleChildScrollView` handles overflow - a fixed
  page per tab no longer needs a resizable sheet to see the rest.
  `showGradualBottomSheet` (`lib/widgets/gradual_bottom_sheet.dart`) has no
  remaining callers as a result.
  `ShareSheet`'s "Share with people"/"Share link"/"Send file directly"
  sections follow `DESIGN_SYSTEM.md` §4 via `NooShareSection`/
  `NooPersonAccessRow`/`NooPermissionPill`; the permission pill and the
  link's permission/expiry chips are read-only display (no
  `ItemOperations` call updates a share's permission/expiry/password/
  hide-download yet) - promote those to real controls once that exists.
  Removing a person/group/email share is reachable by tapping their
  permission pill, which opens a small "Remove access" menu.
  [`MoveCopyConflictSheet`](../../lib/widgets/move_copy_conflict_sheet.dart)
  is rebuilt: `showNooDialog`/`showNooSheet` (per `NooLayout.isDesktop`), a
  `NooGroupedList` of file-tile rows with an inline
  `NooSegmentedControl<ConflictChoice>` once "Decide per item" is picked,
  and `NooButton`s for overwrite-all/keep-both/decide-per-item/confirm. Its
  `show(BuildContext, List<MoveCopyConflict>)` API is unchanged.
- [`FrostedGlassContainer`](../../lib/widgets/frosted_glass_container.dart) —
  the blurred/translucent pill background for the media viewer's top/bottom
  bars and video transport controls (its other former user, the floating
  bottom nav bar, is gone - see below). Reuse this for any new floating
  overlay instead of building a new blur/shadow combo.
- `SettingsController.bottomBarOpacity`/`bottomBarBlur` and
  `lib/widgets/floating_bottom_bar.dart`/`media_grid_tile.dart`/
  `swipeable_item.dart`/`sync_status_badge.dart`/`selectable_thumbnail.dart`
  are gone: the bottom bar is now the flat, non-blurred `NooBottomBar` (no
  opacity/blur knob - flat surfaces per the design system), grid tiles are
  `NooGridCard`, swipe actions are `NooSwipeAction`, and per-item sync
  status is `NooFileRow`/`NooFileTableRow`'s built-in `NooStatusIcon` list
  instead of a corner badge. `NooBottomBar` later gained its own, unrelated
  `NooBottomBarStyle.floating` (Settings → Appearance → "Bottom bar") -
  don't confuse the two: this one is still flat/non-blurred, just inset
  with a `line` border instead of edge to edge (no opacity/blur knob
  either). The host `Scaffold` needs `extendBody: true` while it's active
  (`main.dart` already wires this off `SettingsController.bottomBarStyle`).
  Settings' separate "Search in bottom bar" toggle
  (`SettingsController.searchInBottomBar`) adds a never-highlighted Search
  entry to either bar style (`NooBottomBar`'s `searchDestination`/
  `onSearchTap`) and lowers `SettingsController.maxVisibleTabs` by one -
  use that getter, not `defaultMaxVisibleTabs` from `models/app_tab.dart`,
  anywhere that needs the *current* cap on regular tabs.
- [`SyncedHeaderScaffold`](../../lib/widgets/synced_header_scaffold.dart) —
  the pull-to-sync `CustomScrollView` header with the persistent sync-status
  chip and pull-to-refresh gesture/spinner. Every screen (including
  `ShareUploadView`/`MoveCopyDestinationPicker`, its last two users) has
  dropped it for a plain `RefreshIndicator` + `CustomScrollView`
  (device-sync status now shows per-row via `NooStatusIcon`/the Offline
  `NooSummaryCard`, not a shared header chip), so the `SyncedHeaderScaffold`
  class itself is now dead code - kept only because the same file's
  top-level `formatBytes` helper is still widely used
  (`files_view.dart`/`favorites_view.dart`/`shell_common.dart`/
  `widgets/details/*`).
- [`SegmentedIconGroup`/`ToggleIconButton`](../../lib/widgets/segmented_icon_toggle.dart)
  and [`SortMenuButton`](../../lib/widgets/sort_menu_button.dart) — the
  Material sort/filter-chip pieces `ShareUploadView`/
  `MoveCopyDestinationPicker` used to mirror Files' old controls row with.
  Both destination pickers dropped that whole row (they only ever browse
  folders, so sort/hidden/scope/type-filter/grid controls don't apply), so
  these two files are now dead code too - `Breadcrumbs` is the only shared
  widget promoted to noo styling instead of removed, since Files' own
  `FileBreadcrumbRow` proved the same trail is still wanted elsewhere.
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
  launcher icon only. The launcher icon is maintained by hand from an
  IconKitchen export (`mipmap-*` in `android/app/src/main/res`); there is no
  generator step. `assets/icon/app_icon_monochrome.png` is deliberately a
  tightly-cropped glyph (unlike the launcher's safe-zone-padded monochrome
  layer), so it renders at a sensible size at 72-80px.
