# Noo Design System

Noo is a Nextcloud client for iOS, Android, macOS and Windows. ("Noo" is a placeholder name.)
Its visual language is warm neutrals with one violet accent, flat surfaces, pill-shaped controls, and no gradients.

**Platform rule:** keep one visual language everywhere. Adapt only the navigation chrome (status bar, top bar, bottom bar, window controls) to each platform. Content components look the same on every platform.

Reference files in this project:
- `Noo Screens.dc.html` has every screen on every platform, in light and dark.
- `Noo Design System.dc.html` is the visual component sheet.
- `noo-kit.js` holds the tokens (`TH`), the icon set (`SVG`/`ic`), file-type mapping (`KIND`) and mock data.
- `Mobile Screen.dc.html` and `Desktop Screen.dc.html` are the reference builds for each screen.
- [Noo — Missing Screens](https://claude.ai/artifact/3AGPqqMdkLSC2ypCh2CQs4) is a live design canvas (Claude Design, not a static file in this repo) covering pieces this doc originally had no recipe for: Media viewer, Search, the Upload/Move/Copy destination picker, the Details sheet's tab switch, and the Selection action bar (mobile + desktop). It has both an iOS row (built first, ready for later) and an Android row (built to match right now) - same content, chrome adapted per the platform rule above. §4 below is the written-up version of what's approved there; go back to the canvas for pixel-level layout, not just the summary.

---

## 1. Tokens

### 1.1 Color (semantic). Use these names in code.

| Token | Role | Light | Dark |
|---|---|---|---|
| `bg` | App background, desktop sidebar | `#F3EFE6` warm off-white | `#0E0D0B` |
| `surface` (`sf`) | Cards, rows, bars, sheets, desktop main pane | `#FFFFFF` | `#25241F` |
| `surface-2` (`sf2`) | Inputs, inset panels, secondary buttons | `#F6F5F2` | `#3D3C38` |
| `surface-3` (`sf3`) | Progress tracks, toggle off, grabbers | `#EAE8E2` | `#5A5852` |
| `line` (`ln`) | Dividers, 1px borders | `#EAE8E2` | `#3D3C38` |
| `fg-1` | Primary text | `#0E0D0B` | `#F3EFE6` |
| `fg-2` | Secondary text, idle icons | `#5A5852` | `#BDBAB1` |
| `fg-3` | Meta text, placeholders, trailing icons | `#7C7A72` | `#9E9B92` |
| `accent` (`ac`) | Primary fills (buttons, FAB, toggle on, progress) | `#8D0DE3` | `#8D0DE3` |
| `accent-text` (`act`) | Accent text and icons, active nav | `#8D0DE3` | `#CBA5FD` |
| `accent-soft` (`acs`) | Selected and active backgrounds, tonal buttons | `#ECDFFF` | `#2F0454` |
| `danger` / `danger-soft` | Destructive text / bg | `#A8202A` / `#FDE7E7` | `#F49E9E` / `#560F18` |
| `danger-fill` | Swipe-delete background (white text) | `#A8202A` | `#A8202A` |
| `success` / `success-soft` | Synced, connected | `#3E7A23` / `#EAF5DF` | `#B7DD9F` / `#1E3F10` |
| `warning` / `warning-soft` | Video file type | `#8C5A0E` / `#FBEFD0` | `#F0C26C` / `#4A3208` |
| `info` / `info-soft` | Docs, images | `#2940A8` / `#E6ECFE` | `#B6C3FB` / `#1C2B73` |
| `scrim` | Behind sheets, drawers, dialogs | `rgba(14,13,11,.45)` | `rgba(0,0,0,.6)` |

Rules:
- Text on `accent` is always `#FFFFFF`. Accent-colored text uses `accent-text`, never `accent` in dark mode.
- On-color text always uses the matching pair: `accent-text` on `accent-soft`, `danger` on `danger-soft`, and so on.
- Don't use gradients. Don't add new colors. Avatar and photo placeholder fills use the secondary palette: `#8DCDE2 #96B0FD #E5D8BD #EEEDB3 #DA9AC7 #A7D296 #E9A6A7 #85D1BD #CBA5FD`, always with `#0E0D0B` text.

### 1.2 File-type tiles (`KIND`)
| Kind | Background | Icon color | Lucide icon |
|---|---|---|---|
| folder | accent-soft | accent-text | `folder` |
| pdf | danger-soft | danger | `file-text` |
| doc / text | info-soft | info | `file-text` |
| sheet | success-soft | success | `sheet` |
| video | warning-soft | warning | `film` |
| image | info-soft | info | `image` |
| archive | surface-3 | fg-2 | `file-archive` |

Tile sizes: 40px/r12 for mobile rows, 30px/r9 for desktop rows, 44px/r12 for the share header, 32px/r10 for activity. The icon is half the tile size (20, 16, 24, 16).

### 1.3 Typography
Fonts (Google Fonts): **Schibsted Grotesk** for headings (weights 500/600) and **Instrument Sans** for UI (weights 400/500/600). Load them with `https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;500;600&family=Schibsted+Grotesk:wght@500;600&display=swap`. Don't use italics, all-caps or wide tracking.

| Style | Font | Size / line-height | Tracking | Use |
|---|---|---|---|---|
| Large title | Schibsted 600 | 34 / 0.9 | −3% | iOS large title |
| Stat | Schibsted 600 | 32 (mobile) · 28 (desktop) / 0.9 | −3% | Offline GB, counters |
| Title | Schibsted 500 | 22 / 1 | −2% | Android top bar, desktop toolbar |
| Card title | Schibsted 500 | 17–20 / 1 | −2% | Settings cards, sheet sections, account name |
| Group heading | Schibsted 500 | 18 / 1 | −2% | Photos month |
| Body L | Instrument 400/500 | 16 / 1.2 | 0 | Mobile row title, settings label |
| Body | Instrument 400/500 | 14–15 / 1.3 | 0 | Desktop rows, activity text, banners |
| Label | Instrument 600 | 13 / 1 | 0 | Section labels (fg-2), chips, table headers (12, fg-3) |
| Meta | Instrument 400 | 13 (mobile) · 12–13 (desktop) / 1.2 | 0 | Size · date, subtitles (fg-3) |
| Nav label | Instrument 500 / 600 (active) | 12 Android · 10 iOS | 0 | Bottom bars |
| Button | Instrument 600 | 14–16 / 1 | 0 | All buttons |
| Mono | ui-monospace 400 | 13–14 | 0 | Share URLs, local paths |

### 1.4 Space, radius, elevation, motion
- **Spacing** uses a 4px base: 4, 8, 12, 14, 16, 20, 24, 32. Mobile screen gutter is **12px** (cards) and 16px (bars). Desktop content gutter is **24px**.
- **Radius:**
  - pills (`999px`) for every button, chip, segmented control, toggle, search field and badge
  - 20px for cards and grouped lists
  - 18px for grid cards and stat cards
  - 14px for inputs and inset panels
  - 12px for desktop sidebar items and selected table rows
  - 28px for the sheet top and drawer edge
  - 24px for desktop dialogs
  - screen corners are 48 on iOS and 36 on Android
- **Elevation:** product UI is flat, with no shadows on buttons or cards. The only shadow is `0 24px 48px rgba(30,0,47,.14)`, and only on floating desktop dialogs. Separate things by surface color, not by shadow.
- **Motion:** use `cubic-bezier(.7,0,.15,1)` with durations of 180, 280 and 480ms. Nothing bounces. Pressing a button scales it to 0.98.

### 1.5 Icons
Use **Lucide** (pinned to `lucide-static@0.460.0`) at a 1.8 stroke. Sizes are 14, 16, 18, 20, 24 and 32. Icons render in the current text color. Tab icons: Files `folder`, Photos `images`, Favorites `star`, Offline `hard-drive-download`, Shares `share-2`, Recent `clock`, Activity `activity`, Trash `trash-2`, Settings `settings`.

---

## 2. Components

**Button**
- Always a pill. Heights: 52 (sheet CTA), 44 (mobile card), 40 (inline in a field), 36 (desktop toolbar), 28–32 (compact).
- Variants:
  - *Primary*: accent fill, white text.
  - *Tonal*: accent-soft fill, accent-text.
  - *Secondary*: surface-2 fill, fg-1.
  - *Danger*: danger-soft fill, danger text.
  - *Outline*: 1.5px surface-3 border.
- An icon goes on the left, with a 6–10px gap.

**FAB** (Android only)
- An extended pill: 56px tall, accent fill, labelled "Upload".
- Sits 16px from the right and bottom edges of the content area.
- Stays mounted on every tab; it's only the extended label that's tied to
  Files/Photos. Elsewhere it collapses to an icon-only 56px circle (still
  tappable - it always targets the Files tab's current folder), animating
  the width/label change rather than the button popping fully in/out as
  the Scaffold's default FAB transition would on every tab switch.

**Chip**
- A pill, 32–34px tall, 12px horizontal padding, Label 13–14.
- Idle: surface fill on mobile, or a 1px line border on desktop.
- Selected: accent-soft fill with accent-text.
- A trailing `chevron-down` means it opens a menu. A trailing `x` means it's an active filter.

**Segmented control**
- A pill track (surface or surface-2) with 3px padding.
- The active segment gets an accent-soft fill with accent-text at weight 600. Idle segments use fg-2 at weight 500.
- Use it for the List/Grid toggle (icons only, 36×28), Shares scope, Theme, and default view.

**Toggle**
- 48×28 on mobile, 44×26 on desktop, with a white knob 3px inset.
- On: accent track. Off: surface-3 track. It looks the same on every platform.

**Search field**
- A pill (radius 12 on the iOS inline field), 36–38px tall.
- Surface fill on bg, or surface-2 fill on surface. Leading search icon and placeholder in fg-3.
- Placement:
  - iOS: below the large title.
  - Android: an icon in the top bar that expands.
  - Desktop: 260px wide in the toolbar.

**Grouped list (card)**
- A surface card with radius 20 and 1px gaps showing `line`, which draws the dividers.
- An optional group label above it: 13/600 in fg-2, inset 8px.
- Each group is 18px from the next.

**File row**
- Mobile: 64px tall.
  - Left to right: tile 40, then a column with the name (16/500, one line, ellipsis) above a meta line (13, fg-3), then optional trailing icons, then the overflow menu (`ellipsis` on iOS, `ellipsis-vertical` on Android).
  - The meta line is `[status icon][shared icon] size · modified`.
  - A favorite shows an accent-text star before the overflow menu.
  - Trailing icon by screen: star in Favorites, `rotate-ccw` in Trash.
- Desktop: a table row 52px tall.
  - Columns are `minmax(0,1fr) 180px 160px 120px`: Name, two data columns, then status icons and the overflow menu.
  - The header row is 36px, 12/600 in fg-3, with a sort arrow on the active column.
  - A selected row gets an accent-soft fill with radius 12.

**Status icons (14px)**
- Synced: `circle-check` in success.
- Syncing: `refresh-cw` in accent-text.
- Error: `circle-alert` in danger, and the meta text says what to do ("Couldn't sync · Tap to retry").
- Shared: `users` in fg-3.

**Swipe action**
- The row slides and uncovers a 96px action block. Delete is white on danger-fill; Favorite is white on accent.
- The block has a 20px icon above a 12/600 label.
- Swipe actions are set in Settings → Swipe on a file.

**Selection action bar** (Files, Photos, Favorites - anywhere with
multi-select)
- Replaces that screen's own sort/filter row in place while selecting -
  never a second bar stacked underneath it, and never the shell's own top
  bar/toolbar, which don't change for selection.
- A `surface` card, radius 20, in the screen's usual gutter (12 mobile, 24
  desktop) - selection reads as a distinct mode, not a bare row of buttons
  on `bg`.
- Left to right: a 36px `surface-2` close circle (`x`), then "N selected"
  (17/500), then the bulk actions, trailing-anchored. Fixed width, never
  scrolls: only the first few actions show inline (3 on mobile, 4 on
  desktop - there can be up to 9: favorite, share, download, delete, copy,
  move, rename, sync, details); the rest sit behind a trailing "More"
  button that opens the same grouped-list sheet a file row's own overflow
  menu (`ellipsis`/`ellipsis-vertical`) already uses. Which actions land in
  the inline slots vs. "More" is the user's own priority order (Settings
  → Action bar, §4's 9-part list), not a fixed per-kind assignment.
- Mobile: inline actions are plain 20px accent-text icons, no fill; "More"
  is the same 40px `NooOverflowButton` treatment (`ellipsis`/
  `ellipsis-vertical`, fg-3) file rows use for their own overflow menu.
- Desktop: inline actions are labelled tonal pills (accent-soft/
  accent-text), danger-soft/danger for the one labelled "Delete" - desktop
  has the room for labels, and the app's other toolbar actions are already
  labelled buttons rather than bare icons. "More" is a secondary pill
  (surface-2/fg-1) with a trailing `chevron-down`, so it reads as "opens a
  menu" rather than another bulk action.

**Grid card**
- Surface fill, radius 18. Mobile uses 2 columns with a 10px gap; desktop uses 5 columns with a 16px gap.
- The thumbnail area is 104–118px tall, filled with the file-type soft color and a 32px icon. Real thumbnails replace it when they exist.
- Below it: the name (14/500) with an overflow menu, then the meta (12).

**Photo grid**
- Square tiles with a 2px gap on mobile (3 columns, edge to edge) and a 4px gap on desktop (8 columns).
- Tiles are grouped by month, with the group heading on the left and the count on the right.
- Videos get a badge in the bottom-right: a `play` icon and the duration on `rgba(14,13,11,.7)`.

**Activity item**
- Avatar 36 (initials on a secondary-palette color), then a sentence: **Actor** verb **object** tail.
- Time in meta style. The file tile (32) goes on the right.

**Banner / summary card**
- A surface card with radius 20 (surface-2 on desktop) and padding of 14–18.
- The action sits on its own row below the description text, not squeezed
  onto the same line - a long retention message/caption and the action
  used to fight for the same row's width.
- Trash: an info icon, the retention text, then "Empty trash" as a
  right-aligned danger text button on the row below.
- Offline: the stat and caption, then a "Sync now" tonal button on the row
  below, then the 6px progress bar and the last-sync meta.

**Progress bar**
- 6px tall pill. Surface-3 track with an accent fill.
- Used for storage quota, cache use and the offline limit.

**Avatar**
- A circle with initials, weight 600, at 0.36× the avatar size.
- Sizes: 30–32 in bars, 36 in lists, 48 in the drawer, 52–56 on the account card.
- The current user gets an accent-soft fill with accent-text.

**Settings row**
- 52px tall, or 60px with a subtitle.
- Left to right: an optional 20px icon in fg-2, then the label (16) with an optional subtitle (13, fg-3), then a trailing control.
- Trailing control is one of: a toggle, a value in fg-3 with a chevron (desktop uses a 32px dropdown with radius 10), a segmented control, a pill button, or a status badge.
- A destructive row uses danger text.
- Exception: a segmented control with 3+ labelled segments (Theme's
  System/Light/Dark) gets its own row below the label instead of a
  trailing slot - three icon+label segments crammed in next to the label
  left each one too cramped to read. Label row, then the full-width
  segmented control on the row below, both on one continuous surface (no
  divider between them) - same shape the sort sheet's Ascending/Descending
  control and Photos' filter-sheet type control already use.

**Tab order row**
- A grip icon (`grip-vertical`, fg-3), the tab icon, the label, then a pin button: a 36px circle (30 on desktop) that is accent-soft with `pin` when pinned, or surface-2 with `pin-off` when not.
- Allow at most 5 pinned tabs.

**Sheet** (mobile)
- Surface fill, radius 28 at the top. A 36×5 grabber in surface-3. Padding 20, with 22px between sections.
- It sits on a scrim.

**Dialog** (desktop)
- 540px wide, radius 24, padding 24, sitting on a scrim.
- Header: file tile, title "Share "<name>"", and a close button (32px circle, surface-2).

**Drawer** (mobile)
- 316px wide, surface fill, radius 28 on the trailing edge, on a scrim.
- Top to bottom:
  - account block with a chevron to switch accounts
  - storage bar
  - "More" label, then the unpinned tabs as 52px pill items (icon 24, label 16/500, trailing count)
  - Settings
  - an "Edit tabs" link at the bottom, in accent-text

---

## 3. Navigation & platform mapping

**Tabs** (the user sets the order): Files, Photos, Favorites, Offline, Shares, Recent, Activity, Trash. Settings is always separate.

### Mobile

Mobile always has **5 pinned tabs in the bottom bar**. The rest go in the drawer, which opens from the top-left menu icon.

| Element | iOS | Android |
|---|---|---|
| Status bar | 54px, Dynamic Island | 40px |
| Top bar | 44px row: `menu` on the left; `plus` and avatar on the right (all accent-text). Then a 34px large title, then the search field. | 64px: `menu`, 22px title, `search`, avatar |
| Bottom bar | Surface fill, 1px top line. Icon 24 above a 10px label. Active: accent-text. Idle: fg-3. 34px home indicator below. | Surface fill, 80px. Icon 24 above a 12px label (label space is always reserved, just invisible when idle, so nothing shifts on selection). The active icon sits inside a 56×32 accent-soft pill that slides between tabs as one shared indicator, rather than popping in/out per tab. 20px gesture bar below. |
| Bottom bar - floating (Settings → Appearance → "Bottom bar", both platforms) | Same content, inset 16px from both side edges and clear of the bottom safe area instead of edge to edge, radius 28 (the sheet-top/drawer-edge radius) rather than square corners. No shadow (product UI stays flat - see 1.4); a 1px `line` border stands in for elevation instead. Row height drops slightly (64/72 vs 50/80) to suit. Android's idle tabs drop their reserved label space in this mode - the icon just centers in the button and renders a touch bigger (27 vs 24px) - rather than sitting high with a gap held open under it. `Scaffold.extendBody: true` while floating, so the body scrolls behind the bar's transparent margin instead of stopping short of it. |
| Upload | `plus` in the nav bar | Extended FAB |
| Overflow icon | `ellipsis` | `ellipsis-vertical` |
| Settings | Pushed screen with a "‹ Files" back button and a large title. No bottom bar. | Pushed screen with a back arrow and a title. No bottom bar. |
| Biometric label | "Lock with Face ID" | "Lock with fingerprint" |

### Desktop

Desktop has a 256px sidebar in `bg` and a main pane in `surface`, separated by a 1px line.

**Sidebar**, top to bottom:
- account switcher card
- the 5 pinned tabs
- a divider
- the remaining tabs
- a spacer
- the storage meter
- Settings

Sidebar items are 38px tall with radius 12, an 18px icon and a 14/500 label. The active item gets an accent-soft fill with accent-text at weight 600. Counts sit on the right: Trash 12, Offline errors, new shares.

**Toolbar** is 64px tall:
- the title (22px Schibsted Grotesk), with a breadcrumb in Files
- a spacer
- the search field
- context actions: List/Grid toggle and Upload in Files, Upload in Photos, Empty trash in Trash, Sync now in Offline

| Element | macOS | Windows |
|---|---|---|
| Window | Radius 12 | Radius 8 |
| Controls | Traffic lights at the top of the sidebar | 40px title bar with the app mark and name; minimize, maximize and close buttons 46px wide |
| Navigation | Back and forward chevrons at the start of the toolbar | Not shown in the toolbar |
| Biometric | "Touch ID" | "Windows Hello" |
| Local path | `~/Noo/…` | `C:\Users\…\Noo` |
| Swipe setting | "Trackpad swipe on a file" | "Touch swipe on a file" |

---

## 4. Screen recipes

- **Files:**
  - Toolbar: sort chip (`Name ↑`), type filter chip, List/Grid segmented toggle.
  - Desktop adds Modified and Shared filter chips, an active-filter chip, and an item count.
  - Content: a list, or a grid when the toggle is set.
- **Photos:** a sort chip and a filter chip (mirroring Files' own controls
  row - no List/Grid toggle, the grid is the only view). The type filter
  (All, Photos, Videos - Camera isn't backed by real data, see the view's
  doc comment) lives inside the filter sheet as a full-width segmented
  control, the same "label, then the control on its own row below" shape
  Settings' Theme row uses, not its own row of chips. Every icon (All,
  Photos, Videos in the filter sheet; All, Files, Folders in Files' own
  filter sheet, same treatment) always shows; only the *selected* segment
  also shows its label (`NooSegmentedControl`'s `labelOnlySelected`) - the
  same List/Grid-toggle-style pill both screens' filter sheets use, not
  Files' old checkmark list or Photos' own always-labelled track. Then the
  photo grid grouped by month.
- **Favorites:** a file list with a star as the trailing icon.
- **Offline:** a summary card (or 4 stat cards on desktop), then a list whose rows show sync status icons and status meta.
- **Shares:** a segmented control (With you, By you, Links), then a list. The
  meta reads "Owner · Permission". No per-row overflow menu on any of the
  three scopes - tapping a row (file or folder) opens the full Share sheet
  for that item (fetched fresh via `FilesController.fetchItemAtPath`, since
  a share only carries enough metadata for its own row), the same sheet
  Files/Photos open from their own Share action - that's already where
  copying a link or removing access lives, so a second, row-local menu here
  was redundant.
- **Recent:** a list grouped into Today, Yesterday and This week. The meta is the action plus the location.
- **Activity:** the feed grouped by day. Desktop limits it to 760px wide.
- **Trash:** a retention banner, then a list. Mobile rows get a restore icon; desktop rows get a tonal "Restore" pill.
- **Settings:** sections in this order:
  1. Account card
  2. Accounts (list, then "Add account")
  3. Security
  4. File sync
  5. Files cache
  6. Appearance
  7. Tabs
  8. Action bar - a reorder-only list (no pin/hide, unlike Tabs): the
     priority order for the Selection action bar's bulk actions (favorite,
     share, download, delete, copy, move, rename, sync, details) - the
     first few (3 mobile / 4 desktop) land in the bar's fixed inline
     slots, the rest sit behind "More". See §2 "Selection action bar".
  9. Swipe on a file

  Mobile uses one column of grouped lists, each individually collapsible
  (tap its label, expanded by default - `NooGroupedList`'s `collapsible`
  param) so the full list can be collapsed down instead of needing a
  separate way to navigate it; an earlier version had a trailing jump rail
  (one small icon per section, pinned where the scrollbar would sit)
  instead, dropped for adding a second, redundant navigation method without
  shortening the page. Desktop uses a 2-column grid of cards with a 1px
  line and radius 20, wide enough to see most sections without scrolling,
  so it gets neither.
