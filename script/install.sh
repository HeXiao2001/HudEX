#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DockCue"
APP_DIR="/Applications/$APP_NAME.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"

latest_dmg() {
  find "$RELEASE_DIR" -maxdepth 1 -name 'DockCue-v*.dmg' -type f 2>/dev/null | sort -V | tail -1
}

echo "=== Installing DockCue ==="

pkill -x "$APP_NAME" 2>/dev/null || true

DMG_PATH="$(latest_dmg || true)"
if [[ -n "$DMG_PATH" && -f "$DMG_PATH" ]]; then
  echo "Mounting $(basename "$DMG_PATH")..."
  MOUNT_POINT="$(hdiutil attach "$DMG_PATH" -nobrowse -noautoopen 2>&1 | awk '/\/Volumes\// {print $NF; exit}')"
  trap 'hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true' EXIT
  rm -rf "$APP_DIR"
  cp -R "$MOUNT_POINT/$APP_NAME.app" "/Applications/"
  hdiutil detach "$MOUNT_POINT" >/dev/null
  trap - EXIT
else
  echo "No release DMG found; installing development bundle."
  rm -rf "$APP_DIR"
  cp -R "$DIST_DIR/$APP_NAME.app" "/Applications/"
fi

xattr -dr com.apple.quarantine "$APP_DIR" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true

echo "Installed to $APP_DIR"
open "$APP_DIR"
echo "DockCue launched. Add to Login Items for auto-start."
echo ""
echo "=== Update instructions ==="
echo "Menu bar → Check for Updates... → download latest DMG → reinstall"
