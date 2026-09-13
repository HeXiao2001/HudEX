#!/usr/bin/env bash
#
# Copies .build/HudEX.app into /Applications. HudEX is a single self-contained
# bundle: no helper process, no login item plist, no support files.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/.build/HudEX.app"
TARGET_APP="/Applications/HudEX.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo ".build/HudEX.app not found — run script/build_and_run.sh first." >&2
  exit 1
fi

pkill -x HudEX >/dev/null 2>&1 || true
rm -rf "$TARGET_APP"
cp -R "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$TARGET_APP" >/dev/null 2>&1 || true

echo "Installed to $TARGET_APP"
open "$TARGET_APP"
