#!/usr/bin/env bash
#
# Builds HudEX, assembles it as .build/HudEX.app and launches it.
#
# The bundle is assembled inside .build/ on purpose: it is a dotted directory, so
# Spotlight never indexes it and a scratch build can never show up next to the
# installed copy in search results or Launchpad.
#
# The bundle makes HudEX a menu-bar application. It deliberately does *not* set
# LSUIElement: that flag also hides the app from Launchpad, and users expect to
# find it there. The Dock icon is avoided at runtime instead, with
# `setActivationPolicy(.accessory)` in AppDelegate.
#
set -euo pipefail

APP_NAME="HudEX"
BUNDLE_ID="dev.hex.hudex"
BUNDLE_VERSION="1.0.2"
BUNDLE_SHORT_VERSION="1.0.2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_APP_DIR="$ROOT_DIR/.build/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$BUILD_APP_DIR"
BUILD_CONFIG="debug"
BUNDLE_EXECUTABLE="$APP_DIR/Contents/MacOS/$APP_NAME"
ICNS_FILE="$ROOT_DIR/script/HudEX.icns"
ASSET_SCRIPT="$ROOT_DIR/script/generate_assets.swift"
EXAMPLE_FILE="$ROOT_DIR/Examples/HudEX.md"

# SwiftPM's manifest sandbox cannot be nested inside another sandbox (some CI
# and agent environments), so the flag stays overridable.
SWIFT_FLAGS="${HUDEX_SWIFT_FLAGS:-}"

cd "$ROOT_DIR"

LAUNCH=true
VERIFY=false
for argument in "$@"; do
  case "$argument" in
    --no-launch) LAUNCH=false ;;
    --verify) VERIFY=true ;;
    --release) BUILD_CONFIG="release" ;;
  esac
done

EXECUTABLE="$ROOT_DIR/.build/$BUILD_CONFIG/$APP_NAME"

# ------------------------------------------------------------------
# 1. App icon
# ------------------------------------------------------------------
if [[ ! -f "$ICNS_FILE" ]] || [[ "$ASSET_SCRIPT" -nt "$ICNS_FILE" ]]; then
  echo "Generating app icon…"
  "$ASSET_SCRIPT" >/dev/null
fi

# ------------------------------------------------------------------
# 2. Build
# ------------------------------------------------------------------
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

echo "Building $APP_NAME ($BUILD_CONFIG)…"
# shellcheck disable=SC2086
swift build -c "$BUILD_CONFIG" --product "$APP_NAME" $SWIFT_FLAGS

NEW_HASH="$(shasum -a 256 "$EXECUTABLE" | awk '{print $1}')"
OLD_HASH=""
if [[ -f "$BUNDLE_EXECUTABLE" ]]; then
  OLD_HASH="$(shasum -a 256 "$BUNDLE_EXECUTABLE" | awk '{print $1}')"
fi

# ------------------------------------------------------------------
# 3. Signing identity (ad-hoc is fine for local use)
# ------------------------------------------------------------------
SIGN_IDENTITY="${HUDEX_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "HudEX Development"; then
  SIGN_IDENTITY="HudEX Development"
fi
echo "Signing with: $SIGN_IDENTITY"

# Written on every run: the fast path below skips re-copying the binary, but
# the plist is the contract with LaunchServices (and with Launchpad).
write_info_plist() {
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
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$BUNDLE_SHORT_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  $ICON_KEY
  </dict>
  </plist>
PLIST
}

# ------------------------------------------------------------------
# 4. Bundle
# ------------------------------------------------------------------
# A bundle built by another user (or by a root-run script) cannot be refreshed.
if [[ -d "$APP_DIR" && ! -w "$APP_DIR" ]]; then
  echo "!! $APP_DIR is not writable by $(whoami)." >&2
  echo "   Remove it once and run again:  sudo rm -rf \"$APP_DIR\"" >&2
  exit 1
fi

if [[ "$OLD_HASH" == "$NEW_HASH" && -d "$APP_DIR" ]]; then
  echo "Binary unchanged — refreshing resources and re-signing"
  cp "$EXAMPLE_FILE" "$APP_DIR/Contents/Resources/Examples/HudEX.md" 2>/dev/null || true
else
  echo "Assembling bundle"
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Examples"
  cp "$EXECUTABLE" "$BUNDLE_EXECUTABLE"
  cp "$EXAMPLE_FILE" "$APP_DIR/Contents/Resources/Examples/HudEX.md" 2>/dev/null || true
  # Localisation lives in the SwiftPM resource bundle.
  for RESOURCE_BUNDLE in "$ROOT_DIR"/.build/*/"$BUILD_CONFIG"/HudEX_HudEXCore.bundle; do
    if [[ -d "$RESOURCE_BUNDLE" ]]; then
      rm -rf "$APP_DIR/Contents/Resources/HudEX_HudEXCore.bundle"
      cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
      break
    fi
  done

  ICON_KEY=""
  if [[ -f "$ICNS_FILE" ]]; then
    cp "$ICNS_FILE" "$APP_DIR/Contents/Resources/HudEX.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>HudEX</string>"
  fi

  write_info_plist
fi

/usr/bin/codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null 2>&1 \
  || /usr/bin/codesign --force --deep --sign - "$APP_DIR" >/dev/null

# ------------------------------------------------------------------
# 5. Launch
# ------------------------------------------------------------------
if [[ "$LAUNCH" == true ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  /usr/bin/open -n "$APP_DIR"
fi

if [[ "$VERIFY" == true ]]; then
  sleep 1
  pgrep -x "$APP_NAME" >/dev/null
  echo "$APP_NAME is running"
fi

echo "Done: $APP_DIR"
