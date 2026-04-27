extends Node

# Autoload: SaveManager  (res://scripts/managers/SaveManager.gd)
# Single source of truth for all persistent game state.
# All writes stay in-memory until _flush() is called.
# _flush() is called: after level complete, on app pause, on window close.

const SAVE_DIR     := "user://saves/"
const SAVE_VERSION := 2
const MAX_SLOTS    := 3
const CLOUD_ENABLED := false

var _slot: int = 0
var data: Dictionary = {}   # public for debug inspection; use methods to mutate

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_dir()
	_reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush()

# ── Slot management ───────────────────────────────────────────────────────────

func get_slot() -> int:
	return _slot

func load_slot(slot: int) -> bool:
	_slot = clampi(slot, 0, MAX_SLOTS - 1)
	return _load()

func has_save(slot: int = -1) -> bool:
	var s: int = slot if slot >= 0 else _slot
	return FileAccess.file_exists(_save_path(s))

func get_all_slots() -> Array:
	var result: Array = []
	for i in MAX_SLOTS:
		var path: String = _save_path(i)
		if FileAccess.file_exists(path):
			var d: Variant = _read_file(path)
			if d is Dictionary:
				result.append({
					"slot":        i,
					"exists":      true,
					"level":       d.get("current_level", 1),
					"circle":      d.get("current_circle", 1),
					"total_souls": d.get("total_souls", 0),
					"sin":         d.get("sin", 0.0),
					"world_seed_str": d.get("world_seed_str", ""),
					"name":        d.get("profile_name", ""),
				})
				continue
		result.append({"slot": i, "exists": false})
	return result

