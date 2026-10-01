# Demo server for Play Store screenshots

`tool/screenshots.sh` takes the Play Store screenshots against a **throwaway
Nextcloud that only contains fake data**, so nothing real can appear in them.
This folder is that server:

- `docker-compose.yml` - a single Nextcloud container (SQLite, nothing
  persisted; `docker compose down -v` wipes it).
- `seed.py` - creates the users and fills them with invented content: landscape
  "photos" drawn with Pillow, tiny generated PDFs, made-up documents, favorites,
  shares (to a second user and a public link), trash, a filler file for the
  storage quota, and edits by a second user so the Activity feed has more than
  one author. It ends by printing `APP_PASSWORD=...` - an app password for the
  demo user, so the app can start logged in without the browser login step.

## Running it

Most of the time just run the whole pipeline from the repo root:

```bash
bash tool/screenshots.sh
```

(Git Bash is fine on Windows.) You need **Docker**, **Python 3**, **Flutter**
and an **Android SDK** (`ANDROID_HOME`). Pillow and `requests` are installed
into `tool/demo_server/.venv` automatically if your Python lacks them. The
script installs the emulator and a system image through `sdkmanager` on first
use. Options (`HEADLESS=1`, `DEMO_PORT`, `DEMO_HOST`, `KEEP_SERVER=1`,
`ANDROID_SERIAL`, ...) are documented at the top of the script.

To poke at the server yourself:

```bash
docker compose -f tool/demo_server/docker-compose.yml up -d
python3 tool/demo_server/seed.py          # prints APP_PASSWORD=...
# browse http://localhost  (Alex / alex-demo-pass, admin / demo-admin-password)
docker compose -f tool/demo_server/docker-compose.yml down -v
```

`python3 tool/demo_server/seed.py --generate-only DIR` writes the generated
files to `DIR` without any server - handy for previewing the fake content.

## Before you upload

Look at every image. The known places where real data could still show up:
the server address and username (sync header panel, Settings > Accounts), the
avatar initial, notification icons in the status bar, and anything left over
from a previously used emulator profile (the script always wipes its own).
