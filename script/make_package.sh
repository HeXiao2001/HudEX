#!/usr/bin/env bash
#
# Builds the release artefacts:
#
#   release/HudEX-<version>.pkg   native installer (double-click → Installer.app)
#   release/HudEX-<version>.dmg   drag-to-Applications disk image
#
# HudEX is ad-hoc signed (no Developer ID), so the first launch on another Mac
# asks for one confirmation; both artefacts explain that.
#
# Note: creating the DMG needs `hdiutil`, which attaches a temporary disk image.
# In a restricted/sandboxed shell that is blocked — run this script from a normal
# Terminal if the DMG step fails (the .pkg step works anywhere).
#
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

VERSION=$(grep -m1 '^BUNDLE_SHORT_VERSION=' script/build_and_run.sh | cut -d'"' -f2)
APP="HudEX"
RELEASE="$ROOT/release"
STAGE="$RELEASE/.stage"
PKG="$RELEASE/$APP-$VERSION.pkg"
DMG="$RELEASE/$APP-$VERSION.dmg"

echo "==> Building $APP $VERSION (release)"
HUDEX_SWIFT_FLAGS=--disable-sandbox ./script/build_and_run.sh --release --no-launch

# Both artefacts come from this one bundle, and the bundle is checked before it
# is packaged: shipping a package that is older than the source is the one
# mistake that is invisible until someone installs it.
BUNDLE="$ROOT/.build/$APP.app"
BUNDLE_VERSION=$(defaults read "$BUNDLE/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
STRINGS=$(find "$BUNDLE/Contents/Resources" -name Localizable.strings | head -1)
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
  echo "!! bundle is $BUNDLE_VERSION but the script says $VERSION — rebuild first" >&2
  exit 1
fi
for marker in '"welcome.title"' '"source.ownership"'; do
  if ! grep -q "$marker" "$STRINGS" 2>/dev/null; then
    echo "!! the packaged bundle is missing $marker — it is stale" >&2
    exit 1
  fi
done
echo "    bundle $BUNDLE_VERSION verified ($(basename "$STRINGS"))"

# A build that launches but shows nothing passes every other check — it happened
# once, so the package build refuses to continue without this.
if [[ "${HUDEX_SKIP_SMOKE:-0}" != "1" ]]; then
  echo "==> Launch smoke test"
  "$ROOT/script/smoke_test.sh" "$BUNDLE"
fi

rm -rf "$STAGE" "$PKG" "$DMG"
mkdir -p "$STAGE/pkgroot/Applications" "$STAGE/dmg"

echo "==> Installer package (.pkg)"
/usr/bin/ditto --noextattr --norsrc ".build/$APP.app" "$STAGE/pkgroot/Applications/$APP.app"
pkgbuild \
  --root "$STAGE/pkgroot" \
  --install-location / \
  --identifier dev.hex.hudex \
  --version "$VERSION" \
  --ownership recommended \
  "$PKG"

echo "==> Disk image (.dmg) — drag onto Applications"
/usr/bin/ditto --noextattr --norsrc ".build/$APP.app" "$STAGE/dmg/$APP.app"
ln -s /Applications "$STAGE/dmg/Applications"
cat > "$STAGE/dmg/Read Me First.txt" <<'NOTE'
HudEX — first launch / 第一次打开

1. Drag HudEX onto the Applications folder next to this file.
   把 HudEX 拖到旁边的 Applications 文件夹里。

2. macOS will warn that the developer cannot be verified, because HudEX is not
   notarised. Right-click (or Control-click) HudEX in Applications → Open →
   Open again. Only the first launch is interrupted.
   因为 HudEX 没有做公证签名，第一次打开会被 macOS 拦一下：
   在「应用程序」里对 HudEX 点右键 → 打开 → 再点「打开」。
   如果仍然被拦住，终端里执行一次即可：
       xattr -dr com.apple.quarantine /Applications/HudEX.app

3. HudEX has no Dock icon: it lives in the menu bar.
   Open Settings → Source to pick your project file, convert it to JSON and
   convert an older Markdown file to one JSON source when needed. All tasks
   use one Apple Reminders list named HudEX. HudEX asks for Reminders access on the
   first sync.
   HudEX 没有 Dock 图标，它住在菜单栏里。
   打开 设置 → 数据源 选择你的 HudEX.md，没有文件时点「创建示例文件」。

HudEX makes no network requests. Reminders access is optional and requested
when automatic or manual sync first runs. 不联网；首次自动或手动同步时请求权限。
NOTE

DMGBUILD=""
for candidate in /tmp/dmgvenv/bin/dmgbuild "$(command -v dmgbuild 2>/dev/null)"; do
  [[ -x "$candidate" ]] && DMGBUILD="$candidate" && break
done

if [[ -n "$DMGBUILD" ]]; then
  "$DMGBUILD" -s "$ROOT/script/dmg-settings.py" \
    -D app="$ROOT/.build/$APP.app" -D volume_name="$APP $VERSION" \
    "$APP $VERSION" "$DMG" >/dev/null 2>&1
fi

if [[ ! -f "$DMG" ]]; then
  if hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
    echo "    created (plain layout; dmgbuild unavailable)"
  else
    rm -f "$DMG"
    echo "    !! could not create the disk image in this shell (hdiutil needs device access)"
  fi
fi
[[ -f "$DMG" ]] && echo "    created $DMG"

rm -rf "$STAGE"

echo
echo "==> Artefacts"
( cd "$RELEASE" && shasum -a 256 "$(basename "$PKG")" ${DMG:+"$(basename "$DMG")"} 2>/dev/null )
echo
echo "Install the package with:"
echo "    open $PKG            # Installer.app, asks for your password"
echo "    sudo installer -pkg $PKG -target /    # no dialogs"
