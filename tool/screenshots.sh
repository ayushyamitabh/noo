#!/usr/bin/env bash
# Generates the Play Store screenshots - without any real data.
#
# What it does, end to end:
#   1. starts a throwaway Nextcloud in Docker and fills it with fake data
#   2. creates + boots a clean Android emulator (1080x1920, demo-mode status bar)
#   3. runs integration_test/store_screenshots_test.dart against it, which
#      logs in as the fake user and walks through the app's tabs and states
#   4. leaves flattened, size-checked PNGs in store_listing/screenshots/
#
# Works on Linux, macOS and Git Bash on Windows. Needs: docker, python3,
# flutter, and an Android SDK (ANDROID_HOME / ANDROID_SDK_ROOT). See
# tool/demo_server/README.md.
#
# Options (environment variables):
#   SCREENSHOT_DIR   output directory            (store_listing/screenshots)
#   ANDROID_SERIAL   use this already-running device instead of the emulator
#   HEADLESS=1       run the emulator without a window
#   DEMO_PORT        host port for the demo server (80; anything else shows
#                    up as ":port" in the app's header)
#   DEMO_HOST        show this hostname instead of "localhost" in the app,
#                    e.g. cloud.example.com (best effort - edits the
#                    emulator's hosts file, which needs a rootable image)
#   KEEP_SERVER=1    leave the demo server running afterwards
#   KEEP_EMULATOR=1  leave the emulator running afterwards
#   SCREEN_W / SCREEN_H / SCREEN_DENSITY   emulator screen (1080 / 1920 / 440);
#                    Play needs the long side <= 2x the short side
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

# Git Bash would otherwise rewrite device paths such as /system/etc/hosts.
export MSYS_NO_PATHCONV=1

AVD_NAME="${AVD_NAME:-noo_screenshots}"
API_LEVEL="${SCREENSHOT_API:-36}"
SYSTEM_IMAGE="system-images;android-${API_LEVEL};google_apis;x86_64"
SCREEN_W="${SCREEN_W:-1080}"
SCREEN_H="${SCREEN_H:-1920}"
SCREEN_DENSITY="${SCREEN_DENSITY:-440}"
OUT_DIR="${SCREENSHOT_DIR:-store_listing/screenshots}"
DEMO_PORT="${DEMO_PORT:-80}"
DEMO_HOST="${DEMO_HOST:-}"
export DEMO_PORT DEMO_HOST