func delete_slot(slot: int) -> void:
	for path in [_save_path(slot), _backup_path(slot)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if slot == _slot:
		_reset()

# ── Explicit save ─────────────────────────────────────────────────────────────

func save_after_level() -> void:
	_flush()
	if CLOUD_ENABLED:
		_cloud_upload()

# ── Progress ──────────────────────────────────────────────────────────────────

func get_current_level() -> int:
	return data.get("current_level", 1)

func set_current_level(level: int) -> void:
	data["current_level"] = maxi(level, 1)

func get_current_circle() -> int:
	return data.get("current_circle", 1)

func set_current_circle(circle: int) -> void:
	data["current_circle"] = maxi(circle, 1)

# ── Sin ───────────────────────────────────────────────────────────────────────

func get_sin() -> float:
	return data.get("sin", 0.0)

func set_sin(value: float) -> void:
	data["sin"] = clampf(value, 0.0, 100.0)

func add_sin(amount: float) -> void:
	set_sin(get_sin() + amount)

func reduce_sin(amount: float) -> void:
	set_sin(get_sin() - amount)

# ── Light (currency) ──────────────────────────────────────────────────────────

func get_light() -> int:
	return data.get("light", 0)

func add_light(amount: int) -> void:
	data["light"] = get_light() + maxi(amount, 0)

func spend_light(amount: int) -> bool:
	if get_light() < amount:
		return false
	data["light"] = get_light() - amount
	return true

# ── Souls ─────────────────────────────────────────────────────────────────────

func get_total_souls() -> int:
	return data.get("total_souls", 0)

func get_saved_soul_ids() -> Array:
	return data.get("saved_soul_ids", [])

func add_soul(soul_id: int) -> void:
	var ids: Array = get_saved_soul_ids()
	if soul_id not in ids:
		ids.append(soul_id)
		data["saved_soul_ids"] = ids
		data["total_souls"]    = ids.size()

func has_soul(soul_id: int) -> bool:
	return soul_id in get_saved_soul_ids()

func get_total_hidden_souls() -> int:
	return data.get("total_hidden_souls", 0)

func get_hidden_soul_ids() -> Array:
	return data.get("hidden_soul_ids", [])

func add_hidden_soul(soul_id: String) -> void:
	var ids: Array = get_hidden_soul_ids()
	if soul_id not in ids:
		ids.append(soul_id)
		data["hidden_soul_ids"]    = ids
		data["total_hidden_souls"] = ids.size()

# ── Upgrades ──────────────────────────────────────────────────────────────────

func get_upgrade_level(upgrade_id: String) -> int:
	return data.get("upgrades", {}).get(upgrade_id, 0)

func set_upgrade_level(upgrade_id: String, level: int) -> void:
	if not data.has("upgrades"):
		data["upgrades"] = {}
	data["upgrades"][upgrade_id] = maxi(level, 0)

func has_upgrade(upgrade_id: String) -> bool:
	return get_upgrade_level(upgrade_id) > 0

# ── Generic flags (boolean) ───────────────────────────────────────────────────
# Used for one-time purchases, feature unlocks, etc.
# AdsManager stores "no_ads_purchased" here via set_flag.

func get_flag(key: String) -> bool:
	return data.get("flags", {}).get(key, false)

func set_flag(key: String, value: bool) -> void:
	if not data.has("flags"):
		data["flags"] = {}
	data["flags"][key] = value
	if value:
		_flush()   # persist purchases immediately

# Alias used by MainMenu — delegates to get_flag for consistency
func has_reward(key: String) -> bool:
	return get_flag(key)

# ── Rewards list (consumable unlocks) ─────────────────────────────────────────

func get_active_rewards() -> Array:
	return data.get("active_rewards", [])

func add_reward(reward_id: String) -> void:
	var rewards: Array = get_active_rewards()
	if reward_id not in rewards:
		rewards.append(reward_id)
		data["active_rewards"] = rewards

# ── Hints / tutorial ──────────────────────────────────────────────────────────

func is_hint_seen(hint_id: String) -> bool:
	return hint_id in data.get("seen_tutorial_hints", [])

func mark_hint_seen(hint_id: String) -> void:
	var seen: Array = data.get("seen_tutorial_hints", [])
	if hint_id not in seen:
		seen.append(hint_id)
		data["seen_tutorial_hints"] = seen

func clear_all_hints() -> void:
	data["seen_tutorial_hints"] = []

# ── Statistics ────────────────────────────────────────────────────────────────

func get_demon_deals_accepted() -> int:
	return data.get("demon_deals_accepted", 0)

func increment_demon_deals() -> void:
	data["demon_deals_accepted"] = get_demon_deals_accepted() + 1

func get_deals_refused() -> int:
	return data.get("deals_refused", 0)

func increment_deals_refused() -> void:
	data["deals_refused"] = get_deals_refused() + 1

func get_secret_levels_found() -> int:
	return data.get("secret_levels_found", 0)

func increment_secret_levels() -> void:
	data["secret_levels_found"] = get_secret_levels_found() + 1

# ── Endings ───────────────────────────────────────────────────────────────────

func get_unlocked_endings() -> Array:
	return data.get("unlocked_endings", [])

func unlock_ending(ending_id: String) -> void:
	var endings: Array = get_unlocked_endings()
	if ending_id not in endings:
		endings.append(ending_id)
		data["unlocked_endings"] = endings

# ── World seed ────────────────────────────────────────────────────────────────
# Stored as the user-typed string; LevelGenerator hashes it to int.
# Empty string = deterministic per level_id (default behaviour).

func get_world_seed_str() -> String:
	return data.get("world_seed_str", "")

func set_world_seed_str(value: String) -> void:
	data["world_seed_str"] = value

# ── Profile name ──────────────────────────────────────────────────────────────

func get_profile_name() -> String:
	return data.get("profile_name", "")

func set_profile_name(value: String) -> void:
	data["profile_name"] = value

# ── Per-level personal best ───────────────────────────────────────────────────
# Stored as `level_bests` (Dictionary keyed by str(level_id)) so persists in
# JSON as plain objects. Each entry: { time, stars, souls, deaths }.

func get_level_best(level_id: int) -> Dictionary:
	var bests: Dictionary = data.get("level_bests", {})
	return bests.get(str(level_id), {})

## Update the best record if `stars` strictly improves OR `stars` matches
## but `time` is faster. Returns the new best dict if updated, {} if the
## existing record stood (and the run wasn't an improvement).
func update_level_best(level_id: int, time: float, stars: int, souls: int, deaths: int) -> Dictionary:
	var bests: Dictionary = data.get("level_bests", {})
	var key: String = str(level_id)
	var current: Dictionary = bests.get(key, {})
	var prev_stars: int = int(current.get("stars", 0))
	var prev_time:  float = float(current.get("time", INF))
	var should_update: bool = stars > prev_stars \
		or (stars == prev_stars and time < prev_time)
	if not should_update:
		return {}
	var record: Dictionary = {
		"time": time,
		"stars": stars,
		"souls": souls,
		"deaths": deaths,
	}
	bests[key] = record
	data["level_bests"] = bests
	return record

# ── Internal: load ────────────────────────────────────────────────────────────

func _load() -> bool:
	var path: String = _save_path(_slot)
	if FileAccess.file_exists(path):
		var d: Variant = _read_file(path)
		if d is Dictionary:
			data = d
			_migrate()
			return true

	var backup: String = _backup_path(_slot)
	if FileAccess.file_exists(backup):
		push_warning("SaveManager: main save corrupted, loading backup for slot %d" % _slot)
		var d: Variant = _read_file(backup)
		if d is Dictionary:
			data = d
			_migrate()
			return true

	_reset()
	return false

func _read_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else null

# ── Internal: write ───────────────────────────────────────────────────────────

func _flush() -> void:
	var path:   String = _save_path(_slot)
	var backup: String = _backup_path(_slot)

	# Promote current main to backup before overwriting
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		if old:
			var content: String = old.get_as_text()
			old.close()
			var bak := FileAccess.open(backup, FileAccess.WRITE)
			if bak:
				bak.store_string(content)
				bak.close()

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: cannot write slot %d — %s" % [_slot, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

# ── Internal: default data ────────────────────────────────────────────────────

func _reset() -> void:
	data = {
		"version":             SAVE_VERSION,
		"current_level":       1,
		"current_circle":      1,
		"sin":                 0.0,
		"light":               0,
		"total_souls":         0,
		"saved_soul_ids":      [],
		"total_hidden_souls":  0,
		"hidden_soul_ids":     [],
		"upgrades":            {},
		"flags":               {},
		"active_rewards":      [],
		"unlocked_endings":    [],
		"demon_deals_accepted": 0,
		"deals_refused":       0,
		"secret_levels_found": 0,
		"seen_tutorial_hints": [],
		"world_seed_str":      "",
		"profile_name":        "",
	}

# ── Internal: migration ───────────────────────────────────────────────────────

func _migrate() -> void:
	var v: int = data.get("version", 1)
	if v == SAVE_VERSION:
		return

	# v1 → v2: active_rewards became flags dict
	if v < 2:
		var flags: Dictionary = data.get("flags", {})
		for reward in data.get("active_rewards", []):
			flags[reward] = true
		data["flags"] = flags

	data["version"] = SAVE_VERSION
	_flush()

# ── Internal: paths ───────────────────────────────────────────────────────────

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")

func _save_path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot

func _backup_path(slot: int) -> String:
	return SAVE_DIR + "save_%d_backup.json" % slot

# ── Cloud stubs ───────────────────────────────────────────────────────────────

func _cloud_upload() -> void:
	# Steam:  SteamworksSdk.file_write("save_%d.json" % _slot, JSON.stringify(data))
	# Google: PlayGameServices.save_game(...)
	pass

func cloud_download(_slot_idx: int) -> void:
	pass
