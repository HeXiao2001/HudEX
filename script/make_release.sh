#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DockCue"
BUNDLE_ID="dev.hex.dockcue"
VERSION="${1:-0.1.0}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/release"
STAGING="$RELEASE_DIR/dmg_staging"
APP_DIR="$STAGING/$APP_NAME.app"
CERT_NAME="DockCue Development"
ICONSET_DIR="$ROOT_DIR/script/DockCue.iconset"
ICNS_FILE="$ROOT_DIR/script/DockCue.icns"
MENU_ICON_FILE="$ROOT_DIR/script/DockCueMenuTemplate.png"
MENU_ICON_2X_FILE="$ROOT_DIR/script/DockCueMenuTemplate@2x.png"
DMG_BACKGROUND="$ROOT_DIR/script/dmg-background.png"
ASSET_SCRIPT="$ROOT_DIR/script/generate_assets.swift"

cd "$ROOT_DIR"

echo "=== Building DockCue v$VERSION (release) ==="

# Clean
rm -rf "$RELEASE_DIR"
mkdir -p "$STAGING"

# Assets
if [[ -x "$ASSET_SCRIPT" ]]; then
  echo "Generating app and DMG assets..."
  "$ASSET_SCRIPT" >/dev/null
elif [[ ! -f "$ICNS_FILE" ]] || [[ "$ICONSET_DIR" -nt "$ICNS_FILE" ]]; then
  if [[ -d "$ICONSET_DIR" ]]; then
    iconutil -c icns -o "$ICNS_FILE" "$ICONSET_DIR" 2>/dev/null || true
  fi
fi

# Release build
swift build -c release --product "$APP_NAME"

# Assemble app bundle
mkdir -p "$APP_DIR/Contents/MacOS" \
         "$APP_DIR/Contents/Resources/Examples"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Examples/config.json" "$APP_DIR/Contents/Resources/Examples/config.json"
cp "$ROOT_DIR/Examples/hud.json" "$APP_DIR/Contents/Resources/Examples/hud.json"
cp "$ROOT_DIR/Examples/hud_leftDock.json" "$APP_DIR/Contents/Resources/Examples/hud_leftDock.json" 2>/dev/null || true
cp "$ROOT_DIR/Examples/hud_rightDock.json" "$APP_DIR/Contents/Resources/Examples/hud_rightDock.json" 2>/dev/null || true
cp "$MENU_ICON_FILE" "$APP_DIR/Contents/Resources/DockCueMenuTemplate.png" 2>/dev/null || true
cp "$MENU_ICON_2X_FILE" "$APP_DIR/Contents/Resources/DockCueMenuTemplate@2x.png" 2>/dev/null || true

# Icon
if [[ -f "$ICNS_FILE" ]]; then
  cp "$ICNS_FILE" "$APP_DIR/Contents/Resources/DockCue.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>DockCue</string>"
else
  ICON_KEY=""
fi

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
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
  <key>CFBundleDisplayName</key>
  <string>DockCue</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSCalendarsUsageDescription</key>
  <string>DockCue shows lightweight Dock-side cues from local files.</string>
  $ICON_KEY
</dict>
</plist>
PLIST

# Sign
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_NAME"; then
  /usr/bin/codesign --force --deep --sign "$CERT_NAME" "$APP_DIR"
  echo "Signed with: $CERT_NAME"
else
  /usr/bin/codesign --force --deep --sign - "$APP_DIR"
  echo "Ad-hoc signed"
fi

# ── DMG with drag-to-install layout ──────────────────────────────────────

ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp "$DMG_BACKGROUND" "$STAGING/.background/dmg-background.png" 2>/dev/null || true
cp "$ICNS_FILE" "$STAGING/.VolumeIcon.icns" 2>/dev/null || true

DMG_PATH="$RELEASE_DIR/DockCue-v$VERSION.dmg"
DMG_TMP="$RELEASE_DIR/DockCue-tmp.dmg"
VOLNAME="DockCue_v$VERSION"

# Create read-write DMG with enough headroom for Finder metadata.
hdiutil create -fs HFS+ -volname "$VOLNAME" -srcfolder "$STAGING" -size 24m "$DMG_TMP" >/dev/null

# Mount and set layout. Finder scripting is best-effort because it can fail
# when Finder is unavailable, automation permissions are restricted, or this
# script is running in an environment that cannot mount disk images.
if ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TMP" 2>&1)"; then
  DEV="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print $1; exit}')"
  MOUNT="/Volumes/$VOLNAME"

  if [[ -f "$MOUNT/.VolumeIcon.icns" ]]; then
    /usr/bin/SetFile -a C "$MOUNT" 2>/dev/null || true
    /usr/bin/SetFile -a V "$MOUNT/.VolumeIcon.icns" 2>/dev/null || true
  fi
  /usr/bin/SetFile -a V "$MOUNT/.background" 2>/dev/null || true

  # Arrange icons (left=DockCue, right=Applications symlink)
  if ! osascript <<APPLESCRIPT
try
  tell application "Finder"
    tell disk "$VOLNAME"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set bounds of container window to {200, 200, 840, 560}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 96
      try
        set background picture of viewOptions to POSIX file "$MOUNT/.background/dmg-background.png"
      end try
      set position of item "$APP_NAME.app" to {170, 215}
      set position of item "Applications" to {470, 215}
      update without registering applications
      delay 0.5
      close
    end tell
  end tell
end try
APPLESCRIPT
  then
    echo "Warning: Finder DMG layout step failed; continuing with a functional DMG."
  fi

  sync
  hdiutil detach "$DEV" >/dev/null
else
  echo "Warning: Could not mount temporary DMG for Finder layout; continuing without custom layout."
  echo "$ATTACH_OUTPUT"
fi
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$DMG_TMP"

# Clean staging
rm -rf "$STAGING"

echo ""
echo "=== Release built ==="
echo "DMG: $DMG_PATH"
ls -lh "$DMG_PATH"
