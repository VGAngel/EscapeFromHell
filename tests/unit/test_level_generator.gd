extends GutTest

# Tests for LevelGenerator pure math helpers.
# Config is injected directly — no file I/O.

var lg: Node

const TEST_DIFFICULTY_CFG := {
	"difficulty_injection": {
		"levels_1_3": {"enemy_count_mod": -1, "trap_density": "low",    "room_count": 3},
		"levels_4_6": {"enemy_count_mod":  0, "trap_density": "medium", "room_count": 4},
		"levels_7_9": {"enemy_count_mod":  1, "trap_density": "high",   "room_count": 5},
	}
}

func before_each() -> void:
	lg = autofree(preload("res://scripts/LevelGenerator.gd").new())
	lg._cfg   = TEST_DIFFICULTY_CFG.duplicate(true)
	lg._souls = {}
	lg._static_levels = []
	lg._hidden_soul_levels = {}

# ── _circle_of ────────────────────────────────────────────────────────────────

func test_circle_of_level_1() -> void:
	assert_eq(lg._circle_of(1), 1)

func test_circle_of_level_10() -> void:
	assert_eq(lg._circle_of(10), 1, "level 10 is still circle 1")

func test_circle_of_level_11() -> void:
	assert_eq(lg._circle_of(11), 2, "level 11 starts circle 2")

func test_circle_of_level_20() -> void:
	assert_eq(lg._circle_of(20), 2)

func test_circle_of_level_100() -> void:
	assert_eq(lg._circle_of(100), 10, "level 100 is circle 10")

func test_circle_of_level_50() -> void:
	assert_eq(lg._circle_of(50), 5)

func test_circle_of_level_51() -> void:
	assert_eq(lg._circle_of(51), 6)

# ── _index_in_circle ─────────────────────────────────────────────────────────

func test_index_in_circle_first() -> void:
	assert_eq(lg._index_in_circle(1), 1, "first level → index 1")

func test_index_in_circle_tenth() -> void:
	assert_eq(lg._index_in_circle(10), 10, "tenth level → index 10")

func test_index_in_circle_second_circle_first() -> void:
	assert_eq(lg._index_in_circle(11), 1, "level 11 → index 1 in circle 2")

func test_index_in_circle_second_circle_last() -> void:
	assert_eq(lg._index_in_circle(20), 10)

func test_index_in_circle_mid() -> void:
	assert_eq(lg._index_in_circle(15), 5)

func test_index_in_circle_level_100() -> void:
	assert_eq(lg._index_in_circle(100), 10)

# ── _difficulty_for_index ─────────────────────────────────────────────────────

func test_difficulty_index_1_is_low() -> void:
	var d: Dictionary = lg._difficulty_for_index(1)
	assert_eq(d.get("trap_density"), "low")
	assert_eq(d.get("enemy_count_mod"), -1)
	assert_eq(d.get("room_count"), 3)

func test_difficulty_index_3_is_low() -> void:
	var d: Dictionary = lg._difficulty_for_index(3)
	assert_eq(d.get("trap_density"), "low")

func test_difficulty_index_4_is_medium() -> void:
	var d: Dictionary = lg._difficulty_for_index(4)
	assert_eq(d.get("trap_density"), "medium")
	assert_eq(d.get("enemy_count_mod"), 0)
	assert_eq(d.get("room_count"), 4)

func test_difficulty_index_6_is_medium() -> void:
	var d: Dictionary = lg._difficulty_for_index(6)
	assert_eq(d.get("trap_density"), "medium")

func test_difficulty_index_7_is_high() -> void:
	var d: Dictionary = lg._difficulty_for_index(7)
	assert_eq(d.get("trap_density"), "high")
	assert_eq(d.get("enemy_count_mod"), 1)
	assert_eq(d.get("room_count"), 5)

func test_difficulty_index_9_is_high() -> void:
	var d: Dictionary = lg._difficulty_for_index(9)
	assert_eq(d.get("trap_density"), "high")

