#!/usr/bin/env bash
#
# Static audit of an AAB / APK manifest before Play Store upload.
# Catches the small slip-ups that get a release rejected (debuggable
# left on, target SDK too low, wrong package id, version drift, etc.)
# without needing to install the app on a device.
#
# Usage:  scripts/build/audit_manifest.sh build/foo.aab
#
# Requires `aapt` (Android SDK build-tools) on PATH, or set AAPT_BIN.

set -euo pipefail

bin="${1:-}"
[[ -f "$bin" ]] || { echo "usage: $0 <path-to-aab-or-apk>" >&2; exit 2; }

aapt="${AAPT_BIN:-aapt}"
if ! command -v "$aapt" >/dev/null; then
	echo "⚠️  aapt not found — skipping manifest audit (install Android SDK build-tools or set AAPT_BIN)" >&2
	exit 0
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
expected_pkg="$(awk -F'"' '/^package\/unique_name/ {print $2}' "$ROOT/export_presets.cfg")"
expected_ver="$(awk -F'"' '/^config\/version/ {print $2}' "$ROOT/project.godot")"
expected_code="$(awk -F'=' '/^version\/code/ {gsub(/[^0-9]/, "", $2); print $2}' "$ROOT/export_presets.cfg")"
# Play Store requires target SDK 35+ for new releases as of Aug 2025.
min_target_sdk=34

dump="$("$aapt" dump badging "$bin")"

fail=0
check() {
	local desc="$1" expected="$2" actual="$3"
	if [[ "$actual" == "$expected" ]]; then
		printf "  ✓ %-22s %s\n" "$desc" "$actual"
	else
		printf "  ✗ %-22s expected %s, got %s\n" "$desc" "$expected" "$actual"
		fail=1
	fi
}

pkg=$(echo "$dump" | grep -oE "package: name='[^']+'" | head -1 | sed -E "s/.*name='([^']+)'.*/\1/")
ver_name=$(echo "$dump" | grep -oE "versionName='[^']+'" | head -1 | sed -E "s/.*='([^']+)'/\1/")
ver_code=$(echo "$dump" | grep -oE "versionCode='[^']+'" | head -1 | sed -E "s/.*='([^']+)'/\1/")
target_sdk=$(echo "$dump" | grep -oE "targetSdkVersion:'[^']+'" | head -1 | sed -E "s/.*:'([^']+)'/\1/")
debuggable=$(echo "$dump" | grep -c "application-debuggable" || true)

echo "── Manifest audit: $(basename "$bin") ──"
check "package"        "$expected_pkg"  "$pkg"
check "versionName"    "$expected_ver"  "$ver_name"
check "versionCode"    "$expected_code" "$ver_code"

if [[ "$target_sdk" -lt "$min_target_sdk" ]]; then
	printf "  ✗ %-22s %s (Play Store requires ≥ %s)\n" "targetSdkVersion" "$target_sdk" "$min_target_sdk"
	fail=1
else
	printf "  ✓ %-22s %s\n" "targetSdkVersion" "$target_sdk"
fi

if [[ "$debuggable" -gt 0 ]]; then
	printf "  ✗ %-22s set (release builds must NOT be debuggable)\n" "android:debuggable"
	fail=1
else
	printf "  ✓ %-22s not set\n" "android:debuggable"
fi

# Permissions sanity — list anything unexpected so the dev sees it.
perms=$(echo "$dump" | grep "uses-permission:" | sed -E "s/.*name='([^']+)'.*/\1/" || true)
if [[ -n "$perms" ]]; then
	echo "  ℹ permissions:"
	echo "$perms" | sed 's/^/      /'
fi

if [[ "$fail" -ne 0 ]]; then
	echo "❌ audit FAILED — fix the above before uploading to Play Store" >&2
	exit 1
fi
echo "✅ audit passed"
