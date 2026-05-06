extends Node

# Autoload: LevelGenerator
# Usage: var result := LevelGenerator.generate(level_id)

const CONFIG_PATH         := "res://level_generation_config.json"
const SOULS_PATH          := "res://souls_collection.json"
const ROOM_SCENE_PATTERN  := "res://scenes/rooms/circle_%d/room_%s_%d.tscn"

# ── Player / platform physical constants ──────────────────────────────────────
# Mirrors Player.tscn collision and BasePlatform.PLATFORM_HEIGHT.
# Kept here so generation code can reason about spacing without loading scenes.
const PLAYER_WIDTH:    float = 80.0
const PLAYER_HEIGHT:   float = 100.0
const PLATFORM_HEIGHT: float = 30.0

# ── Difficulty zone rules ─────────────────────────────────────────────────────
# Maximum reachable jump height in pixels.
# Derived from Player.gd: jump_force=600, gravity=900 → h = 600²/(2×900) = 200 px.
# Adjust this value when tuning jump_force — zones recalculate automatically.
const MAX_JUMP_HEIGHT: float = 200.0

# Half of max jump. Used as base spacing unit.
const PART_JUMP: float = MAX_JUMP_HEIGHT / 2.0       # 100 px

# Quarter of max jump. Used as spacing step between tiers.
const STEP_JUMP: float = PART_JUMP / 2.0             # 50 px

# Vertical gap between platforms per difficulty tier (in pixels).
const VERTICAL_SPACING := {
	"easy":    PART_JUMP,                             # 100 px
	"medium":  PART_JUMP + STEP_JUMP,                 # 150 px
	"hard":    PART_JUMP + STEP_JUMP * 2.0,           # 200 px — max single jump
	"extreme": MAX_JUMP_HEIGHT,                       # 200 px — moving platforms force timing
}

# Per-level shaft height in screens (1 screen = VIEWPORT_HEIGHT, see
# PlaceholderRoom.VIEWPORT_HEIGHT). Indexed by idx_in_circle (1..9);
# index 0 is unused. Linear ramp from L1=2 to L9=8.
const ROOM_COUNT_BY_IDX: Array[int] = [0, 2, 3, 4, 4, 5, 6, 6, 7, 8]

# Platform type preferences per difficulty tier.
# easy    → wide static shelves (forgiving footing)
# medium  → narrow static shelves (precision)
# hard    → horizontally moving platforms (timing)
# extreme → vertically moving platforms (timing + altitude)
const ZONE_PLATFORMS := {
	"easy":    { "type": "stone",             "width": 220.0 },
	"medium":  { "type": "stone",             "width": 110.0 },
	"hard":    { "type": "moving_horizontal", "width": 110.0 },
	"extreme": { "type": "moving_vertical",   "width": 110.0 },
}

# Platform width bucket distribution for the smooth difficulty curve.
# Each level samples its platforms from these widths, weighted by a
# triangular kernel whose center slides from bucket 0 (220 px, level 1)
# to bucket N-1 (100 px, level 99). This keeps adjacent levels close
# in average width while still letting individual platforms vary —
# instead of every platform on a level being identical.
const PLATFORM_WIDTH_BUCKETS: Array[float] = [220.0, 190.0, 160.0, 130.0, 100.0, 70.0]
# Spread = 2 + center mapping that lands at bucket index 1 for L1 and at
# bucket index N-2 for L99 makes the triangular kernel cover exactly the
# trio [220, 190, 160] at L1 and [130, 100, 70] at L99 (zero weight on the
# others). Mid-game levels temporarily activate four neighbouring buckets
# for a smooth crossfade.
const PLATFORM_WIDTH_SPREAD: float = 2.0

# ── Public result type ────────────────────────────────────────────────────────

