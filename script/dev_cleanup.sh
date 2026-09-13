#!/usr/bin/env bash
#
# After a development session: stop the debug build, and make sure it cannot
# show up next to the installed app in Spotlight or Launchpad.
#
#   ./script/dev_cleanup.sh          # quit + unregister the dev build
#   ./script/dev_cleanup.sh --dock   # ...and restart the Dock (refreshes Launchpad)
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

pkill -x HudEX 2>/dev/null || true
sleep 1
echo "HudEX running: $(pgrep -x HudEX | wc -l | tr -d ' ')"

# Unregistering works on paths that no longer exist — which is the important
# case: LaunchServices keeps those entries, and they are what shows up as a
# second, unstoppable-looking copy in Spotlight and Launchpad.
for stale in "$ROOT/.build/HudEX.app" "$ROOT/dist/HudEX.app" \
             "$ROOT/release/.stage/dmg/HudEX.app" \
             "$ROOT/release/.stage/pkgroot/Applications/HudEX.app" \
             "/Volumes/HudEX/HudEX.app"; do
  "$LSREG" -u "$stale" >/dev/null 2>&1 && echo "unregistered $stale"
done

# Leftover mounted images also answer a Spotlight search.
for volume in /Volumes/HudEX*; do
  [[ -d "$volume" ]] || continue
  hdiutil detach "$volume" >/dev/null 2>&1 && echo "ejected $volume"
done

if [[ "${1:-}" == "--dock" ]]; then
  killall Dock 2>/dev/null || true
  echo "Dock restarted (Launchpad refreshed)"
fi

echo "still registered:"
"$LSREG" -dump 2>/dev/null | grep -E "^\s*path:.*HudEX.app" | sed 's/^ *path: */  /' || echo "  (none)"
