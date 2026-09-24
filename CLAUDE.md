# Noo — Nextcloud Client

A Flutter (Material 3) client for Nextcloud: browse files, view photos, check
activity, manage shares/trash. Auth uses Nextcloud's Login Flow v2 — the app
never collects a password directly, only a server address.

Detailed, topic-specific context lives in `.claude/context/`. Read the
relevant file(s) before working in that area rather than loading all of them:

- [`architecture.md`](.claude/context/architecture.md) — folder layout, state
  management, navigation/screen flow
- [`server.md`](.claude/context/server.md) — Nextcloud API/WebDAV
  integration, login flow, session persistence
- [`styling.md`](.claude/context/styling.md) — theming, Material 3
  conventions, fonts, reusable chrome widgets
- [`standards.md`](.claude/context/standards.md) — code style, comment
  conventions, linting, testing
- [`design-system/DESIGN_SYSTEM.md`](.claude/context/design-system/DESIGN_SYSTEM.md)
  — the target visual/component spec (tokens, components, platform
  mapping, screen recipes) for the in-progress UI rework; the sibling
  `.dc.html`/`noo-kit.js` files it references are the visual/token
  reference builds, not something to read directly

## Common commands

```bash
flutter test      # run tests
flutter analyze   # static analysis / lints
```

## Keeping docs current

After making a change that affects architecture, server integration,
styling conventions, or code standards, update the relevant file(s) in
`.claude/context/` in the same session — don't leave documentation to drift
from the code. This applies whether the change is a new feature, a
refactor, or a convention shift (e.g. a new reusable widget, a changed
state-management pattern, a new dependency). If a change doesn't fit any
existing topic file, add a section rather than skipping the update.
