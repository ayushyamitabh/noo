# Noo Design System

Noo is a Nextcloud client for iOS, Android, macOS and Windows. ("Noo" is a placeholder name.)
Its visual language is warm neutrals with one violet accent, flat surfaces, pill-shaped controls, and no gradients.

**Platform rule:** keep one visual language everywhere. Adapt only the navigation chrome (status bar, top bar, bottom bar, window controls) to each platform. Content components look the same on every platform.

Reference files in this project:
- `Noo Screens.dc.html` has every screen on every platform, in light and dark.
- `Noo Design System.dc.html` is the visual component sheet.
- `noo-kit.js` holds the tokens (`TH`), the icon set (`SVG`/`ic`), file-type mapping (`KIND`) and mock data.
- `Mobile Screen.dc.html` and `Desktop Screen.dc.html` are the reference builds for each screen.

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
- Shows only on Files and Photos.

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
- Trash: an info icon, the retention text, and "Empty trash" as a danger text button.
- Offline: the stat, a 6px progress bar, the last-sync meta, and a "Sync now" tonal button.

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
| Bottom bar | Surface fill, 1px top line. Icon 24 above a 10px label. Active: accent-text. Idle: fg-3. 34px home indicator below. | Surface fill, 80px. The active icon sits in a 56×32 accent-soft pill with a 12px label. 20px gesture bar below. |
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
- **Photos:** type chips (All, Photos, Videos, Camera), then the photo grid grouped by month. The grid view is the only view.
- **Favorites:** a file list with a star as the trailing icon.
- **Offline:** a summary card (or 4 stat cards on desktop), then a list whose rows show sync status icons and status meta.
- **Shares:** a segmented control (With you, By you, Links), then a list. The meta reads "Owner · Permission".
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
  8. Swipe on a file

  Mobile uses one column of grouped lists. Desktop uses a 2-column grid of cards with a 1px line and radius 20.
- **Share sheet / dialog:** sections in this order:
  1. Header: file tile, name, size · folder, and close.
  2. **Share with people:** an input ("Name, email or group"), then the people with access. The owner comes first; the others each have a permission pill ("Can edit ▾").
  3. **Share link:** a toggle, then the URL field in mono with a primary "Copy link" button, then option chips (permission, expiry, password, allow download).
  4. **Send file directly:** an outline button, with a caption saying that link settings don't apply.

---

## 5. Copy
- Use plain, active and short sentences, under 15 words. Say "you".
- Name the problem and the fix: "Couldn't sync · Tap to retry", not "An error occurred".
- Use sentence case everywhere and no all-caps. Use a middle dot ( · ) to separate meta values.
- Don't use emoji in the product UI.
