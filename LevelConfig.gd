extends Node

# Autoload: add to Project > Project Settings > Autoload as "LevelConfig"

const CONFIG_PATH := "res://levels_config.json"

var _data: Dictionary = {}
var _levels_by_id: Dictionary = {}
var _circle_defaults: Dictionary = {}

func _ready() -> void:
	_load()

func _load() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("LevelConfig: cannot open " + CONFIG_PATH)
		return
	_data = JSON.parse_string(file.read_as_text())
	file.close()

	_circle_defaults = _data.get("circle_defaults", {})

	for level: Dictionary in _data.get("levels", []):
		_levels_by_id[level["id"]] = level

# Returns the raw level dict (merges circle defaults for missing keys).
func get_level(id: int) -> Dictionary:
	if not _levels_by_id.has(id):
		push_warning("LevelConfig: level %d not found" % id)
		return {}
	var level: Dictionary = _levels_by_id[id].duplicate(true)
	var circle_key := str(level.get("circle", 0))
	var defaults: Dictionary = _circle_defaults.get(circle_key, {})
	# Fill only keys that the level did not explicitly define.
	for key in ["enemies", "traps", "bonuses"]:
		if not level.has(key) or level[key].is_empty():
			level[key] = defaults.get(key, [])
	return level

func get_level_type(id: int) -> String:
	return get_level(id).get("type", "")

func get_souls_count(id: int) -> int:
	return get_level(id).get("souls_count", 0)

func get_soul_types(id: int) -> Array:
	return get_level(id).get("soul_types", [])

func get_enemies(id: int) -> Array:
	return get_level(id).get("enemies", [])

func get_traps(id: int) -> Array:
	return get_level(id).get("traps", [])

func get_bonuses(id: int) -> Array:
	return get_level(id).get("bonuses", [])

func get_special_mechanics(id: int) -> Array:
	return get_level(id).get("special_mechanics", [])

func get_difficulty(id: int) -> int:
	return get_level(id).get("difficulty", 1)

func get_circle(id: int) -> int:
	return get_level(id).get("circle", 1)

func get_circle_theme(circle: int) -> String:
	var key := str(circle)
	return _circle_defaults.get(key, {}).get("theme", "grey_stone")

# Returns all level ids belonging to a circle.
func get_levels_in_circle(circle: int) -> Array:
	var result: Array = []
	for level: Dictionary in _data.get("levels", []):
		if level.get("circle", 0) == circle:
			result.append(level["id"])
	return result

func has_mechanic(id: int, mechanic: String) -> bool:
	return mechanic in get_special_mechanics(id)

func is_boss_level(id: int) -> bool:
	return get_level_type(id) == "boss"

func is_void_level(id: int) -> bool:
	return get_level_type(id) == "void"

func total_levels() -> int:
	return _levels_by_id.size()
