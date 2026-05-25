#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="KWWKLauncher"
BUNDLE_ID="ai.kwwk.launcher"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
INSTALL_DIR="${KWWK_LAUNCHER_INSTALL_DIR:-$HOME/Applications}"
INSTALL_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
CLI_BINARY="$APP_MACOS/kwwk"
INFO_PLIST="$APP_CONTENTS/Info.plist"
LOCK_DIR="${TMPDIR:-/tmp}/kwwk-build-and-run.lock"
SWIFT_BUILD_JOBS="${KWWK_SWIFT_BUILD_JOBS:-2}"
SWIFT_BUILD_NICE="${KWWK_SWIFT_BUILD_NICE:-5}"

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" >"$LOCK_DIR/pid"
    return
  fi

  local owner=""
  if [[ -f "$LOCK_DIR/pid" ]]; then
    owner="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  fi

  if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
    echo "KWWKLauncher build/run is already active in pid $owner" >&2
    exit 75
  fi

  rm -rf "$LOCK_DIR"
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "KWWKLauncher build/run lock is busy: $LOCK_DIR" >&2
    exit 75
  fi
  printf '%s\n' "$$" >"$LOCK_DIR/pid"
}

cleanup_lock() {
  rm -rf "$LOCK_DIR"
}

swift_build() {
  /usr/bin/nice -n "$SWIFT_BUILD_NICE" swift build --jobs "$SWIFT_BUILD_JOBS" --product "$1"
}

acquire_lock
trap cleanup_lock EXIT

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift_build "$APP_NAME"
swift_build kwwk
BUILD_BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
BUILD_CLI="$BUILD_BIN_DIR/kwwk"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_CLI" "$CLI_BINARY"
chmod +x "$APP_BINARY"
chmod +x "$CLI_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>$BUNDLE_ID</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>kwwk</string>
      </array>
    </dict>
  </array>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open "$APP_BUNDLE"
}

process_count() {
  local pids
  pids="$(pgrep -x "$APP_NAME" 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    printf '%s\n' "$pids" | wc -l | tr -d '[:space:]'
    return
  fi

  ps -axo comm= | awk -v name="$APP_NAME" '
    {
      command = $0
      sub(/^.*\//, "", command)
      if (command == name) count += 1
    }
    END { print count + 0 }
  '
}

process_list() {
  pgrep -fl "$APP_NAME" 2>/dev/null || ps -axo pid=,command= | awk -v name="$APP_NAME" '
    {
      command = $0
      sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "", command)
      basename = command
      sub(/^.*\//, "", basename)
      sub(/[[:space:]].*$/, "", basename)
      if (basename == name) print $0
    }
  ' || true
}

verify_single_instance() {
  open_app
  sleep 1
  open_app
  sleep 1
  local count
  count="$(process_count)"
  if [[ "$count" != "1" ]]; then
    echo "expected one $APP_NAME process, found $count" >&2
    process_list >&2
    exit 1
  fi
}

install_app() {
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_BUNDLE"
  /usr/bin/ditto "$APP_BUNDLE" "$INSTALL_BUNDLE"

  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$INSTALL_BUNDLE" >/dev/null 2>&1 || true
  fi

  echo "Installed $INSTALL_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    if [[ "$(process_count)" == "0" ]]; then
      echo "expected $APP_NAME process to be running" >&2
      process_list >&2
      exit 1
    fi
    ;;
  --verify-single-instance|verify-single-instance)
    verify_single_instance
    ;;
  --install|install)
    install_app
    /usr/bin/open "$INSTALL_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--verify-single-instance|--install]" >&2
    exit 2
    ;;
esac
