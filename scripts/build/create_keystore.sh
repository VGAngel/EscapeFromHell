#!/usr/bin/env bash
#
# Generate Android keystores used by the Godot export pipeline.
#
#   debug.keystore   — shared default, password "android". Safe to
#                       regenerate on any dev machine; signs APKs we
#                       only side-load for testing.
#
#   release.keystore — the *single* identity of the published app.
#                       If you lose it, the listing on Play Store is
#                       dead forever. Back up the file AND password
#                       to two offline locations after creation.
#
# Both end up in secrets/ which is gitignored. Run once per machine
# for debug; run once *ever* for release (then never again).
#
# Usage:
#   scripts/build/create_keystore.sh           # interactive (recommended)
#   scripts/build/create_keystore.sh --debug   # only debug
#   scripts/build/create_keystore.sh --release # only release

set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/../../secrets" && pwd)"
DEBUG_KS="$SECRETS_DIR/debug.keystore"
RELEASE_KS="$SECRETS_DIR/release.keystore"

# Standard distinguished-name for a small studio. Edit before first
# release if these aren't accurate — Play Console bakes them into
# the listing's developer cert.
DNAME="CN=Dreamplay Games, OU=Mobile, O=Dreamplay, L=Kyiv, ST=Kyiv, C=UA"

want_debug=true
want_release=true

for arg in "$@"; do
	case "$arg" in
		--debug)   want_release=false ;;
		--release) want_debug=false ;;
		-h|--help)
			sed -n '2,20p' "$0"; exit 0 ;;
	esac
done

if ! command -v keytool >/dev/null; then
	echo "❌ keytool not found. Install JDK 17 (e.g. \`brew install openjdk@17\`)." >&2
	exit 1
fi

generate() {
	local out="$1" alias="$2" pass="$3" validity="$4"
	if [[ -f "$out" ]]; then
		echo "✓ $out already exists — skipping (delete it manually if you really want to regenerate)."
		return 0
	fi
	keytool -genkeypair \
		-keystore "$out" \
		-alias "$alias" \
		-keyalg RSA -keysize 2048 \
		-validity "$validity" \
		-storepass "$pass" -keypass "$pass" \
		-dname "$DNAME"
	chmod 600 "$out"
	echo "✓ created $out (alias=$alias, validity=${validity}d)"
}

if $want_debug; then
	generate "$DEBUG_KS" "androiddebugkey" "android" 10950   # 30 years
fi

if $want_release; then
	echo
	echo "── Release keystore ──"
	echo "Pick a STRONG password. Save it in two places offline."
	read -rsp "Password (min 12 chars): " pass1; echo
	read -rsp "Confirm password:        " pass2; echo
	if [[ "$pass1" != "$pass2" ]]; then
		echo "❌ passwords don't match" >&2; exit 1
	fi
	if [[ ${#pass1} -lt 12 ]]; then
		echo "❌ password too short (need ≥12 chars)" >&2; exit 1
	fi
	generate "$RELEASE_KS" "escape_from_hell" "$pass1" 36500   # 100 years (Play Store min: 25)
	echo
	echo "🔐 Now copy secrets/keystore.env.example → secrets/keystore.env"
	echo "   and paste the password into EFH_RELEASE_KEYSTORE_PASS."
fi
