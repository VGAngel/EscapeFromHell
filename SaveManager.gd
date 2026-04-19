extends Node

# Autoload: add to Project > Project Settings > Autoload as "SaveManager"

const SAVE_DIR       := "user://saves/"
const MAX_SLOTS      := 3
const CLOUD_ENABLED  := false  # увімкнути коли підключиш Steam/Google Play

var _slot: int = 0
var data: Dictionary = {}

func _ready() -> void:
	_ensure_dir()

# ── Slots ─────────────────────────────────────────────────────

func get_slot() -> int:
	return _slot

# Завантажує слот і повертає true якщо збереження існує
func load_slot(slot: int) -> bool:
	_slot = clampi(slot, 0, MAX_SLOTS - 1)
	return _load()

# Повертає список всіх слотів з коротким preview
func get_all_slots() -> Array:
	var result: Array = []
	for i in MAX_SLOTS:
		var path := _save_path(i)
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			var parsed: Variant = JSON.parse_string(file.read_as_text())
			file.close()
			if parsed is Dictionary:
				result.append({
					"slot":         i,
					"exists":       true,
					"level":        parsed.get("current_level", 1),
					"circle":       parsed.get("current_circle", 1),
					"total_souls":  parsed.get("total_souls", 0),
					"sin":          parsed.get("sin", 0.0)
				})
				continue
		result.append({ "slot": i, "exists": false })
	return result

func delete_slot(slot: int) -> void:
	var main   := _save_path(slot)
	var backup := _backup_path(slot)
	if FileAccess.file_exists(main):
		DirAccess.remove_absolute(main)
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(backup)
	if slot == _slot:
		_reset()

# ── Save / Load ───────────────────────────────────────────────

func save_after_level() -> void:
	_write()
	if CLOUD_ENABLED:
		_cloud_upload()

func has_save(slot: int = _slot) -> bool:
	return FileAccess.file_exists(_save_path(slot))

# ── Progress ──────────────────────────────────────────────────

func get_current_level() -> int:
	return data.get("current_level", 1)

func set_current_level(level: int) -> void:
	data["current_level"] = level

func get_current_circle() -> int:
	return data.get("current_circle", 1)

func set_current_circle(circle: int) -> void:
	data["current_circle"] = circle

# ── Souls ─────────────────────────────────────────────────────

func get_saved_soul_ids() -> Array:
	return data.get("saved_soul_ids", [])

func add_soul(soul_id: int) -> void:
	var ids: Array = get_saved_soul_ids()
	if soul_id not in ids:
		ids.append(soul_id)
		data["saved_soul_ids"] = ids
		data["total_souls"]    = ids.size()

func get_total_souls() -> int:
	return data.get("total_souls", 0)

func get_hidden_soul_ids() -> Array:
	return data.get("hidden_soul_ids", [])

func add_hidden_soul(soul_id: String) -> void:
	var ids: Array = get_hidden_soul_ids()
	if soul_id not in ids:
		ids.append(soul_id)
		data["hidden_soul_ids"]      = ids
		data["total_hidden_souls"]   = ids.size()

func get_total_hidden_souls() -> int:
	return data.get("total_hidden_souls", 0)

# ── Sin ───────────────────────────────────────────────────────

func get_sin() -> float:
	return data.get("sin", 0.0)

func set_sin(value: float) -> void:
	data["sin"] = clampf(value, 0.0, 100.0)

func add_sin(amount: float) -> void:
	set_sin(get_sin() + amount)

func reduce_sin(amount: float) -> void:
	set_sin(get_sin() - amount)

# ── Currency ──────────────────────────────────────────────────

func get_light() -> int:
	return data.get("light", 0)

func add_light(amount: int) -> void:
	data["light"] = get_light() + amount

func spend_light(amount: int) -> bool:
	if get_light() < amount:
		return false
	data["light"] = get_light() - amount
	return true

# ── Upgrades ──────────────────────────────────────────────────

func get_upgrade_level(upgrade_id: String) -> int:
	return data.get("upgrades", {}).get(upgrade_id, 0)

func set_upgrade_level(upgrade_id: String, level: int) -> void:
	if not data.has("upgrades"):
		data["upgrades"] = {}
	data["upgrades"][upgrade_id] = level

func has_upgrade(upgrade_id: String) -> bool:
	return get_upgrade_level(upgrade_id) > 0

# ── Rewards ───────────────────────────────────────────────────

func get_active_rewards() -> Array:
	return data.get("active_rewards", [])

func add_reward(reward_id: String) -> void:
	var rewards: Array = get_active_rewards()
	if reward_id not in rewards:
		rewards.append(reward_id)
		data["active_rewards"] = rewards

func has_reward(reward_id: String) -> bool:
	return reward_id in get_active_rewards()

# ── Endings ───────────────────────────────────────────────────

func get_unlocked_endings() -> Array:
	return data.get("unlocked_endings", [])

func unlock_ending(ending_id: String) -> void:
	var endings: Array = get_unlocked_endings()
	if ending_id not in endings:
		endings.append(ending_id)
		data["unlocked_endings"] = endings

# ── Stats ─────────────────────────────────────────────────────

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

# ── Internal ──────────────────────────────────────────────────

func _load() -> bool:
	var path := _save_path(_slot)

	# Спробувати основний файл
	if FileAccess.file_exists(path):
		var result := _read_file(path)
		if result != null:
			data = result
			return true

	# Основний пошкоджений — спробувати резервний
	var backup := _backup_path(_slot)
	if FileAccess.file_exists(backup):
		push_warning("SaveManager: main save corrupted, loading backup for slot %d" % _slot)
		var result := _read_file(backup)
		if result != null:
			data = result
			return true

	_reset()
	return false

func _write() -> void:
	var path   := _save_path(_slot)
	var backup := _backup_path(_slot)
	var json   := JSON.stringify(data, "\t")

	# Якщо основний існує — скопіювати в резервний перед перезаписом
	if FileAccess.file_exists(path):
		var old := FileAccess.open(path, FileAccess.READ)
		if old:
			var old_content := old.read_as_text()
			old.close()
			var bak := FileAccess.open(backup, FileAccess.WRITE)
			if bak:
				bak.store_string(old_content)
				bak.close()

	# Записати основний
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("SaveManager: cannot write slot %d" % _slot)
		return
	file.store_string(json)
	file.close()

func _read_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return null
	var parsed: Variant = JSON.parse_string(file.read_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return null

func _reset() -> void:
	data = {
		"current_level":        1,
		"current_circle":       1,
		"total_souls":          0,
		"saved_soul_ids":       [],
		"total_hidden_souls":   0,
		"hidden_soul_ids":      [],
		"sin":                  0.0,
		"light":                0,
		"upgrades":             {},
		"unlocked_endings":     [],
		"active_rewards":       [],
		"demon_deals_accepted": 0,
		"deals_refused":        0,
		"secret_levels_found":  0
	}

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR.left(-1)):
		DirAccess.make_dir_absolute(SAVE_DIR.left(-1))

func _save_path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot

func _backup_path(slot: int) -> String:
	return SAVE_DIR + "save_%d_backup.json" % slot

# ── Cloud (заглушки) ──────────────────────────────────────────

func _cloud_upload() -> void:
	# TODO: підключити Steam Steamworks або Google Play
	# Steam:  SteamworksSdk.file_write("save_%d.json" % _slot, JSON.stringify(data))
	# Google: PlayGameServices.save_game(...)
	pass

func cloud_download(slot: int) -> void:
	# TODO: завантажити з хмари і перезаписати локальний файл
	pass
