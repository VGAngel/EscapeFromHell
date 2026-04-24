extends GutTest

# Tests for LevelConfig pure query logic.
# Data is injected directly — no file I/O needed.

var lc: Node

func before_each() -> void:
	lc = autofree(preload("res://scripts/managers/LevelConfig.gd").new())
	# autofree() skips add_child → _ready() never called → _load() never runs
	lc._levels_by_id = {
		1:  {"id": 1,  "circle": 1, "type": "platformer", "souls_count": 2,
			 "static": true, "difficulty": 1, "enemies": ["shade"], "traps": [], "bonuses": []},
		5:  {"id": 5,  "circle": 1, "type": "escape",     "souls_count": 3,
			 "escape_time": 45.0, "special_mechanics": ["timed_escape"]},
		7:  {"id": 7,  "circle": 1, "type": "void",       "souls_count": 1},
		10: {"id": 10, "circle": 1, "type": "boss",       "souls_count": 0},
		11: {"id": 11, "circle": 2, "type": "platformer", "souls_count": 2,
			 "special_mechanics": ["hidden_soul_room"]},
		15: {"id": 15, "circle": 2, "type": "labyrinth",  "difficulty": 3,
			 "soul_types": ["innocent", "broken", "sleeping"]},
		17: {"id": 17, "circle": 2, "type": "void",       "souls_count": 1,
			 "hidden_soul": true},
		20: {"id": 20, "circle": 2, "type": "boss",       "souls_count": 0, "static": true},
	}
	lc._circle_defaults = {
		"1": {"theme": "limbo",   "enemies": ["shade"],      "traps": ["pit"],  "bonuses": ["prayer"], "soul_types": ["innocent"]},
		"2": {"theme": "lustful", "enemies": ["lust_demon"], "traps": ["wind"], "bonuses": [],         "soul_types": ["broken"]},
	}
	lc._data = {"levels": [], "circle_defaults": lc._circle_defaults}

# ── get_level_type ────────────────────────────────────────────────────────────

func test_get_level_type_platformer() -> void:
	assert_eq(lc.get_level_type(1), "platformer")

func test_get_level_type_boss() -> void:
	assert_eq(lc.get_level_type(10), "boss")

func test_get_level_type_void() -> void:
	assert_eq(lc.get_level_type(7), "void")

func test_get_level_type_escape() -> void:
	assert_eq(lc.get_level_type(5), "escape")

func test_get_level_type_unknown_returns_platformer() -> void:
	assert_eq(lc.get_level_type(999), "platformer", "unknown level uses fallback type")

# ── is_boss_level ─────────────────────────────────────────────────────────────

func test_is_boss_level_true() -> void:
	assert_true(lc.is_boss_level(10))

func test_is_boss_level_false_for_platformer() -> void:
	assert_false(lc.is_boss_level(1))

func test_is_boss_level_false_for_void() -> void:
	assert_false(lc.is_boss_level(7))

# ── is_void_level ─────────────────────────────────────────────────────────────

func test_is_void_level_true() -> void:
	assert_true(lc.is_void_level(7))

func test_is_void_level_false_for_boss() -> void:
	assert_false(lc.is_void_level(10))

# ── is_static ─────────────────────────────────────────────────────────────────

func test_is_static_explicit_flag() -> void:
	assert_true(lc.is_static(1), "static:true flag")

func test_is_static_boss_level() -> void:
	assert_true(lc.is_static(10), "boss levels are always static")

func test_is_static_first_of_circle() -> void:
	# 21 % 10 == 1 → first level of circle 3 (not in injected data → fallback)
	# Use level 21 which is not in _levels_by_id, falls back with id%10==1
	# Actually, with fallback level 21 is not static flagged, but id%10==1 check
	# is done on the real id. Let's add level 21 to test this path.
	lc._levels_by_id[21] = {"id": 21, "circle": 3, "type": "platformer", "souls_count": 2}
	assert_true(lc.is_static(21), "id %% 10 == 1 is always static")

func test_is_static_false_for_non_static() -> void:
	assert_false(lc.is_static(15), "labyrinth mid-circle is not static")

# ── get_circle ────────────────────────────────────────────────────────────────

func test_get_circle_level_1() -> void:
	assert_eq(lc.get_circle(1), 1)

func test_get_circle_level_10() -> void:
	assert_eq(lc.get_circle(10), 1)

func test_get_circle_level_11() -> void:
	assert_eq(lc.get_circle(11), 2)

func test_get_circle_level_20() -> void:
	assert_eq(lc.get_circle(20), 2)

func test_get_circle_fallback_level() -> void:
	# Unknown level 55 → _make_fallback → ceili(55/10) = 6
	assert_eq(lc.get_circle(55), 6)

