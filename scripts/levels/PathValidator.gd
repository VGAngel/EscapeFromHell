extends RefCounted
class_name PathValidator

# Pure path validator for vertical shaft layouts. No autoloads, no scene tree —
# takes an array of platforms and reports issues found by the two play paths:
#
#   1. DOWN-path (altar → portal): player walks off platform edges, never
#      jumps. Each walk-off must land on a platform within NO_DAMAGE_FALL
#      vertical (= tier-0 fall band, no HP cost).
#
#   2. UP-path (portal → altar): player jumps platform-to-platform. Each
#      next-up platform must be within physical jump reach (vertical ≤
#      MAX_JUMP_HEIGHT, horizontal ≤ _max_horizontal_jump(v_gap) +
#      half-widths).
#
# Platform format (Dictionary):
#   { "x": float, "y": float, "w": float, "label": String (optional) }
#
# Issue format:
#   { "row": int, "label": String, "path": "down"|"up",
#     "side": "left"|"right"|"both"|"-", "problem": String, "details": Dict }
#
# Tests in tests/unit/test_path_validator.gd lock in the contracts.

# ── Physics constants (mirror Player.gd / LevelGenerator.gd) ──────────────────
const MAX_JUMP_HEIGHT:    float = 200.0   # LevelGenerator.MAX_JUMP_HEIGHT
const WALK_SPEED:         float = 180.0   # Player.walk_speed
const GRAVITY:            float = 900.0   # Player.gravity
const JUMP_FORCE:         float = 600.0   # Player.jump_force
const NO_DAMAGE_FALL_PX:  float = 300.0   # tier-0 fall band — Player FALL_DAMAGE_TIERS
const SAME_LEVEL_REACH:   float = 240.0
const MAX_UP_REACH:       float = 120.0
const REACH_SLACK_FACTOR: float = 1.15    # mirrors PlaceholderRoom._max_horizontal_jump

# ── Public API ────────────────────────────────────────────────────────────────

## Validate the descent path: each platform must let the player walk off
## either edge and land somewhere within NO_DAMAGE_FALL_PX (≈ tier-0).
## Returns an array of issue dicts; empty array = path is clean.
static func validate_down_path(platforms: Array) -> Array:
	var issues: Array = []
	if platforms.size() < 2:
		return issues
	# Sort top-to-bottom in screen coords (smaller Y = higher in Godot 2D).
	var sorted: Array = _sorted_top_to_bottom(platforms)
	# Skip the last (lowest) platform — nothing to fall onto.
	for i in sorted.size() - 1:
		var top: Dictionary = sorted[i]
		var top_y: float = float(top.y)
		var top_left:  float = float(top.x) - float(top.w) * 0.5
		var top_right: float = float(top.x) + float(top.w) * 0.5
		# Each edge gets its own walk-off check. _find_walk_off_landing only
		# returns landings reachable within the tier-0 fall band, so an
		# empty result means "any walk-off here costs HP" — flag it.
		for side_data in [["left", top_left, -WALK_SPEED], ["right", top_right, WALK_SPEED]]:
			var side:    String = String(side_data[0])
			var edge_x:  float  = float(side_data[1])
			var vel_x:   float  = float(side_data[2])
			var landing: Dictionary = _find_walk_off_landing(sorted, top_y, edge_x, vel_x)
			if landing.is_empty():
				issues.append(_make_issue(top, i, "down", side,
					"walk-off has no tier-0 landing — would fall > %d px (damage)" \
						% int(NO_DAMAGE_FALL_PX),
					{"edge_x": edge_x}))
	return issues

