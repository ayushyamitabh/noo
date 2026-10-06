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
  `GoogleFonts.interTextTheme(...)`. Font files ship in
  `assets/google_fonts/` (Instrument Sans, Schibsted Grotesk) and
  `main()` sets `GoogleFonts.config.allowRuntimeFetching = false`, so the
  app never contacts Google (the privacy policy on the website relies on
  this — keep it true; add new weights as bundled files). Tests set the
  same flag in `setUpAll` (see `standards.md`).
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
| `lists/` | `NooGroupedList`, `NooSettingsRow`, `NooTabOrderRow`, `NooBanner`, `NooInfoNote` (tinted info callout; `SettingsSection(notice:)`), `NooSummaryCard`, `NooSelectionBar` |
| `files/` | `NooFileKind` (spec §1.2 tiles; `NooFileKind.from(name:, mimeType:, isDirectory:)`), `NooFileTile`, `NooStatusIcon`/`NooSyncStatus`, `NooFileRow` (mobile 64px), `NooFileTableHeader`/`NooFileTableRow` (desktop), `NooSwipeAction` |
| `media/` | `NooGridCard`, `NooPhotoTile` (video badge, selection), `NooPhotoGroupHeader`/`NooPhotoGrid` (sliver, or `.box`), `NooActivityItem`, `NooStatCard` |
| `nav/` | `NooBottomBar`, `NooTopBar` (a `PreferredSizeWidget`) with `NooTopBarButton`/`NooTopBarBack`, `NooDrawer` with its `Account`/`Storage`/`Item`/`Link` parts, `NooSidebar` with `NooSidebarItem`/`Divider`/`Account`/`Storage`, `NooToolbar` (floating rounded card with margin; `NooToolbar.outerHeight` for `appBar` sizing) |
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
- `NooSwipeAction` reveals its action on a normal swipe (tap the block to
  trigger it) but also fires it directly if the drag goes far enough (past
  1.8x the block's width) before release - a full swipe-through does delete
  in one gesture, it's not tap-only anymore.
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
- Hidden files and external storage are each a three-way segmented row
  (`HiddenFilesFilterRow`/`StorageScopeRow`, `lib/widgets/filter_mode_rows.dart`,
  in both the Files and Photos filter sheets), not toggles:
  `HiddenFilesFilter` hide (default) / only / include, and `StorageScope`
  cloud (default) / external / all. Files and Photos each persist their own
  hidden filter (`ui_hidden_filter`, `ui_hidden_filter_photos`; the old
  `ui_show_hidden*` bools are still read as a fallback, `true` → include);
  `StorageScope` stays shared. Leaving `hide` is still behind the
  hidden-files lock gate. With `StorageScope.all`, Files splits the listing:
  regular items first, then a collapsible "External storage" section
  (`_ExternalStorageHeader`, local `_externalExpanded` state, default open)
  holding the external ones; Photos/Favorites just merge them into one list.
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
  `tab_state_slivers.dart` also has `topBarSliver`, which every regular
  tab's view uses to plant its own `AppTopBar` instance as the first sliver
  in its `CustomScrollView` (a thin wrapper around the framework's
  `SliverFloatingHeader`) instead of the shell passing one shared instance
  to `Scaffold.appBar` - see its doc comment and `architecture.md`'s
  "Mobile" bullet for why.
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
- Upload FAB size: `SettingsController.fabStyle` (`FabStyle.auto/mini/expanded`,
  Settings > Appearance > "Upload button") drives `NooFab.collapsed` in
  `main.dart` - auto collapses off Files/Photos, mini always icon-only,
  expanded always labelled. Phone/Android layout only.
- PDF viewer (`media_pdf_preview.dart`): pdfx's InteractiveViewer won't zoom
  out past `viewport.height / doc.height`, so for short documents (<= 3
  pages, measured up front) the full-size `PdfViewPinch` is wrapped in a
  `MediaQuery` with extra bottom padding (pdfx's child is a `SafeArea`) so
  the boundary height reaches the viewport and fit-width stays reachable
  after pinch-zooming, without shrinking the canvas. `topInset` (status bar
  + top bar height, 0 when the controls are hidden) animates the viewport
  below the overlaid top bar.
- `NooGroupedList.notice`: optional widget (e.g. `NooInfoNote`) rendered
  under the label, above the card; `SettingsSection` uses it for its
  `notice` on phones.
- [`MediaDetailsPanel`](../../lib/widgets/viewer/media_details_panel.dart) —
  the media viewer's bottom bar as a draggable panel (mobile/phone only;
  tablet-class still uses the `DetailsSheet` dialog). Dragging the bar, the
  Details button, or swiping up on swipeable media (raw `Listener` in
  `file_viewer_screen.dart`) grows it upward so the action row rides on top
  of the details; tapping the media collapses it.
- `SettingsController.bottomBarOpacity`/`bottomBarBlur` and
  `lib/widgets/floating_bottom_bar.dart`/`media_grid_tile.dart`/
  `swipeable_item.dart`/`sync_status_badge.dart`/`selectable_thumbnail.dart`
  are gone: the bottom bar is now the flat, non-blurred `NooBottomBar` (no
  opacity/blur knob - flat surfaces per the design system), grid tiles are
  `NooGridCard`, swipe actions are `NooSwipeAction`, and per-item sync
  status is `NooFileRow`/`NooFileTableRow`'s built-in `NooStatusIcon` list
  instead of a corner badge. `NooBottomBar` later gained its own, unrelated
  `NooBottomBarStyle.floating` (Settings → Appearance → "Bottom bar") -
  don't confuse the two: this one is still non-blurred, just inset with a
  `line` border and `nooDialogShadow` (the app's one other shadow user - see
  that constant's doc comment) instead of edge to edge (no opacity/blur knob
  either). `floating` ignores `NooNavStyle` and always uses the Android row
  (icon-only idle tabs, sliding pill, 64px), so iOS matches Android there;
  only the attached bar still has a distinct iOS row. A separate, orthogonal
  `SettingsController.bottomBarFrosted` toggle (Settings → Appearance →
  "Frosted glass bottom bar", off by default, both platforms and both bar
  styles) swaps the bar's solid `surface` for a 0.72-alpha one over a
  20-sigma `BackdropFilter` (same sigma as `FrostedGlassContainer`) and drops
  `nooDialogShadow` (it would show through the glass). A frosted bar only
  reads as glass with content behind it, so the shell uses
  `NooBottomBar.drawsBehindBody(barStyle, frosted)` for `extendBody`, and
  `bottomBarClearance` (and Files' own trailing sliver) reserve the bar's
  footprint for attached+frosted too, not just floating. The host `Scaffold` needs `extendBody: true` while it's active
  (`main.dart` already wires this off `SettingsController.bottomBarStyle`),
  which also means every tab's own scrollable list has to reserve enough
  bottom padding to clear the bar - nothing does that automatically once the
  body draws behind it. Use `bottomBarClearance(context)`
  (`tab_state_slivers.dart`) for that rather than a flat `100`; it already
  accounts for both bar styles.
  Settings' separate "Search in bottom bar" toggle
  (`SettingsController.searchInBottomBar`) adds a never-highlighted Search
  entry to either bar style (`NooBottomBar`'s `searchDestination`/
  `onSearchTap`) and lowers `SettingsController.maxVisibleTabs` by one -
  use that getter, not `defaultMaxVisibleTabs` from `models/app_tab.dart`,
  anywhere that needs the *current* cap on regular tabs.
- `SettingsController.navMenuStyle` (`NooNavMenuStyle.drawer`/`avatarMenu`,
  Settings → Appearance → "Navigation menu") picks what opens hidden tabs +
  Settings on mobile: the original hamburger-opens-`AppDrawer` pattern, or
  the avatar button opens [`showAvatarMenu`](../../lib/widgets/avatar_menu.dart)
  instead. Wired through `AppTopBar`→`NooTopBar.onMenu` (null in `avatarMenu`
  mode - no menu icon renders at all, see `NooTopBar`'s `lead` logic) and
  `ShellAvatarButton`'s new `onTap`/`label` overrides (`shell_common.dart`) -
  a caller passing a custom `onTap` *must* also pass a matching `label`, or
  the tooltip/semantics still say "Accounts" for a button that no longer
  opens the account switcher. In `avatarMenu` mode `main.dart` also sets
  `Scaffold.drawerEnableOpenDragGesture: false` so the edge swipe can't open
  the drawer. The menu header has a chevron that expands an account section
  (other saved accounts to switch to, "Add Account", "Manage Accounts")
  above the hidden tabs/Settings. `showAvatarMenu` is this app's first use of
  `showGeneralDialog` directly (`barrierColor: Colors.transparent` +
  `barrierDismissible: true` for a non-dimming click-outside-to-close menu,
  not a modal flow) - there's no existing anchored-popup primitive here
  (`PopupMenuButton`'s own width doesn't stretch to a full content column),
  so don't reach for `showNooSheet`/`showNooDialog` for something shaped
  like this. It's positioned just past the status bar (`SafeArea`'s own
  inset, not the top bar's full height on top of that) so it covers the
  top bar - including the tab title - rather than sitting below it, and
  its card carries two stacked `boxShadow`s rather than just
  `nooDialogShadow` alone: that one shadow's blur is wide and soft enough
  to read as basically invisible on a small card over a dark theme's
  near-black `bg` (a dark, diffuse shadow needs real density close to the
  edge to be visible against an already-dark backdrop), so a second,
  tighter, more opaque contact shadow underneath it gives real elevation
  in both themes. The card's border can go missing wherever an opaque row
  sits against it too (every corner but the header's, which has no
  full-bleed fill of its own) if a `Container` combines `border` with its
  own `clipBehavior` - that paints the border as part of the *outer*
  decoration, then the clipped child on top right up to the same boundary,
  with no gap for the border's own stroke to show through. Fixed the same
  way any bordered-and-clipped `Container` should be: no `clipBehavior` on
  the bordered `Container` itself, and a 1px-inset `ClipRRect` (radius
  reduced by that same 1px) around the filled, clipped content instead, so
  it never paints over the border. Also added
  `NooTopBar.androidTitleTrailing`: Android has no large title to put a
  second search row under the way iOS's `search:` slot does, so an inline
  search bar (`AppTopBar` passes a plain `ShellSearchLauncher()` when
  search isn't in the bottom bar) sits to the title's own right in that
  flexible slot - `Flexible`, not `Expanded`, so the title still shrinks/
  ellipsizes if there's truly no room but doesn't claim more than it needs
  otherwise - instead of the title being replaced by it.
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

## Text/markdown viewer

`MediaTextPreview` is an editable monospace `TextField` padded clear of the status bar, top bar and action bar; a Save button appears when dirty (read-only for offline copies). `NooPersonAccessRow.trailing` replaces the owner label/permission pill (used by share-search results). Sheets whose close button lives in `showNooSheet` children must pop via a `Builder` context, not the caller's.

`showNooSheet` insets its body by the keyboard (`viewInsets.bottom`) so focused fields stay visible; the body's widget structure must not change when the keyboard opens, or the sheet content is rebuilt and loses focus.

Markdown files (`.md`/`.markdown`) in `MediaTextPreview` open rendered via `flutter_markdown_plus` (`Markdown`, styled from Noo tokens in `_markdownStyle`), with a top-right Edit/Preview toggle (hidden for read-only offline copies). Other text files go straight to the editor.

`ShareSheet`: focusing the people search field does not scroll; once the user types, `_revealPeopleSection` animates the "Share with people" section (keyed by `_peopleKey` on the `NooShareSection`, not the inner column) to just below the sheet's top edge with a small gap.

## Desktop/tablet layout notes

- The desktop branch in `main.dart` is wrapped in `SafeArea` so tablets keep
  system bars clear of the sidebar; the sidebar has no divider between pinned
  and hidden tabs.
- Desktop Settings is the same two-level menu as mobile (centered 640px column, back button in the floating toolbar); the
  pushed category screens render the desktop card layout.
- Settings that don't apply in wide-tablet (Appearance nav options,
  Swipe on a file) show a `NooInfoNote` via `SettingsSection.notice`.
- Mobile-layout grids (Files, Favorites, move/copy picker, share upload,
  Photos) take their column count from `NooLayout.gridColumns` (min tile
  width, never below the phone count), so a tablet in portrait gets more
  columns rather than a few huge tiles.
