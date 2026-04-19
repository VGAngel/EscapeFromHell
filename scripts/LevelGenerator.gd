extends Node

# Autoload: LevelGenerator
# Usage: var result := LevelGenerator.generate(level_id)

const CONFIG_PATH         := "res://level_generation_config.json"
const SOULS_PATH          := "res://souls_collection.json"
const ROOM_SCENE_PATTERN  := "res://scenes/rooms/circle_%d/room_%s_%d.tscn"

# ── Public result type ────────────────────────────────────────────────────────

class GeneratedLevel:
	var level_id:      int      = 0
	var circle:        int      = 0
	var is_static:     bool     = false
	var room_scenes:   Array    = []   # Array[String] — paths to .tscn
	var soul_id:       int      = 0    # 0 = none
	var soul_data:     Dictionary = {}
	var enemy_count_mod: int    = 0
	var trap_density:  String   = "medium"
	var room_count:    int      = 4
	var circle_style:  String   = ""

# ── Internal data ─────────────────────────────────────────────────────────────

var _cfg:   Dictionary = {}
var _souls: Dictionary = {}

var _static_levels: Array = []
var _hidden_soul_levels: Dictionary = {}  # level_id → soul data

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_load_souls()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("LevelGenerator: level_generation_config.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("LevelGenerator: failed to parse level_generation_config.json")
		return
	_cfg = parsed

	var static_cfg: Dictionary = _cfg.get("static_levels", {})
	_static_levels = []
	_static_levels.append_array(static_cfg.get("boss_levels", []))
	_static_levels.append_array(static_cfg.get("circle_openers", {}).get("levels", []))
	_static_levels.append_array(static_cfg.get("milestone_levels", []))

func _load_souls() -> void:
	var file := FileAccess.open(SOULS_PATH, FileAccess.READ)
	if not file:
		push_warning("LevelGenerator: souls_collection.json not found")
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

	# Hidden souls with explicit levels also mark those levels as static
	for soul: Dictionary in _souls.get("hidden_souls", []):
		var lvl: int = soul.get("level", 0)
		if lvl > 0 and lvl not in _static_levels:
			_static_levels.append(lvl)

# ── Public API ────────────────────────────────────────────────────────────────

# Returns GeneratedLevel. For static levels room_scenes will be empty —
# the caller loads the hand-made scene directly via LevelConfig.
func generate(level_id: int) -> GeneratedLevel:
	var result := GeneratedLevel.new()
	result.level_id = level_id
	result.circle   = _circle_of(level_id)

	if _is_static(level_id):
		result.is_static = true
		result.soul_data = _hidden_soul_levels.get(level_id, {})
		result.soul_id   = result.soul_data.get("id", 0)
		return result

	# Seed: same level always produces the same layout
	seed(level_id)

	var circle:    int    = result.circle
	var idx:       int    = _index_in_circle(level_id)   # 1–10
	var diff:      Dictionary = _difficulty_for_index(idx)

	result.enemy_count_mod = diff.get("enemy_count_mod", 0)
	result.trap_density    = diff.get("trap_density", "medium")
	result.room_count      = diff.get("room_count", 4)
	result.circle_style    = _circle_style(circle)

	result.room_scenes = _pick_rooms(circle, result.room_count)
	result.soul_data   = _soul_for_level(level_id, circle)
	result.soul_id     = result.soul_data.get("id", 0)

	return result

func is_static(level_id: int) -> bool:
	return _is_static(level_id)

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
	rooms.append(ROOM_SCENE_PATTERN % [circle, "entrance", 1])

	# Main rooms (random, no repeats within one level)
	var main_count: int = count - 2  # minus entrance and exit
	var used: Array = []
	for _i in main_count:
		var idx: int = _pick_unique_room_index(used, pool_size)
		rooms.append(ROOM_SCENE_PATTERN % [circle, "main", idx])
		used.append(idx)

	# Exit (always room index 1)
	rooms.append(ROOM_SCENE_PATTERN % [circle, "exit", 1])

	return rooms

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

func _soul_for_level(level_id: int, circle: int) -> Dictionary:
	# Named soul assigned directly to this level
	if _hidden_soul_levels.has(level_id):
		return _hidden_soul_levels[level_id]

	# Fallback: pick any unassigned soul from the circle's pool
	var candidates: Array = []
	for soul: Dictionary in _souls.get("named_souls", []):
		if soul.get("circle", 0) == circle and soul.get("level", 0) == 0:
			candidates.append(soul)
	if candidates.is_empty():
		return {}
	return candidates[randi() % candidates.size()]

# ── Difficulty ────────────────────────────────────────────────────────────────

func _difficulty_for_index(idx_in_circle: int) -> Dictionary:
	var inj: Dictionary = _cfg.get("difficulty_injection", {})
	if idx_in_circle <= 3:
		return inj.get("levels_1_3", {"enemy_count_mod": -1, "trap_density": "low",    "room_count": 3})
	elif idx_in_circle <= 6:
		return inj.get("levels_4_6", {"enemy_count_mod":  0, "trap_density": "medium", "room_count": 4})
	else:
		return inj.get("levels_7_9", {"enemy_count_mod": +1, "trap_density": "high",   "room_count": 5})

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_static(level_id: int) -> bool:
	return level_id in _static_levels

func _circle_of(level_id: int) -> int:
	return ceili(float(level_id) / 10.0)

func _index_in_circle(level_id: int) -> int:
	return ((level_id - 1) % 10) + 1

func _circle_style(circle: int) -> String:
	var pool_key := "circle_%d" % circle
	var pool: Dictionary = _cfg.get("procedural_levels", {}).get("room_pools", {}).get(pool_key, {})
	return pool.get("style", "")
