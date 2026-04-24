extends Node

# Autoload: LevelConfig  (res://scripts/managers/LevelConfig.gd)
# Reads levels_config.json once at startup.
# All callers use the public API; never touch _data directly.

const CONFIG_PATH := "res://levels_config.json"

var _data:           Dictionary = {}
var _levels_by_id:   Dictionary = {}   # id(int) → level dict
var _circle_defaults: Dictionary = {}  # "1".."10" → defaults dict

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("LevelConfig: cannot open " + CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("LevelConfig: JSON parse failed or root is not a Dictionary")
		return
	_data = parsed
	_circle_defaults = _data.get("circle_defaults", {})
	for level: Dictionary in _data.get("levels", []):
		_levels_by_id[int(level["id"])] = level

# ── Core query ────────────────────────────────────────────────────────────────

# Returns merged level dict (circle defaults fill missing per-level keys).
func get_level(id: int) -> Dictionary:
	if not _levels_by_id.has(id):
		push_warning("LevelConfig: level %d not found, using defaults" % id)
		return _make_fallback(id)
	var level: Dictionary = _levels_by_id[id].duplicate(true)
	var defaults: Dictionary = _circle_defaults.get(str(level.get("circle", 1)), {})
	for key in ["enemies", "traps", "bonuses", "soul_types"]:
		if not level.has(key) or (level[key] is Array and level[key].is_empty()):
			level[key] = defaults.get(key, [])
	return level

func _make_fallback(id: int) -> Dictionary:
	var circle: int = ceili(float(id) / 10.0)
	return {
		"id": id, "circle": circle, "type": "platformer",
		"souls_count": 1, "static": false, "difficulty": circle,
	}

# ── Type & structure ──────────────────────────────────────────────────────────

func get_level_type(id: int) -> String:
	return get_level(id).get("type", "platformer")

func is_boss_level(id: int) -> bool:
	return get_level_type(id) == "boss"

func is_void_level(id: int) -> bool:
	return get_level_type(id) == "void"

func is_static(id: int) -> bool:
	var lvl: Dictionary = get_level(id)
	if lvl.get("static", false):
		return true
	# Boss levels and circle-opening levels are always hand-crafted
	if lvl.get("type", "") == "boss":
		return true
	if id % 10 == 1:   # first level of each circle
		return true
	return false

func get_circle(id: int) -> int:
	return get_level(id).get("circle", ceili(float(id) / 10.0))

func get_difficulty(id: int) -> int:
	return get_level(id).get("difficulty", 1)

# ── Souls ─────────────────────────────────────────────────────────────────────

func get_souls_count(id: int) -> int:
	var lvl: Dictionary = get_level(id)
	# Prefer explicit souls_count; fall back to soul_types array length
	if lvl.has("souls_count"):
		return int(lvl["souls_count"])
	var types: Array = lvl.get("soul_types", [])
	return types.size()

func get_soul_types(id: int) -> Array:
	return get_level(id).get("soul_types", ["innocent"])

func has_hidden_soul(id: int) -> bool:
	# Explicit flag takes priority; fall back to checking special_mechanics
	var lvl: Dictionary = get_level(id)
	if lvl.get("hidden_soul", false):
		return true
	return has_mechanic(id, "hidden_soul_room")

# ── Enemies & traps ───────────────────────────────────────────────────────────

func get_enemies(id: int) -> Array:
	return get_level(id).get("enemies", [])

func get_traps(id: int) -> Array:
	return get_level(id).get("traps", [])

func get_bonuses(id: int) -> Array:
	return get_level(id).get("bonuses", [])

# ── Special mechanics ─────────────────────────────────────────────────────────

func get_special_mechanics(id: int) -> Array:
	return get_level(id).get("special_mechanics", [])

func has_mechanic(id: int, mechanic: String) -> bool:
	return mechanic in get_special_mechanics(id)

# ── Escape timer ──────────────────────────────────────────────────────────────

func get_escape_time(id: int) -> float:
	return float(get_level(id).get("escape_time", 60.0))

# ── Circle helpers ────────────────────────────────────────────────────────────

func get_circle_theme(circle: int) -> String:
	return _circle_defaults.get(str(circle), {}).get("theme", "grey_stone")

## Returns the tileset id used by a circle's procedural rooms.
## Mapping lives in levels_config.json → circle_defaults["<n>"]["tileset"].
## Falls back to "tileset1" so an unconfigured circle still renders.
func get_circle_tileset(circle: int) -> String:
	return _circle_defaults.get(str(circle), {}).get("tileset", "tileset1")

## Returns the tileset for a specific level. Per-level override (`"tileset"`
## field on the level entry) wins over the circle default. Used so one circle
## can span multiple art sets (e.g. Circle 1: tileset1 for L1-L4, tileset12
## from L5 onwards).
func get_tileset_for_level(id: int) -> String:
	var lvl_tileset: String = get_level(id).get("tileset", "")
	if lvl_tileset != "":
		return lvl_tileset
	return get_circle_tileset(get_circle(id))

func get_levels_in_circle(circle: int) -> Array:
	var result: Array = []
	for level: Dictionary in _data.get("levels", []):
		if level.get("circle", 0) == circle:
			result.append(int(level["id"]))
	return result

func get_level_name(id: int) -> String:
	return get_level(id).get("name", "Рівень %d" % id)

func total_levels() -> int:
	return _levels_by_id.size()
