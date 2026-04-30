#!/usr/bin/env bash
#
# Bump the app version in lockstep across the two places that have
# to agree, or Play Console rejects the upload:
#
#   project.godot         config/version="X.Y.Z"
#   export_presets.cfg    version/name="X.Y.Z"
#                         version/code=N           (strictly increasing int)
#
# The static guard `test_version_in_preset_matches_project` already
# fails if these drift; this script makes sure they never do.
#
# Usage:
#   scripts/build/bump_version.sh patch        # 0.1.0 → 0.1.1
#   scripts/build/bump_version.sh minor        # 0.1.3 → 0.2.0
#   scripts/build/bump_version.sh major        # 0.2.5 → 1.0.0
#   scripts/build/bump_version.sh 0.5.2        # explicit version
#   scripts/build/bump_version.sh 0.5.2 --tag  # also git-commit + tag
#   scripts/build/bump_version.sh --show       # print current values
#
# versionCode is auto-incremented by 1 on every bump (never reused —
# Play Console enforces strict monotonicity).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$ROOT/project.godot"
PRESET="$ROOT/export_presets.cfg"

cur_ver="$(awk -F'"' '/^config\/version/ {print $2}' "$PROJECT")"
cur_code="$(awk -F'=' '/^version\/code/ {gsub(/[^0-9]/, "", $2); print $2}' "$PRESET")"
preset_ver="$(awk -F'"' '/^version\/name/ {print $2}' "$PRESET")"

if [[ "$cur_ver" != "$preset_ver" ]]; then
	echo "❌ versions already out of sync: project.godot=$cur_ver, preset=$preset_ver" >&2
	echo "   fix manually before bumping." >&2
	exit 1
fi

# ── Mode dispatch ─────────────────────────────────────────────────────────────

[[ $# -ge 1 ]] || { sed -n '2,20p' "$0"; exit 2; }

if [[ "$1" == "--show" ]]; then
	echo "version:     $cur_ver"
	echo "versionCode: $cur_code"
	exit 0
fi

bump_kind="$1"
do_tag=false
for arg in "${@:2}"; do
	case "$arg" in
		--tag) do_tag=true ;;
		*)     echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

IFS='.' read -r maj min pat <<<"$cur_ver"
case "$bump_kind" in
	patch) pat=$((pat + 1)) ;;
	minor) min=$((min + 1)); pat=0 ;;
	major) maj=$((maj + 1)); min=0; pat=0 ;;
	*)
		# Treat as explicit version. Validate format X.Y.Z.
		if [[ ! "$bump_kind" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
			echo "❌ '$bump_kind' is not patch/minor/major or X.Y.Z" >&2
			exit 2
		fi
		IFS='.' read -r maj min pat <<<"$bump_kind"
		;;
esac

new_ver="${maj}.${min}.${pat}"
new_code=$((cur_code + 1))

# Sanity: monotonic. Refuse to go backwards even if user typed an
# older explicit version — Play Console would reject the upload anyway.
if ! awk -v old="$cur_ver" -v new="$new_ver" 'BEGIN {
	split(old, o, "."); split(new, n, ".");
	for (i = 1; i <= 3; i++) { o[i] += 0; n[i] += 0;
		if (n[i] > o[i]) exit 0;
		if (n[i] < o[i]) exit 1;
	}
	exit 1   # equal counts as not-newer
}'; then
	echo "❌ new version $new_ver is not greater than current $cur_ver" >&2
	exit 1
fi

echo "→ bumping $cur_ver (code $cur_code) → $new_ver (code $new_code)"

# ── Patch files in place ──────────────────────────────────────────────────────

# project.godot
sed -i.bak -E "s/^(config\/version)=\"[^\"]+\"/\1=\"$new_ver\"/" "$PROJECT"
rm -f "$PROJECT.bak"

# export_presets.cfg — both version/name and version/code
sed -i.bak -E "s/^(version\/name)=\"[^\"]+\"/\1=\"$new_ver\"/" "$PRESET"
sed -i.bak -E "s/^(version\/code)=[0-9]+/\1=$new_code/" "$PRESET"
rm -f "$PRESET.bak"

# Cross-check we actually changed both.
got_ver="$(awk -F'"' '/^config\/version/ {print $2}' "$PROJECT")"
got_code="$(awk -F'=' '/^version\/code/ {gsub(/[^0-9]/, "", $2); print $2}' "$PRESET")"
if [[ "$got_ver" != "$new_ver" || "$got_code" != "$new_code" ]]; then
	echo "❌ patch failed (got $got_ver / $got_code) — aborting" >&2
	exit 1
fi

echo "✓ project.godot   config/version=\"$new_ver\""
echo "✓ export_presets  version/name=\"$new_ver\", version/code=$new_code"

# ── Optional commit + tag ─────────────────────────────────────────────────────

if $do_tag; then
	if ! git -C "$ROOT" diff --quiet -- "$PROJECT" "$PRESET"; then
		git -C "$ROOT" add "$PROJECT" "$PRESET"
		git -C "$ROOT" commit -m "chore(release): v$new_ver (versionCode $new_code)"
		git -C "$ROOT" tag -a "v$new_ver" -m "v$new_ver"
		echo "✓ committed and tagged v$new_ver — push with:"
		echo "    git push origin main && git push origin v$new_ver"
	else
		echo "ℹ no changes to commit (already at $new_ver?)"
	fi
fi
