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

rm -rf "$STAGE" "$PKG" "$DMG"
mkdir -p "$STAGE/pkgroot/Applications" "$STAGE/dmg"

echo "==> Installer package (.pkg)"
cp -R "dist/$APP.app" "$STAGE/pkgroot/Applications/"
pkgbuild \
  --root "$STAGE/pkgroot" \
  --install-location / \
  --identifier dev.hex.hudex \
  --version "$VERSION" \
  --ownership recommended \
  "$PKG"

echo "==> Disk image (.dmg)"
cp -R "dist/$APP.app" "$STAGE/dmg/"
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
   Open Settings → Source to pick your HudEX.md, or create the example file.
   HudEX 没有 Dock 图标，它住在菜单栏里。
   打开 设置 → 数据源 选择你的 HudEX.md，没有文件时点「创建示例文件」。

HudEX needs no permissions and no network: it only reads and writes that one
Markdown file. 它不需要任何权限、不联网，只读写那一个 Markdown 文件。
NOTE

if hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGE/dmg" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
  echo "    created $DMG"
else
  rm -f "$DMG"
  echo "    !! hdiutil failed (restricted shell?) — the .pkg is still available"
fi

rm -rf "$STAGE"

echo
echo "==> Artefacts"
( cd "$RELEASE" && shasum -a 256 "$(basename "$PKG")" ${DMG:+"$(basename "$DMG")"} 2>/dev/null )
echo
echo "Install the package with:"
echo "    open $PKG            # Installer.app, asks for your password"
echo "    sudo installer -pkg $PKG -target /    # no dialogs"
