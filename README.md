# Noo

A fast, native [Nextcloud](https://nextcloud.com) client built with Flutter
and Material You.

Noo gives you a clean, modern way to browse and manage the files on your own
Nextcloud server — files, photos, shares, activity, and trash, all in one
app, themed to match your device.

## Features

- **Files** — browse, upload, move, rename, delete, and favorite files and
  folders; sort and filter per folder
- **Photos** — a dedicated media gallery with a full-screen viewer for images
  and video
- **Activity** — a feed of what's changed on your server
- **Shares** — see and manage what you've shared and what's shared with you
- **Trash** — restore or permanently delete recently removed items
- **Material You theming** — dynamic color on supported devices, five
  built-in accent colors, light/dark/AMOLED
- **Secure sign-in** — authenticates via Nextcloud's Login Flow v2: you sign
  in through your browser, and Noo never sees or stores your password,
  only a scoped app token

## Screenshots

_Coming soon._

## Getting started

Prerequisites:

- [Flutter](https://docs.flutter.dev/get-started/install) (SDK `^3.12.2`)
- A Nextcloud server with Login Flow v2 enabled (on by default since
  Nextcloud 15)

```bash
flutter pub get
flutter run
```

On first launch, enter your server's address — Noo opens your browser to
finish signing in.

## Supported platforms

Android, iOS, and Windows.

## Building

```bash
flutter build apk       # Android
flutter build ios       # iOS
flutter build windows   # Windows
```

## Tech stack

Flutter with Material 3, [`provider`](https://pub.dev/packages/provider) for
state management, and `http`/`dio` talking directly to Nextcloud's WebDAV
and OCS APIs — no bundled Nextcloud SDK.

## Contributing

Project context for contributors (human or AI) lives in
[`CLAUDE.md`](CLAUDE.md) and `.claude/context/` — architecture, the server
integration, styling conventions, and code standards.

```bash
flutter test      # run tests
flutter analyze   # static analysis / lints
```

## License

Not yet licensed for redistribution — license TBD.
