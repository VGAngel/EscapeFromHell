extends Node

# Autoload: SaveManager  (res://scripts/managers/SaveManager.gd)
# Single source of truth for all persistent game state.
# All writes stay in-memory until _flush() is called.
# _flush() is called: after level complete, on app pause, on window close.

const SAVE_DIR     := "user://saves/"
const SAVE_VERSION := 2
const MAX_SLOTS    := 3
const CLOUD_ENABLED := false
# Cross-slot pointer: which slot is currently active. Lives outside the
# slot files so switching profiles can't accidentally orphan it. If the
# file is missing or unreadable we fall back to the first existing
# slot — keeps existing players upgrading from pre-profiles builds happy.
const ACTIVE_SLOT_PATH := "user://active_slot.json"

# Profile name rules — kept here so UI and SaveManager validate identically.
# Cyrillic + Latin + digits + spaces; trim before storing; 3-20 chars.
const PROFILE_NAME_MIN := 3
const PROFILE_NAME_MAX := 20

# Profile lifecycle. UIs that show profile data (HeroCard, PlaySubmenu's
# inline name row, MainMenu) subscribe to keep their views in sync without
# polling.
signal profile_switched(slot: int)
signal profile_created(slot: int, name: String)
signal profile_deleted(slot: int)

var _slot: int = 0
var data: Dictionary = {}   # public for debug inspection; use methods to mutate

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_ensure_dir()
	_reset()
	# Boot ordering: try to restore the previously active slot, then
	# any existing slot, else leave slot 0 reset and unloaded — that's
	# the signal to MainMenu to launch the first-run profile-create
	# flow. Only the autoload instance restores from disk; ad-hoc
	# instances that GUT spawns under a test scene get pristine state
	# (otherwise leftover save files bleed into unrelated tests).
	if get_parent() == get_tree().root:
		_boot_restore()


func _boot_restore() -> void:
	var restored: int = _read_active_slot()
	if restored >= 0 and has_save(restored):
		_slot = restored
		_load()
	elif has_any_profiles():
		_slot = first_existing_slot()
		_load()
		_write_active_slot(_slot)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush()

# ── Slot management ───────────────────────────────────────────────────────────

func get_slot() -> int:
	return _slot

func load_slot(slot: int) -> bool:
	_slot = clampi(slot, 0, MAX_SLOTS - 1)
	var ok: bool = _load()
	_write_active_slot(_slot)
	profile_switched.emit(_slot)
	return ok


# True iff at least one slot has a saved file. Used by the boot router
# to decide between MainMenu (existing player) and ProfileCreateScreen
# (first launch / all profiles deleted).
func has_any_profiles() -> bool:
	for i in MAX_SLOTS:
		if FileAccess.file_exists(_save_path(i)):
			return true
	return false


# Returns the lowest slot index that actually has a save. -1 if none.
# Used as a fallback when active_slot.json is missing or stale.
func first_existing_slot() -> int:
	for i in MAX_SLOTS:
		if FileAccess.file_exists(_save_path(i)):
			return i
	return -1


# Active-slot pointer (read at boot, written on every load_slot).
# Stored outside the slot files so its lifecycle is global, not per-save.
func get_active_slot() -> int:
	return _slot


# Create a profile in a specific slot in one shot: validate name, write,
# flush, and emit profile_created. Returns false if the name is invalid
# or the slot already has a save (caller should delete first).
func create_profile(slot: int, raw_name: String) -> bool:
	if not is_valid_profile_name(raw_name):
		return false
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	if has_save(slot):
		return false
	_slot = slot
	_reset()
	data["profile_name"] = raw_name.strip_edges()
	_flush()
	_write_active_slot(_slot)
	profile_created.emit(_slot, data["profile_name"])
	# Emit profile_switched too so generic listeners (HeroCard etc.) just
	# subscribe to one signal and get the right behaviour for both
	# create-and-go and switch-existing flows.
	profile_switched.emit(_slot)
	return true