func test_difficulty_uses_fallback_when_cfg_empty() -> void:
	lg._cfg = {}
	var d: Dictionary = lg._difficulty_for_index(2)
	assert_eq(d.get("trap_density"), "low", "hardcoded fallback for indices 1-3")

# ── _is_static ────────────────────────────────────────────────────────────────

func test_is_static_false_when_list_empty() -> void:
	assert_false(lg._is_static(1))

func test_is_static_true_when_in_list() -> void:
	lg._static_levels = [1, 10, 20]
	assert_true(lg._is_static(10))

func test_is_static_false_when_not_in_list() -> void:
	lg._static_levels = [1, 10, 20]
	assert_false(lg._is_static(5))

# ── generate — static level ───────────────────────────────────────────────────

func test_generate_static_level_returns_is_static_true() -> void:
	lg._static_levels = [10]
	var result = lg.generate(10)
	assert_true(result.is_static)

func test_generate_static_level_empty_room_scenes() -> void:
	lg._static_levels = [10]
	var result = lg.generate(10)
	assert_eq(result.room_scenes.size(), 0, "static levels have no generated rooms")

func test_generate_non_static_returns_is_static_false() -> void:
	var result = lg.generate(5)
	assert_false(result.is_static)

func test_generate_sets_correct_circle() -> void:
	var result = lg.generate(15)
	assert_eq(result.circle, 2)

func test_generate_sets_correct_level_id() -> void:
	var result = lg.generate(7)
	assert_eq(result.level_id, 7)

# ── _pick_unique_room_index ───────────────────────────────────────────────────

func test_pick_unique_room_index_avoids_used() -> void:
	seed(42)
	var used: Array = [1, 2, 3, 4, 5]
	var pool_size: int = 10
	var idx: int = lg._pick_unique_room_index(used, pool_size)
	assert_false(idx in used, "should pick an index not in used list")

func test_pick_unique_room_index_within_range() -> void:
	seed(42)
	for _i in 20:
		var idx: int = lg._pick_unique_room_index([], 10)
		assert_true(idx >= 1 and idx <= 10)

func test_pick_unique_room_index_fallback_when_pool_exhausted() -> void:
	seed(42)
	var used: Array = [1, 2, 3, 4, 5]
	# pool_size == used.size() → allow repeats
	var idx: int = lg._pick_unique_room_index(used, 5)
	assert_true(idx >= 1 and idx <= 5)

# ── _pick_rooms ───────────────────────────────────────────────────────────────

func test_pick_rooms_count_matches_requested() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 4)
	assert_eq(rooms.size(), 4)

func test_pick_rooms_first_is_entrance() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 4)
	assert_true(rooms[0].contains("entrance"))

func test_pick_rooms_last_is_exit() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 4)
	assert_true(rooms[rooms.size() - 1].contains("exit"))

func test_pick_rooms_middle_are_main() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 5)
	# rooms[1] and rooms[2] and rooms[3] are main
	for i in range(1, rooms.size() - 1):
		assert_true(rooms[i].contains("main"), "room %d should be main" % i)

func test_pick_rooms_uses_correct_circle_in_paths() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(3, 3)
	for path in rooms:
		assert_true(path.contains("circle_3"))

func test_pick_rooms_main_rooms_no_repeats() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 6)   # 4 main rooms
	var mains: Array = rooms.slice(1, rooms.size() - 1)
	var seen: Dictionary = {}
	for r in mains:
		assert_false(seen.has(r), "duplicate main room: %s" % r)
		seen[r] = true

func test_pick_rooms_three_count_has_one_main() -> void:
	seed(1)
	var rooms: Array = lg._pick_rooms(1, 3)
	assert_eq(rooms.size(), 3)
	assert_true(rooms[1].contains("main"))

# ── _soul_for_level ───────────────────────────────────────────────────────────

func test_soul_for_level_returns_assigned_soul() -> void:
	lg._hidden_soul_levels = {5: {"id": 5, "name": "Тест", "circle": 1, "level": 5}}
	var soul: Dictionary = lg._soul_for_level(5, 1)
	assert_eq(soul.get("id"), 5)