## Validate the climb path: from each platform, at least one platform UP
## (smaller Y) must be within physical jump reach.
static func validate_up_path(platforms: Array) -> Array:
	var issues: Array = []
	if platforms.size() < 2:
		return issues
	# Sort bottom-to-top so we walk up the shaft.
	var sorted: Array = _sorted_top_to_bottom(platforms)
	sorted.reverse()
	# Skip the last (highest) platform — nothing to jump UP to.
	for i in sorted.size() - 1:
		var bot: Dictionary = sorted[i]
		var has_reachable: bool = false
		var nearest_up: Dictionary = {}
		var nearest_v_gap: float = INF
		for j in range(i + 1, sorted.size()):
			var up: Dictionary = sorted[j]
			var v_gap: float = float(bot.y) - float(up.y)
			if v_gap > MAX_JUMP_HEIGHT:
				break  # everything above is even higher → unreachable
			var max_h: float = _max_horizontal_jump(v_gap)
			var max_center: float = max_h + (float(bot.w) + float(up.w)) * 0.5
			var dx: float = absf(float(up.x) - float(bot.x))
			if dx <= max_center:
				has_reachable = true
				break
			if v_gap < nearest_v_gap:
				nearest_v_gap = v_gap
				nearest_up = up
		if not has_reachable:
			var details: Dictionary = {}
			if not nearest_up.is_empty():
				details["nearest_up_label"] = String(nearest_up.get("label", ""))
				details["nearest_up_x"]     = float(nearest_up.x)
				details["nearest_v_gap"]    = nearest_v_gap
			issues.append(_make_issue(bot, i, "up", "-",
				"no reachable platform UP — climb path broken here",
				details))
	return issues

## Convenience: run both validators and return combined issues.
static func validate_all(platforms: Array) -> Array:
	var combined: Array = []
	combined.append_array(validate_down_path(platforms))
	combined.append_array(validate_up_path(platforms))
	return combined

# ── Internals ─────────────────────────────────────────────────────────────────

# Mirrors PlaceholderRoom._max_horizontal_jump.
static func _max_horizontal_jump(v_gap: float) -> float:
	if v_gap <= 0.0:
		return SAME_LEVEL_REACH * REACH_SLACK_FACTOR
	var t: float = clampf(v_gap / MAX_JUMP_HEIGHT, 0.0, 1.0)
	return lerpf(SAME_LEVEL_REACH, MAX_UP_REACH, t) * REACH_SLACK_FACTOR

# Find the highest platform within tier-0 fall range that the player can
# actually reach by walking off `edge_x`. Player retains full horizontal
# control mid-air (air_acceleration ≥ walk_speed deceleration), so the
# reachable X-band at any landing Y is [edge_x - walk × t, edge_x + walk × t].
# Returns the highest such platform, or {} if no tier-0 landing exists.
# vel_x is unused in the lenient model but kept for API symmetry.
static func _find_walk_off_landing(sorted_top_to_bottom: Array, top_y: float,
		edge_x: float, _vel_x: float) -> Dictionary:
	for p in sorted_top_to_bottom:
		var py: float = float(p.y)
		if py <= top_y:
			continue
		var dy: float = py - top_y
		if dy > NO_DAMAGE_FALL_PX:
			break  # everything below would damage; tier-0 candidates exhausted
		var t: float = sqrt(2.0 * dy / GRAVITY)
		var reach: float = WALK_SPEED * t
		var band_l: float = edge_x - reach
		var band_r: float = edge_x + reach
		var pl: float = float(p.x) - float(p.w) * 0.5
		var pr: float = float(p.x) + float(p.w) * 0.5
		# X-overlap between reachable band and platform footprint?
		if maxf(band_l, pl) <= minf(band_r, pr):
			return p.duplicate()
	return {}

static func _sorted_top_to_bottom(platforms: Array) -> Array:
	var out: Array = platforms.duplicate()
	out.sort_custom(func(a, b): return float(a.y) < float(b.y))
	return out

static func _make_issue(p: Dictionary, idx: int, path: String,
		side: String, problem: String, details: Dictionary) -> Dictionary:
	return {
		"row":     idx,
		"label":   String(p.get("label", "")),
		"x":       float(p.x),
		"y":       float(p.y),
		"w":       float(p.w),
		"path":    path,
		"side":    side,
		"problem": problem,
		"details": details,
	}