# Trim, then check that what's left only contains letters / digits / spaces
# (Cyrillic is included via the Unicode classification). Length 3-20 after
# trim. Empty / whitespace-only / oversized strings rejected.
func is_valid_profile_name(raw: String) -> bool:
	var s: String = raw.strip_edges()
	if s.length() < PROFILE_NAME_MIN or s.length() > PROFILE_NAME_MAX:
		return false
	for c in s:
		if not (c.is_valid_int() or _is_letter(c) or c == " "):
			return false
	return true


# Cyrillic + Latin letter check. is_subsequence_ofn() doesn't help us
# here; we use the unicode_at()-based ranges. Keeps the logic explicit
# and dependency-free.
func _is_letter(c: String) -> bool:
	if c.length() == 0:
		return false
	var u: int = c.unicode_at(0)
	# Latin A-Z, a-z
	if (u >= 0x41 and u <= 0x5A) or (u >= 0x61 and u <= 0x7A):
		return true
	# Cyrillic basic (А-я, Ё, ё) + Ukrainian-specific Є/є/І/і/Ї/ї/Ґ/ґ.
	if (u >= 0x0410 and u <= 0x044F) or u == 0x0401 or u == 0x0451:
		return true
	if u in [0x0404, 0x0454, 0x0406, 0x0456, 0x0407, 0x0457, 0x0490, 0x0491]:
		return true
	return false

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
	profile_deleted.emit(slot)
	if slot == _slot:
		# Active profile gone — try to fall back to the next remaining
		# slot so existing UIs still have data. If no profiles are left,
		# clear active_slot.json and reset; the boot/main-menu code is
		# responsible for sending the player back to ProfileCreateScreen.
		var next_slot: int = first_existing_slot()
		if next_slot >= 0:
			_slot = next_slot
			_load()
			_write_active_slot(_slot)
			profile_switched.emit(_slot)
		else:
			_reset()
			if FileAccess.file_exists(ACTIVE_SLOT_PATH):
				DirAccess.remove_absolute(ACTIVE_SLOT_PATH)

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
	add_stat("light_spent_total", amount)
	return true

# ── Souls ─────────────────────────────────────────────────────────────────────

func get_total_souls() -> int:
	return data.get("total_souls", 0)


# Total named souls in the pool — used by every "X / N" counter so the UI
# scales automatically when more souls are added to souls_collection.json.
# Reads from LevelGenerator (which already loads the JSON at boot); falls
# back to the historical 100 when the autoload isn't available (tests).
func get_named_souls_target() -> int:
	var lg: Node = Engine.get_main_loop().root.get_node_or_null("LevelGenerator") if Engine.get_main_loop() else null
	if lg and lg.has_method("get_total_named_count"):
		return int(lg.get_total_named_count())
	return 100


func get_hidden_souls_target() -> int:
	var lg: Node = Engine.get_main_loop().root.get_node_or_null("LevelGenerator") if Engine.get_main_loop() else null
	if lg and lg.has_method("get_total_hidden_count"):
		return int(lg.get_total_hidden_count())
	return 20

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


# ── "NEW!" badge tracking ─────────────────────────────────────────────────────
# A collected soul is "unseen" until the player opens its detail sheet
# in CollectionScreen. Used to render a NEW badge on the cell + a count
# on HeroCard.

func is_soul_seen(soul_id: int) -> bool:
	return soul_id in data.get("souls_seen", [])

func mark_soul_seen(soul_id: int) -> void:
	var seen: Array = data.get("souls_seen", [])
	if soul_id not in seen:
		seen.append(soul_id)
		data["souls_seen"] = seen

# Mark every currently-saved soul as seen — used to "clear all NEW
# badges" e.g. when the player tap-and-holds the collection counter
# in HeroCard.
func mark_all_souls_seen() -> void:
	data["souls_seen"] = get_saved_soul_ids().duplicate()

# How many collected named souls the player has NOT yet opened in
# CollectionScreen. Drives the badge count on HeroCard / TopBar.
func get_unseen_souls_count() -> int:
	var saved: Array = get_saved_soul_ids()
	var seen: Array  = data.get("souls_seen", [])
	var n: int = 0
	for id in saved:
		if id not in seen:
			n += 1
	return n

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