# ── get_circle_tileset ────────────────────────────────────────────────────────
#
# Regression guard: tileset config drives which art set the circle uses.
# Mapping lives in levels_config.json → circle_defaults["<n>"]["tileset"].

func test_get_circle_tileset_returns_configured_value() -> void:
	lc._circle_defaults = {
		"1": {"tileset": "tileset1"},
		"3": {"tileset": "tileset2"},
	}
	assert_eq(lc.get_circle_tileset(1), "tileset1")
	assert_eq(lc.get_circle_tileset(3), "tileset2")

func test_get_circle_tileset_unknown_circle_falls_back_to_tileset1() -> void:
	# Circle 99 isn't in defaults → fallback prevents crash on misconfig.
	assert_eq(lc.get_circle_tileset(99), "tileset1")

func test_get_circle_tileset_missing_key_falls_back_to_tileset1() -> void:
	# Circle 1 exists but has no "tileset" key (legacy data) → fallback.
	lc._circle_defaults = {"1": {"theme": "test_only"}}
	assert_eq(lc.get_circle_tileset(1), "tileset1")

# ── get_difficulty ────────────────────────────────────────────────────────────

func test_get_difficulty_explicit() -> void:
	assert_eq(lc.get_difficulty(15), 3)

func test_get_difficulty_fallback() -> void:
	# Unknown level → _make_fallback → difficulty = circle = ceili(35/10) = 4
	assert_eq(lc.get_difficulty(35), 4)

# ── get_souls_count ───────────────────────────────────────────────────────────

func test_get_souls_count_explicit() -> void:
	assert_eq(lc.get_souls_count(1), 2)

func test_get_souls_count_from_soul_types() -> void:
	# Level 15 has no souls_count but has soul_types[3]
	lc._levels_by_id[15].erase("souls_count")
	assert_eq(lc.get_souls_count(15), 3, "soul_types.size() fallback")

func test_get_souls_count_boss_zero() -> void:
	assert_eq(lc.get_souls_count(10), 0)

# ── has_mechanic ──────────────────────────────────────────────────────────────

func test_has_mechanic_true() -> void:
	assert_true(lc.has_mechanic(5, "timed_escape"))

func test_has_mechanic_false() -> void:
	assert_false(lc.has_mechanic(5, "hidden_soul_room"))

func test_has_mechanic_hidden_soul_room() -> void:
	assert_true(lc.has_mechanic(11, "hidden_soul_room"))

# ── has_hidden_soul ───────────────────────────────────────────────────────────

func test_has_hidden_soul_via_flag() -> void:
	assert_true(lc.has_hidden_soul(17), "hidden_soul:true flag")

func test_has_hidden_soul_via_mechanic() -> void:
	assert_true(lc.has_hidden_soul(11), "hidden_soul_room mechanic")

func test_has_hidden_soul_false() -> void:
	assert_false(lc.has_hidden_soul(1))

# ── get_escape_time ───────────────────────────────────────────────────────────

func test_get_escape_time_explicit() -> void:
	assert_eq(lc.get_escape_time(5), 45.0)

func test_get_escape_time_default() -> void:
	assert_eq(lc.get_escape_time(1), 60.0, "default escape time is 60s")

# ── _make_fallback ────────────────────────────────────────────────────────────

func test_make_fallback_correct_circle() -> void:
	var fb: Dictionary = lc._make_fallback(45)
	assert_eq(fb.get("circle"), 5, "circle = ceili(45/10) = 5")

func test_make_fallback_type_platformer() -> void:
	var fb: Dictionary = lc._make_fallback(42)
	assert_eq(fb.get("type"), "platformer")

func test_make_fallback_souls_count_one() -> void:
	var fb: Dictionary = lc._make_fallback(42)
	assert_eq(fb.get("souls_count"), 1)

func test_make_fallback_id_preserved() -> void:
	var fb: Dictionary = lc._make_fallback(77)
	assert_eq(fb.get("id"), 77)

# ── Circle defaults merge ─────────────────────────────────────────────────────

func test_missing_enemies_filled_from_circle_defaults() -> void:
	# Level 17 has no enemies field → should be filled from circle 2 defaults
	var lvl: Dictionary = lc.get_level(17)
	assert_eq(lvl.get("enemies"), ["lust_demon"], "enemies from circle defaults")

func test_explicit_enemies_not_overridden() -> void:
	# Level 1 has explicit enemies: ["shade"]
	var lvl: Dictionary = lc.get_level(1)
	assert_eq(lvl.get("enemies"), ["shade"], "explicit enemies preserved")
