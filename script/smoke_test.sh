#!/usr/bin/env bash
#
# Launches the built app and checks that it actually became visible.
#
# This exists because "the process is running but nothing appeared" is invisible
# to every other kind of test: SwiftPM builds, unit tests and code review all
# pass happily while the app has no windows at all (a missing delegate, say).
#
#   ./script/smoke_test.sh [path/to/HudEX.app]
#
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="${1:-$ROOT/.build/HudEX.app}"

[[ -d "$APP" ]] || { echo "!! no app at $APP" >&2; exit 1; }

pkill -x HudEX 2>/dev/null || true
sleep 1

open "$APP"
sleep 6

fail=0
if [[ "$(pgrep -x HudEX | wc -l | tr -d ' ')" == "0" ]]; then
  echo "!! the app is not running" >&2; fail=1
fi
windows=$(osascript -e 'tell application "System Events" to count windows of (first process whose bundle identifier is "dev.hex.hudex")' 2>/dev/null || echo "?")
if [[ "$windows" == "0" || "$windows" == "?" ]]; then
  # Fall back to counting the app's own windows without Accessibility.
  windows=$(swift "$ROOT/script/window_count.swift" 2>/dev/null || echo "?")
fi
if [[ "$windows" == "0" ]]; then
  echo "!! the app is running but has no windows" >&2; fail=1
fi

pkill -x HudEX 2>/dev/null || true
if [[ $fail == 0 ]]; then
  echo "smoke test passed: running, $windows window(s)"
else
  exit 1
fi