- **Share sheet / dialog:** sections in this order:
  1. Header: file tile, name, size · folder, and close.
  2. **Share with people:** an input ("Name, email or group"), then the people with access. The owner comes first; the others each have a permission pill ("Can edit ▾").
  3. **Share link:** a toggle, then the URL field in mono with a primary "Copy link" button, then option chips (permission, expiry, password, allow download).
  4. **Send file directly:** an outline button, with a caption saying that link settings don't apply.
- **Details sheet:** header (file tile, name, size · folder, close) as in the
  Share sheet above, then a segmented control switching Info/Versions/Activity
  in place below it - there's no separate tab-strip component, so the
  segmented control (already used for List/Grid and the Shares scope) is the
  one that does this job too. Info is a flat label/value list (Size, Type,
  Location, Modified, Created, ...). Versions and Activity reuse their own
  row/feed treatment. Same on every platform - this sheet has no iOS/Android
  split.
- **Media viewer** (the full-screen photo/video viewer): the stage is `bg`,
  following the app's own theme rather than a fixed black - a black stage
  in light mode read as jarringly out of place. A translucent, blurred top
  bar (back, filename, meta) and bottom bar float over the media in a
  `surface`-tinted panel (also theme-following, at a higher opacity than a
  typical blur so it stays legible over arbitrary photo/video brightness
  underneath - icons/text are `fg1`, matching); this is the one deliberate
  exception to "no blur" in product UI, since it's chrome over photo/video
  content, not over the app's own surfaces. A short edge gradient outside
  each panel (toward `surface`, not a fixed black) extends that same
  contrast a little past the panel's hard edge. Both bars' background
  extends edge-to-edge behind the status bar/gesture area, with only their
  content padded clear of it. Back is a plain arrow (`arrow-left`), not the iOS
  chevron+label pushed-screen pattern - platform split still to do. The
  bottom bar holds every action in one row (share, favorite, open
  externally, download, delete, details) on every platform; don't add a
  top-bar overflow menu for the same actions. Video adds a transport row
  above the action row: time · seek bar · time, then play/pause and mute
  centered below it. A photo can be pinch-zoomed; while zoomed in, the
  gallery's own left/right swipe between items is disabled so panning
  around the zoomed photo doesn't also swipe to the next one - it comes
  back the moment the photo returns to its un-zoomed scale. A PDF preview
  stays at its fit-width scale as its floor rather than letting the user
  zoom out past it, since going below 1.0 scale removes any limit on how
  far the page can be panned, including off-screen entirely.
