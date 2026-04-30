#!/usr/bin/env bash
#
# Build a signed Android AAB ready to upload to Play Console.
#
# Steps:
#   1. Load credentials from secrets/keystore.env.
#   2. Validate that keystores, Godot binary, and android source
#      template all exist and look healthy.
#   3. Patch export_presets.cfg with the keystore paths/users (the
#      file is committed without paths so different machines can
#      share the same preset).
#   4. Run `godot --headless --export-release "Android" build/...aab`.
#   5. Audit the produced manifest for the usual Play Store gotchas.
#
# Usage:
#   scripts/build/build_android.sh                  # full release build
#   scripts/build/build_android.sh --debug          # debug-signed APK
#   scripts/build/build_android.sh --validate-only  # just run checks
#
# Requires:
#   * GODOT_BIN env var, or `godot` / `godot4` on PATH, or
#     /Applications/Godot.app on macOS.
#   * Android source template generated once via
#     `Project → Install Android Build Template…` in the Godot editor.
#     (Creates ./android/ — gitignored.)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

mode="release"
validate_only=false

for arg in "$@"; do
	case "$arg" in
		--debug)         mode="debug" ;;
		--release)       mode="release" ;;
		--validate-only) validate_only=true ;;
		-h|--help)       sed -n '2,28p' "$0"; exit 0 ;;
	esac
done

# ── Locate Godot ──────────────────────────────────────────────────────────────

if [[ -n "${GODOT_BIN:-}" && -x "$GODOT_BIN" ]]; then
	godot="$GODOT_BIN"
elif command -v godot >/dev/null; then
	godot="$(command -v godot)"
elif command -v godot4 >/dev/null; then
	godot="$(command -v godot4)"
elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
	godot="/Applications/Godot.app/Contents/MacOS/Godot"
else
	echo "❌ Godot binary not found. Set GODOT_BIN or install godot4." >&2
	exit 1
fi

echo "→ Godot:           $godot"
echo "→ Build mode:      $mode"

# ── Load secrets ──────────────────────────────────────────────────────────────

ENV_FILE="$ROOT/secrets/keystore.env"
if [[ ! -f "$ENV_FILE" ]]; then
	echo "❌ Missing $ENV_FILE — copy keystore.env.example and fill it in." >&2
	exit 1
fi
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

# ── Validate keystores ────────────────────────────────────────────────────────

if [[ "$mode" == "release" ]]; then
	ks_path="${EFH_RELEASE_KEYSTORE_PATH:-}"
	ks_user="${EFH_RELEASE_KEYSTORE_USER:-}"
	ks_pass="${EFH_RELEASE_KEYSTORE_PASS:-}"
else
	ks_path="${EFH_DEBUG_KEYSTORE_PATH:-}"
	ks_user="${EFH_DEBUG_KEYSTORE_USER:-}"
	ks_pass="${EFH_DEBUG_KEYSTORE_PASS:-}"
fi

[[ -f "$ks_path" ]] || { echo "❌ keystore not found at $ks_path — run scripts/build/create_keystore.sh" >&2; exit 1; }
[[ -n "$ks_user" ]] || { echo "❌ keystore alias (user) is empty"; exit 1; }
[[ -n "$ks_pass" ]] || { echo "❌ keystore password is empty"; exit 1; }
[[ "$mode" != "release" || ${#ks_pass} -ge 12 ]] || { echo "❌ release keystore password too short (<12 chars)"; exit 1; }

echo "→ Keystore:        $ks_path (alias=$ks_user)"

# ── Android template present? ────────────────────────────────────────────────

if [[ ! -d "$ROOT/android/build" ]]; then
	cat <<-EOF >&2
	❌ android/build/ missing. Open the project in the Godot editor and run:
	     Project → Install Android Build Template…
	   That creates the gradle source needed for AAB output.
	EOF
	exit 1
fi
echo "→ Android template: android/build/"

# ── Validate export_presets.cfg ──────────────────────────────────────────────

preset="$ROOT/export_presets.cfg"
grep -q '^name="Android"' "$preset" || { echo "❌ Android preset missing"; exit 1; }
grep -q '^gradle_build/use_gradle_build=true' "$preset" || {
	echo "❌ gradle_build/use_gradle_build must be true for AAB"; exit 1; }
grep -q '^gradle_build/export_format=1' "$preset" || {
	echo "❌ gradle_build/export_format must be 1 (AAB)"; exit 1; }
grep -q '^architectures/arm64-v8a=true' "$preset" || {
	echo "❌ arm64-v8a must be enabled (Play Store requires 64-bit)"; exit 1; }

echo "→ export_presets:  validated"

if $validate_only; then
	echo "✅ all checks passed (validate-only)"
	exit 0
fi

# ── Patch keystore paths into a temp copy of export_presets.cfg ──────────────
#
# We never commit absolute paths or passwords; we splice them in just
# before the export call and revert afterwards.

backup="$preset.bak.$$"
cp "$preset" "$backup"
trap 'mv "$backup" "$preset"' EXIT

abs_ks="$(cd "$(dirname "$ks_path")" && pwd)/$(basename "$ks_path")"

if [[ "$mode" == "release" ]]; then
	# Inject under [preset.0.options] block.
	awk -v p="$abs_ks" -v u="$ks_user" '
		/^\[preset\.0\.options\]/ { print; print "keystore/release=\"" p "\""; print "keystore/release_user=\"" u "\""; next }
		{ print }
	' "$backup" > "$preset"
else
	awk -v p="$abs_ks" -v u="$ks_user" '
		/^\[preset\.0\.options\]/ { print; print "keystore/debug=\"" p "\""; print "keystore/debug_user=\"" u "\""; next }
		{ print }
	' "$backup" > "$preset"
fi

# Godot 4 reads the password from the GODOT_ANDROID_KEYSTORE_*_PASSWORD env var.
if [[ "$mode" == "release" ]]; then
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$ks_pass"
else
	export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="$ks_pass"
fi

# ── Output path ───────────────────────────────────────────────────────────────

mkdir -p "$ROOT/build"
version="$(awk -F'"' '/^config\/version/ {print $2}' "$ROOT/project.godot")"
git_sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo "nogit")"
ts="$(date +%Y%m%d-%H%M%S)"

if [[ "$mode" == "release" ]]; then
	out="$ROOT/build/escape-from-hell-${version}-${git_sha}-${ts}.aab"
	export_flag="--export-release"
else
	out="$ROOT/build/escape-from-hell-${version}-${git_sha}-${ts}-debug.apk"
	export_flag="--export-debug"
fi

echo "→ Output:          $out"
echo

# ── Run the export ────────────────────────────────────────────────────────────

"$godot" --headless --path "$ROOT" "$export_flag" "Android" "$out"

if [[ ! -f "$out" ]]; then
	echo "❌ build failed — Godot did not produce $out" >&2
	exit 1
fi

echo
echo "✅ built $out  ($(du -h "$out" | cut -f1))"

# ── Manifest audit (extracts the manifest from the AAB/APK) ───────────────────

if command -v "$ROOT/scripts/build/audit_manifest.sh" >/dev/null \
		|| [[ -x "$ROOT/scripts/build/audit_manifest.sh" ]]; then
	"$ROOT/scripts/build/audit_manifest.sh" "$out" || {
		echo "⚠️  manifest audit reported issues — review before upload" >&2
	}
fi