class GeneratedLevel:
	var level_id:      int        = 0
	var circle:        int        = 0
	var is_static:     bool       = false
	var is_branch:     bool       = false   # true for branch levels (id > 100)
	var parent_id:     int        = 0       # non-zero for branch levels
	var room_scenes:   Array      = []      # Array[String] — paths to .tscn
	var soul_id:       int        = 0       # 0 = none — primary (named) soul
	var soul_data:     Dictionary = {}
	# Hidden ✦ soul assigned to this level (if any). Stored in
	# souls_collection.json under the per-circle pair `level: 5/8/15/18/...`.
	# LevelBase reads this and spawns a SECOND Soul node with set_hidden(true).
	var hidden_soul_data: Dictionary = {}
	# All souls planned for this level, one dict per spawned soul. Index 0 is
	# always the primary (== soul_data); extras are circle-pool picks unique
	# within this level so two souls can't share a name.
	var souls_data:    Array      = []
	var enemy_count_mod: int      = 0
	var trap_density:  String     = "medium"
	var room_count:    int        = 4
	var circle_style:  String     = ""
	# ── Difficulty zone ──────────────────────────────────────────────────────
	# Tier: "easy" | "medium" | "hard" | "extreme".
	var difficulty_zone:    String  = "easy"
	# Max vertical gap between platforms for this level, in pixels.
	var vertical_spacing:   float   = 280.0
	# Recommended platform type for procedural rooms in this level.
	var platform_type_hint: String  = "stone"
	# Mean recommended platform width in pixels (height always = PLATFORM_HEIGHT).
	# Kept for debug overlay / back-compat; rooms should sample per platform
	# from `platform_width_buckets` weighted by `platform_width_weights`.
	var platform_width:     float   = 220.0
	# Per-level weighted distribution of platform widths. See
	# LevelGenerator.PLATFORM_WIDTH_BUCKETS for the bucket values.
	var platform_width_buckets: Array[float] = []
	var platform_width_weights: Array[float] = []

# ── Internal data ─────────────────────────────────────────────────────────────

var _cfg:   Dictionary = {}
var _souls: Dictionary = {}

var _static_levels: Array = []
var _hidden_soul_levels: Dictionary = {}     # level_id → named soul data (legacy field name; really for primary souls placed by `level` key)
var _hidden_soul_per_level: Dictionary = {}  # level_id → hidden ✦ soul data (H1..H20)

