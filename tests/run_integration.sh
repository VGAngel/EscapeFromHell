#!/usr/bin/env bash
# Run all INTEGRATION tests (tests/integration/) headless via GUT.
# Output: tests/logs/integration_<timestamp>.log
# Print a summary tail to stdout.

set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="tests/logs/integration_${TS}.log"

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT (set GODOT_BIN=/path/to/godot)" >&2
  exit 1
fi

mkdir -p tests/logs
echo "▶ Running INTEGRATION tests → $LOG"

"$GODOT" --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/integration \
  -ginclude_subdirs \
  -gprefix=test_ -gsuffix=.gd \
  -gexit \
  > "$LOG" 2>&1

echo "── tail ─────────────────────────────"
tail -30 "$LOG"
echo "── full log: $LOG ───────────────────"

grep -qE "Failing Tests *0$" "$LOG"