func test_soul_for_level_returns_empty_when_no_souls() -> void:
	lg._souls = {}
	lg._hidden_soul_levels = {}
	var soul: Dictionary = lg._soul_for_level(3, 1)
	assert_true(soul.is_empty())

func test_soul_for_level_fallback_picks_from_circle_pool() -> void:
	lg._souls = {"named_souls": [
		{"id": 7, "name": "Іван", "circle": 2, "level": 0},
	]}
	lg._hidden_soul_levels = {}
	seed(1)
	var soul: Dictionary = lg._soul_for_level(12, 2)  # circle 2, no direct assign
	assert_eq(soul.get("id"), 7)

func test_soul_for_level_ignores_souls_from_other_circles() -> void:
	lg._souls = {"named_souls": [
		{"id": 9, "name": "Петро", "circle": 3, "level": 0},
	]}
	lg._hidden_soul_levels = {}
	var soul: Dictionary = lg._soul_for_level(12, 2)  # circle 2, soul is circle 3
	assert_true(soul.is_empty())

# ── _circle_style ─────────────────────────────────────────────────────────────

func test_circle_style_returns_value_from_config() -> void:
	lg._cfg = {"procedural_levels": {"room_pools": {
		"circle_2": {"rooms_count": 10, "style": "swamp"}
	}}}
	assert_eq(lg._circle_style(2), "swamp")

func test_circle_style_returns_empty_when_not_in_config() -> void:
	lg._cfg = {}
	assert_eq(lg._circle_style(1), "")

# ── generate — result fields ──────────────────────────────────────────────────

func test_generate_room_count_for_early_level() -> void:
	# level 2 → index 2 → low → room_count 3
	var r = lg.generate(2)
	assert_eq(r.room_count, 3)

func test_generate_room_count_for_mid_level() -> void:
	# level 5 → index 5 → medium → room_count 4
	var r = lg.generate(5)
	assert_eq(r.room_count, 4)

func test_generate_room_count_for_late_level() -> void:
	# level 8 → index 8 → high → room_count 5
	var r = lg.generate(8)
	assert_eq(r.room_count, 5)

func test_generate_trap_density_low_for_early_level() -> void:
	var r = lg.generate(1)
	assert_eq(r.trap_density, "low")

func test_generate_trap_density_high_for_late_level() -> void:
	var r = lg.generate(9)
	assert_eq(r.trap_density, "high")

func test_generate_enemy_count_mod_negative_for_early() -> void:
	var r = lg.generate(1)
	assert_lt(r.enemy_count_mod, 0)

func test_generate_enemy_count_mod_positive_for_late() -> void:
	var r = lg.generate(9)
	assert_gt(r.enemy_count_mod, 0)

func test_generate_same_seed_produces_same_rooms() -> void:
	var r1 = lg.generate(7)
	var r2 = lg.generate(7)
	assert_eq(r1.room_scenes, r2.room_scenes)

func test_generate_room_scenes_count_matches_room_count() -> void:
	var r = lg.generate(5)   # medium → room_count 4
	assert_eq(r.room_scenes.size(), r.room_count)

func test_generate_soul_id_zero_when_no_souls() -> void:
	lg._souls = {}
	lg._hidden_soul_levels = {}
	var r = lg.generate(3)
	assert_eq(r.soul_id, 0)

# ── is_static public wrapper ──────────────────────────────────────────────────

func test_is_static_public_matches_internal() -> void:
	lg._static_levels = [10, 20]
	assert_true(lg.is_static(10))
	assert_false(lg.is_static(5))

# ── get_soul_data ─────────────────────────────────────────────────────────────

func test_get_soul_data_returns_soul_for_assigned_level() -> void:
	lg._hidden_soul_levels = {4: {"id": 4, "name": "Ганна", "circle": 1, "level": 4}}
	var soul: Dictionary = lg.get_soul_data(4)
	assert_eq(soul.get("name"), "Ганна")

func test_get_soul_data_returns_empty_when_no_souls() -> void:
	lg._souls = {}
	lg._hidden_soul_levels = {}
	var soul: Dictionary = lg.get_soul_data(99)
	assert_true(soul.is_empty())