# ── Mobile control layout ────────────────────────────────────────────────────
# Per-button position overrides + global size scale, populated when the
# player drags buttons in MobileControls edit mode. Empty dict = default
# layout from MobileControls._apply_safe_area.

func get_mobile_layout() -> Dictionary:
	return data.get("mobile_layout", {})

func set_mobile_layout(layout: Dictionary) -> void:
	data["mobile_layout"] = layout
	_flush()   # persist immediately so a crash mid-game doesn't lose tweaks

# ── Statistics ────────────────────────────────────────────────────────────────
# Aggregate counters survive across saves. Stored under data["statistics"] so
# new keys don't churn the top-level schema. All getters degrade gracefully —
# never crash when a counter doesn't exist yet.

func get_stat(key: String, default: Variant = 0) -> Variant:
	return data.get("statistics", {}).get(key, default)

func add_stat(key: String, delta: Variant = 1) -> void:
	var stats: Dictionary = data.get("statistics", {})
	stats[key] = stats.get(key, 0) + delta
	data["statistics"] = stats

func incr_death_cause(cause: String) -> void:
	var stats: Dictionary = data.get("statistics", {})
	var causes: Dictionary = stats.get("deaths_by_cause", {})
	causes[cause] = int(causes.get(cause, 0)) + 1
	stats["deaths_by_cause"] = causes
	data["statistics"] = stats

func get_deaths_by_cause() -> Dictionary:
	return data.get("statistics", {}).get("deaths_by_cause", {})

func add_play_time(seconds: float) -> void:
	var stats: Dictionary = data.get("statistics", {})
	stats["total_play_seconds"] = float(stats.get("total_play_seconds", 0.0)) + seconds
	data["statistics"] = stats

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
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		# Without this warning a corrupted save file silently fell
		# through to backup → defaults, and the player saw their
		# progress reset on next launch with no clue why. Log the
		# path + first 80 chars so we have something to repro on.
		var preview: String = raw.substr(0, 80).strip_edges()
		push_warning(
				"SaveManager: failed to parse save '%s' — %d bytes, head: %s" % [
				path, raw.length(), preview])
		return null
	return parsed

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
		"souls_seen":          [],   # ids of named souls already viewed in CollectionScreen
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

	# `souls_seen` was added with the NEW-badge feature. For pre-existing
	# saves we treat all currently-collected souls as already seen so
	# the player doesn't get a sudden wave of "NEW" badges they never
	# asked for.
	if not data.has("souls_seen"):
		data["souls_seen"] = data.get("saved_soul_ids", []).duplicate()

	data["version"] = SAVE_VERSION
	_flush()

# ── Internal: paths ───────────────────────────────────────────────────────────

func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute("user://saves")

func _save_path(slot: int) -> String:
	return SAVE_DIR + "save_%d.json" % slot

func _backup_path(slot: int) -> String:
	return SAVE_DIR + "save_%d_backup.json" % slot

# ── Active-slot pointer ───────────────────────────────────────────────────────
#
# Tiny JSON {"active_slot": N} living next to the slot files. Read once
# at boot to remember which profile the player was using; rewritten on
# every load_slot/create_profile/recovery-after-delete. Kept separate
# from the slot data so a corrupted slot can't take the pointer with it.

func _read_active_slot() -> int:
	if not FileAccess.file_exists(ACTIVE_SLOT_PATH):
		return -1
	var f := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.READ)
	if f == null:
		return -1
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return -1
	var s: int = int((parsed as Dictionary).get("active_slot", -1))
	if s < 0 or s >= MAX_SLOTS:
		return -1
	return s


func _write_active_slot(slot: int) -> void:
	var f := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveManager: could not write %s" % ACTIVE_SLOT_PATH)
		return
	f.store_string(JSON.stringify({"active_slot": slot, "version": 1}))
	f.close()

# ── Cloud stubs ───────────────────────────────────────────────────────────────

func _cloud_upload() -> void:
	# Steam:  SteamworksSdk.file_write("save_%d.json" % _slot, JSON.stringify(data))
	# Google: PlayGameServices.save_game(...)
	pass

func cloud_download(_slot_idx: int) -> void:
	pass