# Per-playthrough soul → level distribution. Built lazily by
# _ensure_distribution() and rebuilt whenever the world seed changes,
# so each soul appears on exactly ONE level per playthrough (no repeats
# between levels in the same Circle). Different seed = different layout.
# Shape: { level_id (int): [soul_dict, soul_dict, …] }
var _distribution: Dictionary  = {}
var _distribution_seed: String = "<unbuilt>"
# Tracks which (circle, type) fallbacks we've already logged this session,
# so the warning fires once per missing room family instead of per room.
var _fallback_logged: Dictionary = {}

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_load_souls()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		_report_error("LevelGenerator: level_generation_config.json not found at %s" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		_report_error("LevelGenerator: failed to parse %s (invalid JSON)" % CONFIG_PATH)
		return
	_cfg = parsed

	var static_cfg: Dictionary = _cfg.get("static_levels", {})
	_static_levels = []
	# JSON numbers come back as floats — normalise to ints so `level_id in
	# _static_levels` (int comparison) matches.
	for raw in static_cfg.get("boss_levels", []):
		_static_levels.append(int(raw))
	for raw in static_cfg.get("circle_openers", {}).get("levels", []):
		_static_levels.append(int(raw))
	for raw in static_cfg.get("milestone_levels", []):
		_static_levels.append(int(raw))

func _load_souls() -> void:
	var file := FileAccess.open(SOULS_PATH, FileAccess.READ)
	if not file:
		_report_warn("LevelGenerator: souls_collection.json not found at %s" % SOULS_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_souls = parsed

	# Build lookup: level_id → soul
	for soul: Dictionary in _souls.get("named_souls", []):
		var lvl: int = soul.get("level", 0)
		if lvl > 0:
			_hidden_soul_levels[lvl] = soul

	# Hidden ✦ souls. Two per circle, placed on specific levels by the
	# `level` key in souls_collection.json. Build a separate per-level
	# lookup so LevelBase can spawn a SECOND Soul node alongside the
	# primary named one.
	for soul: Dictionary in _souls.get("hidden_souls", []):
		var lvl: int = int(soul.get("level", 0))
		if lvl > 0:
			_hidden_soul_per_level[lvl] = soul

# ── Public API ────────────────────────────────────────────────────────────────

# Total named soul targets the player can collect, derived from the loaded
# souls_collection.json. UI uses this for "X / N" counters so the UI scales
# automatically when the named-soul pool grows. Falls back to the JSON's
# explicit `total_named` field, then to the array length, then to 100.
func get_total_named_count() -> int:
	if _souls.has("total_named"):
		return int(_souls["total_named"])
	var arr: Array = _souls.get("named_souls", [])
	return arr.size() if not arr.is_empty() else 100


func get_total_hidden_count() -> int:
	if _souls.has("total_hidden"):
		return int(_souls["total_hidden"])
	var arr: Array = _souls.get("hidden_souls", [])
	return arr.size() if not arr.is_empty() else 20


# Read-only access to the loaded named-soul list. Kept as a method (not a
# public field) so callers don't accidentally mutate the autoload's
# internal state. Used by PauseScreen / Hub stats to compute per-type
# breakdowns without each screen reloading souls_collection.json.
func get_named_souls() -> Array:
	return _souls.get("named_souls", [])


func get_hidden_souls() -> Array:
	return _souls.get("hidden_souls", [])


# Returns GeneratedLevel. For static levels room_scenes will be empty —
# the caller loads the hand-made scene directly via LevelConfig.
func generate(level_id: int) -> GeneratedLevel:
	var result := GeneratedLevel.new()
	result.level_id  = level_id
	result.is_branch = _is_branch(level_id)
	result.parent_id = _parent_of(level_id)

	# Branch levels share their parent's circle
	var effective_id: int = result.parent_id if result.is_branch else level_id
	result.circle = _circle_of(effective_id)

	if _is_static(level_id):
		result.is_static = true
		result.soul_data = _hidden_soul_levels.get(level_id, {})
		result.soul_id   = result.soul_data.get("id", 0)
		if not result.soul_data.is_empty():
			result.souls_data = [result.soul_data]
		# Hidden ✦ souls can also live on static levels (e.g. milestone
		# rooms). Surface them here too.
		result.hidden_soul_data = _hidden_soul_per_level.get(level_id, {})
		return result

	# Seed: deterministic per level; XOR with profile's world seed so players
	# can share/reproduce a run by sharing their seed string.
	var seed_str: String = SaveManager.get_world_seed_str() if SaveManager else ""
	seed(level_id ^ (hash(seed_str) if not seed_str.is_empty() else 0))

	var circle: int = result.circle
	var idx:    int = _index_in_circle(effective_id)   # 1–10
	var diff:   Dictionary = _difficulty_for_index(idx)

	result.enemy_count_mod = diff.get("enemy_count_mod", 0)
	result.trap_density    = diff.get("trap_density", "medium")
	result.room_count      = diff.get("room_count", 4)
	result.circle_style    = _circle_style(circle)

	var zone: Dictionary = _zone_for_level(circle, idx)
	result.difficulty_zone    = zone.get("tier", "easy")
	result.vertical_spacing   = zone.get("spacing", VERTICAL_SPACING["easy"])
	result.platform_type_hint = zone.get("platform_type", "stone")
	result.platform_width     = zone.get("platform_width", 220.0)
	result.platform_width_buckets = zone.get("platform_width_buckets", PLATFORM_WIDTH_BUCKETS)
	result.platform_width_weights = zone.get("platform_width_weights", [])

	result.room_scenes = _pick_rooms(circle, result.room_count)
	result.soul_data   = _soul_for_level(level_id, circle)
	result.soul_id     = result.soul_data.get("id", 0)

	# Pick souls_count unique entries (primary + extras) so spawned souls on
	# the same level all carry distinct names. souls_count comes from the
	# level config; default 1 if it isn't set.
	var souls_n: int = LevelConfig.get_souls_count(level_id) if LevelConfig else 1
	result.souls_data = _souls_for_level(level_id, circle, maxi(1, souls_n))

	# Hidden ✦ soul (one extra Soul node, set_hidden(true), placed
	# off-path by LevelBase). Two per circle on specific levels —
	# see _load_souls.
	result.hidden_soul_data = _hidden_soul_per_level.get(level_id, {})

	return result

func is_static(level_id: int) -> bool:
	return _is_static(level_id)

## Fallback entry point — runs the procedural path even for static-flagged
## levels. LevelBase calls this for circle-opener levels (1, 11, 21…) when
## no hand-authored content is present in the scene tree.
func generate_procedural(level_id: int) -> GeneratedLevel:
	var was_static: bool = _is_static(level_id)
	if was_static:
		_static_levels.erase(level_id)
	var result := generate(level_id)
	if was_static:
		_static_levels.append(level_id)
	return result

## Returns true if level_id is a branch level (id > 100, branches of circles 1-9).
func is_branch(level_id: int) -> bool:
	return _is_branch(level_id)

## Returns the parent level ID for a branch level, or 0 for main levels.
func get_parent_id(level_id: int) -> int:
	return _parent_of(level_id)

# Returns the soul dict for a given level (used by arena scenes for display).
func get_soul_data(level_id: int) -> Dictionary:
	return _soul_for_level(level_id, _circle_of(level_id))

# ── Room picking ──────────────────────────────────────────────────────────────

func _pick_rooms(circle: int, count: int) -> Array:
	var pool_key := "circle_%d" % circle
	var pool: Dictionary = _cfg.get("procedural_levels", {}).get("room_pools", {}).get(pool_key, {})
	var pool_size: int = pool.get("rooms_count", 20)

	var rooms: Array = []

	# Entrance (always room index 1)
	rooms.append(_resolve_room_path(circle, "entrance", 1))

	# Main rooms (random, no repeats within one level)
	var main_count: int = count - 2  # minus entrance and exit
	var used: Array = []
	for _i in main_count:
		var idx: int = _pick_unique_room_index(used, pool_size)
		rooms.append(_resolve_room_path(circle, "main", idx))
		used.append(idx)

	# Exit (always room index 1)
	rooms.append(_resolve_room_path(circle, "exit", 1))

	return rooms

## Resolve room scene path with fallback to circle_1 when per-circle art
## is not yet authored. LevelBase overwrites `circle` on the loaded room
## so PlaceholderRoom uses the correct theme + enemy pool regardless.
func _resolve_room_path(circle: int, type: String, idx: int) -> String:
	var path := ROOM_SCENE_PATTERN % [circle, type, idx]
	if ResourceLoader.exists(path):
		return path
	# Fallback — circle_1 scenes work for any circle since PlaceholderRoom
	# drives visuals and enemy spawning off its `circle` property.
	var fallback_idx: int = idx
	if type == "main":
		# Clamp main index to what circle_1 ships with (24 variants).
		fallback_idx = ((idx - 1) % 24) + 1
	var key: String = "%d/%s" % [circle, type]
	if not _fallback_logged.has(key):
		_fallback_logged[key] = true
		_report_warn("LevelGenerator: circle %d has no '%s' rooms — falling back to circle_1 for this type" % [circle, type])
	return ROOM_SCENE_PATTERN % [1, type, fallback_idx]

# ── DebugOverlay forwarders ───────────────────────────────────────────────────
func _report_error(msg: String) -> void:
	var d: Node = Engine.get_main_loop().root.get_node_or_null("DebugOverlay") if Engine.get_main_loop() else null
	if d and d.has_method("error"):
		d.error(msg)
	else:
		push_error(msg)

func _report_warn(msg: String) -> void:
	var d: Node = Engine.get_main_loop().root.get_node_or_null("DebugOverlay") if Engine.get_main_loop() else null
	if d and d.has_method("warn"):
		d.warn(msg)
	else:
		push_warning(msg)

func _pick_unique_room_index(used: Array, pool_size: int) -> int:
	if used.size() >= pool_size:
		# Fallback: allow repeats if pool exhausted
		return randi_range(1, pool_size)
	var idx: int = randi_range(1, pool_size)
	var attempts: int = 0
	while idx in used and attempts < 50:
		idx = randi_range(1, pool_size)
		attempts += 1
	return idx

# ── Soul placement ────────────────────────────────────────────────────────────

func _soul_for_level(level_id: int, _circle: int) -> Dictionary:
	# `circle` is unused now that the distribution is keyed purely by
	# level_id — kept in the signature so the existing call sites
	# (and the symmetric _souls_for_level companion) don't churn.
	# Legacy path: souls with explicit `level: N` in JSON win. After the
	# 2026 unpinning all 100 originals were set to level=0, so this is
	# normally empty — kept so future hand-pinned souls still work.
	if _hidden_soul_levels.has(level_id):
		return _hidden_soul_levels[level_id]

	_ensure_distribution()
	var assigned: Array = _distribution.get(level_id, [])
	if assigned.is_empty():
		return {}
	return assigned[0]


# Returns up to `count` souls assigned to this level by the per-playthrough
# distribution. Each soul appears on exactly ONE level per playthrough, so
# the player never meets the same soul twice in a single run.
func _souls_for_level(level_id: int, _circle: int, count: int) -> Array:
	_ensure_distribution()
	var assigned: Array = _distribution.get(level_id, []).duplicate()
	while assigned.size() > count:
		assigned.pop_back()
	return assigned


# Build (or rebuild after seed change) the per-circle distribution. Each
# circle's pool is shuffled with a circle-specific seed derived from the
# world seed, then handed out to that circle's levels in declaration
# order — taking souls_count souls per level. With pool size matching
# total spawn slots, every soul gets a level and no level shares a soul
# with another.
func _ensure_distribution() -> void:
	var current_seed: String = ""
	if SaveManager and SaveManager.has_method("get_world_seed_str"):
		current_seed = String(SaveManager.get_world_seed_str())
	if current_seed == _distribution_seed and not _distribution.is_empty():
		return
	_build_distribution(current_seed)
	_distribution_seed = current_seed


func _build_distribution(seed_str: String) -> void:
	_distribution.clear()
	if not LevelConfig:
		return
	var base_seed: int = hash(seed_str) if not seed_str.is_empty() else 0

	for circle in range(1, 11):
		# All pool souls in this circle (pinned ones — level > 0 — already
		# handled via _hidden_soul_levels and aren't in the distribution).
		var pool: Array = []
		for soul: Dictionary in _souls.get("named_souls", []):
			if int(soul.get("circle", 0)) == circle and int(soul.get("level", 0)) == 0:
				pool.append(soul)

		# Fisher-Yates shuffle with an explicit per-circle RNG so different
		# circles aren't correlated with each other and the layout reproduces
		# from world_seed alone.
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed ^ (circle * 0x9E3779B1)
		for i in range(pool.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp: Dictionary = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp

		# Walk this circle's levels in config-declaration order, taking
		# souls_count souls per level from the front of the shuffled pool.
		var level_ids: Array = LevelConfig.get_levels_in_circle(circle)
		var idx: int = 0
		for lvl_id_v in level_ids:
			var lvl_id: int = int(lvl_id_v)
			var n: int = max(1, LevelConfig.get_souls_count(lvl_id))
			var assigned: Array = []
			for _k in n:
				if idx >= pool.size():
					break  # pool exhausted — extra slots stay empty
				assigned.append(pool[idx])
				idx += 1
			_distribution[lvl_id] = assigned

# ── Difficulty ────────────────────────────────────────────────────────────────

func _difficulty_for_index(idx_in_circle: int) -> Dictionary:
	var inj: Dictionary = _cfg.get("difficulty_injection", {})
	var base: Dictionary
	if idx_in_circle <= 3:
		base = inj.get("levels_1_3", {"enemy_count_mod": -1, "trap_density": "low",    "room_count": 3})
	elif idx_in_circle <= 6:
		base = inj.get("levels_4_6", {"enemy_count_mod":  0, "trap_density": "medium", "room_count": 4})
	else:
		base = inj.get("levels_7_9", {"enemy_count_mod": +1, "trap_density": "high",   "room_count": 5})
	# Per-level shaft length in screens. See ROOM_COUNT_BY_IDX for the full
	# ramp (L1=2 … L9=8). Same-zone adjacent pairs (3,4) and (6,7) share their
	# room_count by design — uniqueness there comes from seeded RNG in
	# PlaceholderRoom.
	var room_count: int = ROOM_COUNT_BY_IDX[clampi(idx_in_circle, 1, 9)]
	return {
		"enemy_count_mod": base.get("enemy_count_mod", 0),
		"trap_density":    base.get("trap_density",    "medium"),
		"room_count":      room_count,
	}

# ── Platform path validation ─────────────────────────────────────────────────
#
# A valid room must have at least one continuous path:
#   • bottom → top : every row reachable from the floor by chained jumps
#   • top → bottom : always valid — player can drop freely at any time
#
# Moving platforms change the reachability math:
#   • moving_horizontal : Y is fixed → same as static for vertical validation
#   • moving_vertical   : platform travels upward by |distance| px.
#                         Player can ride it to the top and jump from there,
#                         so the effective launch Y = rest_y − v_range.
#                         This extends the reachable height beyond MAX_JUMP_HEIGHT.
#
# Each entry in `platforms`:
#   { "y":        float  ← rest-position Y (= max_y for moving_vertical,
#                          since distance is negative → platform goes UP)
#     "v_range":  float  ← upward travel in px:
#                            static / moving_horizontal → 0
#                            moving_vertical            → abs(min(0, distance))
#                            e.g. distance=-80 → v_range=80
#   }
#
# So for moving_vertical:
#   land_y   = y                 (player can land when platform is at bottom)
#   launch_y = y − v_range       (player jumps when platform is at its top)
#   effective reach = y − v_range − MAX_JUMP_HEIGHT
#
# Usage:
#   var ok = LevelGenerator.validate_vertical_path(platforms, floor_y)
#   var bridges = LevelGenerator.missing_bridge_ys(platforms, floor_y)

## Helper: compute v_range from MovingPlatform parameters.
## type:     platform type string ("moving_vertical", "moving_horizontal", etc.)
## distance: signed offset used by MovingPlatform (negative = upward for vertical)
func platform_v_range(type: String, distance: float) -> float:
	if type == "moving_vertical":
		return absf(minf(distance, 0.0))
	return 0.0

## Returns true when every platform row is reachable from `floor_y`.
func validate_vertical_path(platforms: Array, floor_y: float) -> bool:
	return missing_bridge_ys(platforms, floor_y).is_empty()

## Returns Array[float] of Y positions where bridge platforms must be added.
## Empty array means the layout is already fully connected.
##
## Algorithm:
##   1. Build (land_y, launch_y) pairs for every row + floor.
##      launch_y = land_y − v_range  (moving_vertical rises, giving a higher
##      jump-off point; static/horizontal: launch_y = land_y).
##   2. Sort floor-first (descending Y).
##   3. Greedy upward pass: maintain a set of reachable launch Ys.
##      A row is reachable if (best_launch_y − land_y) ≤ MAX_JUMP_HEIGHT.
##      If not reachable, insert evenly-spaced bridges to close the gap.
func missing_bridge_ys(platforms: Array, floor_y: float) -> Array:
	# Build entries: { land_y, launch_y }
	# Floor is always a reachable surface; it has no upward travel.
	var entries: Array = [{ "land_y": floor_y, "launch_y": floor_y }]

	for p in platforms:
		var land_y:  float = float(p.get("y", 0.0))
		var v_range: float = float(p.get("v_range", 0.0))
		var launch_y: float = land_y - v_range   # highest point the player can jump from

		var merged: bool = false
		for e in entries:
			if absf(float(e.land_y) - land_y) < 5.0:
				# Keep the better (lower Y = higher on screen) launch point.
				if launch_y < float(e.launch_y):
					e.launch_y = launch_y
				merged = true
				break
		if not merged:
			entries.append({ "land_y": land_y, "launch_y": launch_y })

	# Sort descending — floor (max Y) first, topmost row last.
	entries.sort_custom(func(a, b): return float(a.land_y) > float(b.land_y))

	# Greedy upward pass.
	# available_launches tracks the lowest (= highest on screen) Y we can jump from.
	var best_launch: float = floor_y   # initially only the floor
	var bridges: Array = []

	for i in range(1, entries.size()):
		var land_y:   float = float(entries[i].land_y)
		var launch_y: float = float(entries[i].launch_y)
		var gap:      float = best_launch - land_y

		if gap <= MAX_JUMP_HEIGHT:
			# Row is reachable — update best launch if this platform goes higher.
			if launch_y < best_launch:
				best_launch = launch_y
		else:
			# Gap too large — fill with static bridges.
			var steps:     int   = ceili(gap / MAX_JUMP_HEIGHT)
			var step_size: float = gap / float(steps)
			for s in range(1, steps):
				var bridge_y: float = best_launch - step_size * float(s)
				bridges.append(bridge_y)
			# After bridges the row becomes reachable; update best_launch.
			best_launch = minf(best_launch, launch_y)

	return bridges

# ── Difficulty zones (vertical spacing + platform type) ───────────────────────
#
# Two axes drive the zone:
#   1. Circle number (1-10) — macro progression across the game
#   2. Index within circle (1-9) — micro progression inside each circle
#
# Circles 1-3 cap at "hard"; circles 4-7 stretch to "extreme" in the back
# third; circles 8-10 sit in "hard"/"extreme" for most of the run. Zones drive
# what procedural rooms should look like, not hand-authored static levels.
func _zone_for_level(circle: int, idx_in_circle: int) -> Dictionary:
	var tier: String = _zone_tier(circle, idx_in_circle)
	var override_tier: String = _cfg.get("difficulty_zones", {}).get("override", {}).get(str(circle), "")
	if override_tier != "":
		tier = override_tier
	var platform: Dictionary = ZONE_PLATFORMS.get(tier, ZONE_PLATFORMS["easy"])
	# Tier still drives platform_type (stone vs moving). Width and spacing
	# come from a global smooth curve so adjacent levels don't lurch.
	var t: float = _difficulty_t(circle, idx_in_circle)
	var weights: Array[float] = _platform_width_weights_for_t(t)
	var mean_width: float = _weighted_mean(PLATFORM_WIDTH_BUCKETS, weights)
	var smooth_spacing: float = lerpf(100.0, 200.0, t)
	return {
		"tier":           tier,
		"spacing":        smooth_spacing,
		"platform_type":  platform.get("type", "stone"),
		"platform_width": mean_width,
		"platform_width_buckets": PLATFORM_WIDTH_BUCKETS,
		"platform_width_weights": weights,
	}

## Smooth global difficulty parameter in [0, 1] from level 1 (t=0) to level
## 99 (t=1). Used to slide the platform width distribution and vertical
## spacing across the whole game.
func _difficulty_t(circle: int, idx_in_circle: int) -> float:
	var global_level: float = float((circle - 1) * 10 + idx_in_circle)
	return clampf((global_level - 1.0) / 98.0, 0.0, 1.0)

## Triangular kernel over PLATFORM_WIDTH_BUCKETS. The kernel center slides
## from bucket 1 at t=0 (L1) to bucket N-2 at t=1 (L99), with spread=2,
## so the active window is exactly the bucket trio at each endpoint:
##   t=0    → [0.5, 1.0, 0.5, 0,   0,   0  ]  L1   uses [220, 190, 160]
##   t=0.5  → [0,   0.25,0.75,0.75,0.25,0  ]  mid  crossfade
##   t=1    → [0,   0,   0,   0.5, 1.0, 0.5]  L99  uses [130, 100, 70]
func _platform_width_weights_for_t(t: float) -> Array[float]:
	var n: int = PLATFORM_WIDTH_BUCKETS.size()
	var center: float = 1.0 + t * float(n - 3)
	var out: Array[float] = []
	for i in n:
		var w: float = maxf(0.0, 1.0 - absf(float(i) - center) / PLATFORM_WIDTH_SPREAD)
		out.append(w)
	return out

func _weighted_mean(values: Array, weights: Array) -> float:
	var total_w: float = 0.0
	var total_v: float = 0.0
	for i in values.size():
		var w: float = float(weights[i])
		total_v += float(values[i]) * w
		total_w += w
	return total_v / total_w if total_w > 0.0 else float(values[0])

## Sample a platform width from the per-level weighted bucket distribution.
## Pass the GeneratedLevel's `platform_width_buckets` and
## `platform_width_weights`. Falls back to the first bucket if weights are
## empty. Uses the supplied RNG so per-room layouts stay deterministic.
static func sample_platform_width(buckets: Array, weights: Array,
		rng: RandomNumberGenerator) -> float:
	if buckets.is_empty():
		return 160.0
	if weights.size() != buckets.size():
		return float(buckets[0])
	var total_w: float = 0.0
	for w in weights:
		total_w += float(w)
	if total_w <= 0.0:
		return float(buckets[0])
	var pick: float = rng.randf() * total_w
	var acc: float = 0.0
	for i in buckets.size():
		acc += float(weights[i])
		if pick <= acc:
			return float(buckets[i])
	return float(buckets[buckets.size() - 1])

func _zone_tier(circle: int, idx_in_circle: int) -> String:
	# Base tier from index within circle.
	# Finer breakpoints so adjacent levels land in different zones:
	#   idx=1 → easy; idx=2-4 → medium; idx=5-7 → hard; idx=8-9 → extreme.
	var base: String
	if idx_in_circle <= 1:
		base = "easy"
	elif idx_in_circle <= 4:
		base = "medium"
	elif idx_in_circle <= 7:
		base = "hard"
	else:
		base = "extreme"
	# Circle escalation — later circles bump the tier up.
	var tiers: Array = ["easy", "medium", "hard", "extreme"]
	var bump: int = 0
	if circle >= 8:
		bump = 2
	elif circle >= 4:
		bump = 1
	var idx: int = clampi(tiers.find(base) + bump, 0, tiers.size() - 1)
	return tiers[idx]

# Public lookup — useful for room scripts / debug overlays that need to know
# the spacing and platform preference for the level they were spawned into.
func get_zone(level_id: int) -> Dictionary:
	var effective_id: int = _parent_of(level_id) if _is_branch(level_id) else level_id
	var circle: int = _circle_of(effective_id)
	var idx: int = _index_in_circle(effective_id)
	return _zone_for_level(circle, idx)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_static(level_id: int) -> bool:
	return level_id in _static_levels

## Branch levels have id > 100. Their parent = level_id - 100.
## Branch IDs: 103–109 (circle 1), 113–119 (circle 2), …, 183–189 (circle 9).
func _is_branch(level_id: int) -> bool:
	return level_id > 100

func _parent_of(level_id: int) -> int:
	if _is_branch(level_id):
		return level_id - 100
	return 0

func _circle_of(level_id: int) -> int:
	# For main levels 1-100: circle = ceil(id / 10)
	# Branch levels should never reach here directly; generate() passes effective_id.
	return ceili(float(level_id) / 10.0)

func _index_in_circle(level_id: int) -> int:
	return ((level_id - 1) % 10) + 1

func _circle_style(circle: int) -> String:
	var pool_key := "circle_%d" % circle
	var pool: Dictionary = _cfg.get("procedural_levels", {}).get("room_pools", {}).get(pool_key, {})
	return pool.get("style", "")