- **Search:** pushed from the shell's search entry point (`menu`/`search`
  icon in the top bar, or the inline field below an iOS large title -
  DESIGN_SYSTEM §2 "Search field" placement). The destination screen is one
  shared recipe for both platforms: back arrow + the pill `NooSearchField`
  (not the inset-panel text-field shape - a search field is always the pill,
  except the one named iOS-inline exception) taking over the top row,
  autofocus, a clear button once there's a query. Below it: a file list
  (mobile rows / desktop table, same as Files), or a centered icon + short
  sentence-case message for the empty ("Search your files") and no-results
  states.
- **Upload / Move / Copy destination picker:** a pushed screen (outside the
  tab shell, so it carries its own complete top bar) titled "Upload to" /
  "Move to" / "Copy to". Back arrow (Android) or "Cancel" text (iOS) leading,
  no trailing action. The same `FilesControlsRow` (sort chip, filter chip,
  List/Grid toggle right-anchored) Files itself uses, then a breadcrumb row,
  then a folder-only list/grid (no files: this screen only browses folders)
  using the standard file row/tile/grid-card at the folder kind. Bottom bar:
  a centered meta line ("Moving 3 items") above a full-width 52px primary
  CTA ("Upload here" / "Move here" / "Copy here") - a count, never a
  filename, even for a single item.

---

## 5. Copy
- Use plain, active and short sentences, under 15 words. Say "you".
- Name the problem and the fix: "Couldn't sync · Tap to retry", not "An error occurred".
- Use sentence case everywhere and no all-caps. Use a middle dot ( · ) to separate meta values.
- Don't use emoji in the product UI.
