#!/usr/bin/env bash
# Run all UNIT tests (tests/unit/) headless via GUT.
# Output: tests/logs/unit_<timestamp>.log
# Print a summary tail to stdout.

set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="tests/logs/unit_${TS}.log"

if [ ! -x "$GODOT" ]; then
  echo "Godot not found at $GODOT (set GODOT_BIN=/path/to/godot)" >&2
  exit 1
fi

mkdir -p tests/logs
echo "▶ Running UNIT tests → $LOG"

"$GODOT" --headless --path . \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/unit \
  -ginclude_subdirs \
  -gprefix=test_ -gsuffix=.gd \
  -gexit \
  > "$LOG" 2>&1

echo "── tail ─────────────────────────────"
tail -30 "$LOG"
echo "── full log: $LOG ───────────────────"

# Exit code from GUT: non-zero if any failures.
grep -qE "Failing Tests *0$" "$LOG"