log() { printf '\n==> %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Two easy mistakes worth catching up front rather than as a confusing
# "missing prerequisites" list.
if [ "$(id -u)" = 0 ]; then
  die "don't run this as root/with sudo - it would create root-owned files and use root's home for the emulator."
fi
if grep -qi microsoft /proc/version 2>/dev/null; then
  die "this is WSL, which can't see your Windows Flutter/Android SDK (and can't run the emulator well). On Windows run it from Git Bash instead."
fi

# ---------------------------------------------------------------- tooling ---

# Windows env vars hold C:\... paths; convert for bash.
to_unix() { if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; else printf '%s' "$1"; fi; }

SDK_ROOT=""
for candidate in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Android/Sdk" \
  "$HOME/Library/Android/sdk" "${LOCALAPPDATA:-}/Android/Sdk"; do
  if [ -n "$candidate" ] && [ -d "$(to_unix "$candidate")" ]; then
    SDK_ROOT="$(to_unix "$candidate")"
    break
  fi
done

# Finds a tool by name on PATH or in the SDK, including Windows .bat/.exe.
find_tool() {
  local name="$1" dir ext
  for ext in "" .bat .exe; do
    if command -v "$name$ext" >/dev/null 2>&1; then command -v "$name$ext"; return 0; fi
  done
  for dir in "$SDK_ROOT/cmdline-tools/latest/bin" "$SDK_ROOT/platform-tools" "$SDK_ROOT/emulator"; do
    for ext in "" .bat .exe; do
      if [ -x "$dir/$name$ext" ]; then printf '%s' "$dir/$name$ext"; return 0; fi
    done
  done
  return 1
}

missing=()
require() { # <command> <how to get it>
  command -v "$1" >/dev/null 2>&1 || missing+=("$1  -  $2")
}
require docker "install Docker (Desktop on Windows/macOS)"
require flutter "install Flutter and put it on PATH"
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || missing+=("python3  -  install Python 3")
ADB="$(find_tool adb || true)"
[ -n "$ADB" ] || missing+=("adb  -  install Android platform-tools (or set ANDROID_HOME)")
if [ -z "${ANDROID_SERIAL:-}" ]; then
  SDKMANAGER="$(find_tool sdkmanager || true)"
  AVDMANAGER="$(find_tool avdmanager || true)"
  [ -n "$SDKMANAGER" ] && [ -n "$AVDMANAGER" ] ||
    missing+=("sdkmanager/avdmanager  -  install the Android cmdline-tools (or set ANDROID_HOME)")
fi
if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Missing prerequisites:\n' >&2
  printf '  - %s\n' "${missing[@]}" >&2
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  DC=(docker compose)
else
  DC=(docker-compose)
fi
DC+=(-f tool/demo_server/docker-compose.yml)
adb() { "$ADB" "$@"; }

# Python with Pillow + requests: use the system one if it has them, else a
# local virtualenv (tool/demo_server/.venv, gitignored).
if ! "$PY" -c 'import PIL, requests' >/dev/null 2>&1; then
  log "Setting up a Python virtualenv (Pillow, requests)"
  "$PY" -m venv tool/demo_server/.venv
  if [ -x tool/demo_server/.venv/bin/python ]; then
    PY="$REPO_ROOT/tool/demo_server/.venv/bin/python"
  else
    PY="$REPO_ROOT/tool/demo_server/.venv/Scripts/python"
  fi
  "$PY" -m pip install -q -r tool/demo_server/requirements.txt
fi

# ---------------------------------------------------------------- cleanup ---

STARTED_EMULATOR=0
EMULATOR_PID=""
cleanup() {
  local code=$?
  set +e
  if [ -n "${SERIAL:-}" ]; then
    adb -s "$SERIAL" shell am broadcast -a com.android.systemui.demo -e command exit >/dev/null 2>&1
    adb -s "$SERIAL" reverse --remove-all >/dev/null 2>&1
  fi
  if [ "$STARTED_EMULATOR" = 1 ] && [ "${KEEP_EMULATOR:-0}" != 1 ]; then
    adb -s "$SERIAL" emu kill >/dev/null 2>&1
  fi
  if [ "${KEEP_SERVER:-0}" != 1 ]; then
    "${DC[@]}" down -v >/dev/null 2>&1
  fi
  exit "$code"
}
trap cleanup EXIT

# ---------------------------------------------------------- demo server ---

log "Starting a fresh demo Nextcloud (port $DEMO_PORT)"
"${DC[@]}" down -v >/dev/null 2>&1 || true
"${DC[@]}" up -d

log "Seeding fake data"
APP_PASSWORD="$(DEMO_BASE_URL="http://localhost:$DEMO_PORT" "$PY" tool/demo_server/seed.py | grep '^APP_PASSWORD=' | tail -n1 | cut -d= -f2-)"
[ -n "$APP_PASSWORD" ] || die "the seed script did not return an app password"

# ---------------------------------------------------------------- device ---

if [ -n "${ANDROID_SERIAL:-}" ]; then
  SERIAL="$ANDROID_SERIAL"
  log "Using existing device $SERIAL"
else
  log "Preparing the emulator"
  [ -n "$SDK_ROOT" ] || die "set ANDROID_HOME to your Android SDK"
  EMULATOR="$(find_tool emulator || true)"
  if [ -z "$EMULATOR" ] || ! [ -d "$SDK_ROOT/system-images/android-${API_LEVEL}/google_apis/x86_64" ]; then
    log "Installing the emulator + system image (one-off, a few GB)"
    yes | "$SDKMANAGER" --licenses >/dev/null 2>&1 || true
    "$SDKMANAGER" "emulator" "platform-tools" "$SYSTEM_IMAGE"
    EMULATOR="$(find_tool emulator)"
  fi

  # avdmanager also prints a harmless "Could not load devices from
  # .../devices.xml" error for system images that ship no devices.xml, so its
  # output is hidden and success is judged by whether the AVD exists.
  echo no | "$AVDMANAGER" create avd --force -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d pixel_6 >/dev/null 2>&1 || true
  AVD_DIR="$(to_unix "${ANDROID_AVD_HOME:-$HOME/.android/avd}")/$AVD_NAME.avd"
  [ -d "$AVD_DIR" ] || die "could not find the AVD at $AVD_DIR (set ANDROID_AVD_HOME)"
  set_ini() { # <key> <value>: replace or append in the AVD's config.ini
    if grep -q "^$1=" "$AVD_DIR/config.ini"; then
      sed -i.bak "s|^$1=.*|$1=$2|" "$AVD_DIR/config.ini" && rm -f "$AVD_DIR/config.ini.bak"
    else
      echo "$1=$2" >> "$AVD_DIR/config.ini"
    fi
  }
  sed -i.bak '/^skin\.path=/d' "$AVD_DIR/config.ini" && rm -f "$AVD_DIR/config.ini.bak"
  set_ini skin.name "${SCREEN_W}x${SCREEN_H}"
  set_ini hw.lcd.width "$SCREEN_W"
  set_ini hw.lcd.height "$SCREEN_H"
  set_ini hw.lcd.density "$SCREEN_DENSITY"

  log "Booting the emulator"
  EMULATOR_FLAGS=(-avd "$AVD_NAME" -no-snapshot -wipe-data -no-audio -no-boot-anim -gpu swiftshader_indirect)
  [ "${HEADLESS:-0}" = 1 ] && EMULATOR_FLAGS+=(-no-window)
  "$EMULATOR" "${EMULATOR_FLAGS[@]}" >/tmp/noo_emulator.log 2>&1 &
  EMULATOR_PID=$!
  STARTED_EMULATOR=1

  adb wait-for-device
  for _ in $(seq 1 150); do
    [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break
    sleep 2
  done
  [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] || die "the emulator did not finish booting (see /tmp/noo_emulator.log)"
  SERIAL="$(adb devices | awk '/^emulator-/{print $1; exit}')"
fi
export ANDROID_SERIAL="$SERIAL"

log "Configuring the device"
adb shell input keyevent 82 >/dev/null 2>&1 || true            # dismiss keyguard
adb shell svc power stayon true >/dev/null 2>&1 || true        # never sleep mid-run

# Make the demo server reachable from the device as localhost. Binding a port
# below 1024 (the default 80) on the device needs root - the google_apis
# emulator images allow `adb root` - otherwise fall back to a high device
# port, which then shows up as ":8080" in the app.
DEVICE_PORT="$DEMO_PORT"
if [ "$DEMO_PORT" -lt 1024 ]; then
  adb root >/dev/null 2>&1 || true
  sleep 2
  adb wait-for-device
fi
if ! adb reverse "tcp:$DEVICE_PORT" "tcp:$DEMO_PORT" >/dev/null 2>&1; then
  DEVICE_PORT=8080
  printf 'note: could not bind port %s on the device (no root); using %s instead\n' "$DEMO_PORT" "$DEVICE_PORT" >&2
  adb reverse "tcp:$DEVICE_PORT" "tcp:$DEMO_PORT" || die "adb reverse failed"
fi

SERVER_HOST="localhost"
if [ -n "$DEMO_HOST" ]; then
  # Best effort: make DEMO_HOST resolve to the (reverse-forwarded) loopback.
  if adb root >/dev/null 2>&1 && sleep 2 && adb remount >/dev/null 2>&1 &&
    adb shell "echo '127.0.0.1 $DEMO_HOST' >> /system/etc/hosts" >/dev/null 2>&1; then
    SERVER_HOST="$DEMO_HOST"
  else
    printf 'warning: could not edit the device hosts file; showing "localhost" instead of %s\n' "$DEMO_HOST" >&2
  fi
fi
SERVER_URL="http://$SERVER_HOST"
[ "$DEVICE_PORT" = 80 ] || SERVER_URL="$SERVER_URL:$DEVICE_PORT"

# Clean status bar: 12:00, full battery, full Wi-Fi, no notification icons.
adb shell settings put global sysui_demo_allowed 1
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" >/dev/null; }
demo enter
demo clock -e hhmm 1200
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4 -e fully true -e mobile hide
demo notifications -e visible false

# --------------------------------------------------------------- capture ---

log "Capturing screenshots (this drives the app for a few minutes)"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
SCREENSHOT_DIR="$OUT_DIR" flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/store_screenshots_test.dart \
  -d "$SERIAL" \
  --dart-define="DEMO_SERVER_URL=$SERVER_URL" \
  --dart-define="DEMO_USERNAME=Alex" \
  --dart-define="DEMO_APP_PASSWORD=$APP_PASSWORD"

log "Making them Play Store ready"
"$PY" tool/finalize_screenshots.py "$OUT_DIR"

log "Done: $OUT_DIR"
printf '\nBefore uploading, LOOK at every image for anything real: the server\n' >&2
printf 'address/username in the header and Settings, notification icons, names.\n' >&2
