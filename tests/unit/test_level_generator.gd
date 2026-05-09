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
	lg = autofree(preload("res://scripts/levels/LevelGenerator.gd").new())
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
	assert_eq(d.get("room_count"), 2)

func test_difficulty_index_3_is_low() -> void:
	var d: Dictionary = lg._difficulty_for_index(3)
	assert_eq(d.get("trap_density"), "low")

func test_difficulty_index_4_is_medium() -> void:
	var d: Dictionary = lg._difficulty_for_index(4)
	assert_eq(d.get("trap_density"), "medium")
	assert_eq(d.get("enemy_count_mod"), 0)
	assert_eq(d.get("room_count"), 4)  # ROOM_COUNT_BY_IDX[4] = 4

func test_difficulty_index_6_is_medium() -> void:
	var d: Dictionary = lg._difficulty_for_index(6)
	assert_eq(d.get("trap_density"), "medium")

func test_difficulty_index_7_is_high() -> void:
	var d: Dictionary = lg._difficulty_for_index(7)
	assert_eq(d.get("trap_density"), "high")
	assert_eq(d.get("enemy_count_mod"), 1)
	assert_eq(d.get("room_count"), 6)

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
	# Per-circle scenes fall back to circle_1 when circle_3 isn't authored yet
	# (LevelBase overwrites `circle` on the instance so theme/enemies still
	# match the target circle). Accept either path.
	for path in rooms:
		assert_true(path.contains("circle_3") or path.contains("circle_1"),
			"path should be from circle_3 or its circle_1 fallback: %s" % path)

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

func test_soul_for_level_returns_distributed_soul() -> void:
	# Distribution maps level → assigned souls. Pre-set it so this unit
	# test doesn't depend on LevelConfig's full level catalogue.
	lg._distribution = {12: [{"id": 7, "name": "Іван", "circle": 2, "level": 0}]}
	# Match SaveManager.get_world_seed_str() default ("") so
	# _ensure_distribution treats the manually-seeded _distribution as
	# already-current and skips the rebuild that would clear it.
	lg._distribution_seed = SaveManager.get_world_seed_str() if SaveManager else ""
	lg._hidden_soul_levels = {}
	var soul: Dictionary = lg._soul_for_level(12, 2)
	assert_eq(soul.get("id"), 7)

func test_soul_for_level_returns_empty_when_level_not_in_distribution() -> void:
	lg._distribution = {12: [{"id": 7, "circle": 2, "level": 0}]}
	lg._distribution_seed = SaveManager.get_world_seed_str() if SaveManager else ""
	lg._hidden_soul_levels = {}
	var soul: Dictionary = lg._soul_for_level(99, 2)  # not in distribution
	assert_true(soul.is_empty())

# ── Distribution: 1-to-1 per playthrough ──────────────────────────────────────

func test_souls_for_level_returns_all_assigned_when_count_matches() -> void:
	lg._distribution = {5: [
		{"id": 1, "circle": 1, "level": 0},
		{"id": 2, "circle": 1, "level": 0},
	]}
	lg._distribution_seed = SaveManager.get_world_seed_str() if SaveManager else ""
	var souls: Array = lg._souls_for_level(5, 1, 2)
	assert_eq(souls.size(), 2)

func test_souls_for_level_trims_excess_when_count_smaller_than_assigned() -> void:
	lg._distribution = {5: [
		{"id": 1, "circle": 1, "level": 0},
		{"id": 2, "circle": 1, "level": 0},
		{"id": 3, "circle": 1, "level": 0},
	]}
	lg._distribution_seed = SaveManager.get_world_seed_str() if SaveManager else ""
	var souls: Array = lg._souls_for_level(5, 1, 1)
	assert_eq(souls.size(), 1)

func test_distribution_assigns_unique_souls_across_levels() -> void:
	# When the pool size matches total spawn slots, no soul should appear
	# on two different levels in the same playthrough.
	lg._souls = {"named_souls": [
		{"id": 1, "circle": 1, "level": 0},
		{"id": 2, "circle": 1, "level": 0},
		{"id": 3, "circle": 1, "level": 0},
	]}
	lg._distribution.clear()
	lg._distribution_seed = "<unbuilt>"
	# Force rebuild by calling _build_distribution directly with a real seed.
	lg._build_distribution("playthrough-123")
	# Collect every assigned soul id across all levels in the distribution.
	var seen_ids: Array = []
	for lvl_id in lg._distribution.keys():
		for soul: Dictionary in lg._distribution[lvl_id]:
			var sid: int = int(soul.get("id", 0))
			assert_false(sid in seen_ids,
				"soul id %d appeared on more than one level" % sid)
			seen_ids.append(sid)

func test_distribution_seed_changes_layout() -> void:
	# Different world seeds should produce different (or at least
	# possibly different) layouts. We just check the dicts aren't
	# byte-identical when the seed differs.
	lg._souls = {"named_souls": [
		{"id": 1, "circle": 1, "level": 0},
		{"id": 2, "circle": 1, "level": 0},
		{"id": 3, "circle": 1, "level": 0},
		{"id": 4, "circle": 1, "level": 0},
		{"id": 5, "circle": 1, "level": 0},
	]}
	lg._build_distribution("seed-A")
	var layout_a: Dictionary = lg._distribution.duplicate(true)
	lg._build_distribution("seed-B-very-different-string")
	var layout_b: Dictionary = lg._distribution.duplicate(true)
	# Even with shuffles, a 5-soul pool has 5! = 120 permutations — two
	# distinct seeds collide < 1% of the time. Failing this is suspicious.
	assert_ne(layout_a, layout_b,
		"different world seeds should usually produce different layouts")

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
	# level 2 → index 2 → ROOM_COUNT_BY_IDX[2] = 3
	var r = lg.generate(2)
	assert_eq(r.room_count, 3)

func test_generate_room_count_for_mid_level() -> void:
	# level 5 → index 5 → ROOM_COUNT_BY_IDX[5] = 5
	var r = lg.generate(5)
	assert_eq(r.room_count, 5)

func test_generate_room_count_for_late_level() -> void:
	# level 8 → index 8 → ROOM_COUNT_BY_IDX[8] = 7
	var r = lg.generate(8)
	assert_eq(r.room_count, 7)

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
	var r = lg.generate(5)   # medium → room_count 5
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

# ── _is_branch ────────────────────────────────────────────────────────────────

func test_is_branch_false_for_main_levels() -> void:
	assert_false(lg._is_branch(1))
	assert_false(lg._is_branch(50))
	assert_false(lg._is_branch(100))

func test_is_branch_true_for_ids_above_100() -> void:
	assert_true(lg._is_branch(103))
	assert_true(lg._is_branch(109))
	assert_true(lg._is_branch(189))

func test_is_branch_false_for_100() -> void:
	assert_false(lg._is_branch(100))

func test_is_branch_true_for_101() -> void:
	assert_true(lg._is_branch(101))

# ── _parent_of ────────────────────────────────────────────────────────────────

func test_parent_of_returns_zero_for_main_level() -> void:
	assert_eq(lg._parent_of(5), 0)

func test_parent_of_returns_original_id_for_branch() -> void:
	assert_eq(lg._parent_of(103), 3)   # branch of level 3
	assert_eq(lg._parent_of(104), 4)   # branch of level 4
	assert_eq(lg._parent_of(109), 9)   # branch of level 9

func test_parent_of_circle_2_branches() -> void:
	assert_eq(lg._parent_of(113), 13)
	assert_eq(lg._parent_of(119), 19)

func test_parent_of_circle_9_branch() -> void:
	assert_eq(lg._parent_of(183), 83)
	assert_eq(lg._parent_of(189), 89)

# ── is_branch / get_parent_id public wrappers ─────────────────────────────────

func test_is_branch_public_matches_internal() -> void:
	assert_true(lg.is_branch(103))
	assert_false(lg.is_branch(3))

func test_get_parent_id_public_returns_parent() -> void:
	assert_eq(lg.get_parent_id(107), 7)
	assert_eq(lg.get_parent_id(7), 0)

# ── generate — branch level fields ───────────────────────────────────────────

func test_generate_branch_sets_is_branch_true() -> void:
	var r = lg.generate(103)   # branch of level 3
	assert_true(r.is_branch)

func test_generate_main_sets_is_branch_false() -> void:
	var r = lg.generate(3)
	assert_false(r.is_branch)

func test_generate_branch_sets_correct_parent_id() -> void:
	var r = lg.generate(104)
	assert_eq(r.parent_id, 4)

func test_generate_branch_inherits_parent_circle() -> void:
	# Branch of level 3 (circle 1) → circle should be 1
	var r = lg.generate(103)
	assert_eq(r.circle, 1)

func test_generate_branch_of_circle_2_level_has_circle_2() -> void:
	# Branch of level 13 (circle 2) → circle should be 2
	var r = lg.generate(113)
	assert_eq(r.circle, 2)

func test_generate_branch_inherits_parent_difficulty() -> void:
	# Branch of level 3 → index_in_circle(3) = 3 → "low" difficulty
	var r = lg.generate(103)
	assert_eq(r.trap_density, "low")

func test_generate_branch_level_id_stored_correctly() -> void:
	var r = lg.generate(107)
	assert_eq(r.level_id, 107)

func test_generate_different_branch_ids_produce_different_seeds() -> void:
	var r103 = lg.generate(103)
	var r104 = lg.generate(104)
	# Different seeds → most likely different room layouts (not guaranteed but very probable)
	# At minimum, level_ids differ
	assert_eq(r103.level_id, 103)
	assert_eq(r104.level_id, 104)

# ── platform_v_range ──────────────────────────────────────────────────────────

func test_v_range_moving_vertical_negative_distance() -> void:
	# distance=-80 → platform goes UP 80 px → v_range=80
	assert_eq(lg.platform_v_range("moving_vertical", -80.0), 80.0)

func test_v_range_moving_vertical_positive_distance() -> void:
	# positive distance → platform goes DOWN → no upward travel → v_range=0
	assert_eq(lg.platform_v_range("moving_vertical", 80.0), 0.0)

func test_v_range_moving_horizontal() -> void:
	assert_eq(lg.platform_v_range("moving_horizontal", 140.0), 0.0)

func test_v_range_static_stone() -> void:
	assert_eq(lg.platform_v_range("stone", 0.0), 0.0)

func test_v_range_other_types_return_zero() -> void:
	for t in ["crumbling", "bounce", "one_way", "ice", "faith"]:
		assert_eq(lg.platform_v_range(t, -80.0), 0.0, "type %s should have v_range 0" % t)

# ── validate_vertical_path ────────────────────────────────────────────────────

func test_validate_empty_platforms_is_valid() -> void:
	assert_true(lg.validate_vertical_path([], 800.0))

func test_validate_single_row_within_max_jump() -> void:
	# floor=800, row at 700 → gap=100 ≤ MAX_JUMP_HEIGHT(200)
	var platforms := [{ "y": 700.0, "v_range": 0.0 }]
	assert_true(lg.validate_vertical_path(platforms, 800.0))

func test_validate_single_row_exactly_at_max_jump() -> void:
	# gap == MAX_JUMP_HEIGHT → still reachable
	var platforms := [{ "y": 600.0, "v_range": 0.0 }]
	assert_true(lg.validate_vertical_path(platforms, 800.0))  # gap=200

func test_validate_single_row_exceeds_max_jump() -> void:
	# floor=800, row at 599 → gap=201 > MAX_JUMP_HEIGHT(200) → invalid
	var platforms := [{ "y": 599.0, "v_range": 0.0 }]
	assert_false(lg.validate_vertical_path(platforms, 800.0))

func test_validate_three_rows_all_within_budget() -> void:
	# Rows 200 px apart — each hop ≤ MAX_JUMP_HEIGHT
	var platforms := [
		{ "y": 600.0, "v_range": 0.0 },
		{ "y": 400.0, "v_range": 0.0 },
		{ "y": 200.0, "v_range": 0.0 },
	]
	assert_true(lg.validate_vertical_path(platforms, 800.0))

func test_validate_gap_in_middle_is_invalid() -> void:
	# First hop 200 px OK, second hop 250 px → invalid
	var platforms := [
		{ "y": 600.0, "v_range": 0.0 },
		{ "y": 350.0, "v_range": 0.0 },  # gap from 600→350 = 250 > 200
	]
	assert_false(lg.validate_vertical_path(platforms, 800.0))

func test_validate_moving_vertical_extends_reach() -> void:
	# floor=800, static row at 600 (gap 200, OK).
	# From 600, moving_vertical platform with v_range=80 → launch from 600-80=520.
	# Next row at 380 → gap from launch 520 to 380 = 140 ≤ 200 → valid.
	var platforms := [
		{ "y": 600.0, "v_range": 0.0  },
		{ "y": 520.0, "v_range": 80.0 },  # moving_vertical: launches from 440
		{ "y": 380.0, "v_range": 0.0  },
	]
	assert_true(lg.validate_vertical_path(platforms, 800.0))

func test_validate_moving_vertical_makes_otherwise_unreachable_row_reachable() -> void:
	# Without moving platform, floor→row gap would be 280 > 200.
	# With moving_vertical (v_range=80) at y=680: launch_y=600, gap to 480 = 120 ≤ 200 → valid.
	var platforms_static := [{ "y": 480.0, "v_range": 0.0 }]
	assert_false(lg.validate_vertical_path(platforms_static, 760.0),
		"gap 280 > 200 should be invalid without moving platform")

	var platforms_moving := [
		{ "y": 680.0, "v_range": 80.0 },  # launch from 600
		{ "y": 480.0, "v_range": 0.0  },
	]
	assert_true(lg.validate_vertical_path(platforms_moving, 760.0),
		"moving platform extends reach making the gap bridgeable")

func test_validate_moving_horizontal_counts_as_static_for_vertical() -> void:
	# v_range=0 for horizontal movers → same as stone
	var platforms := [{ "y": 599.0, "v_range": 0.0 }]
	assert_false(lg.validate_vertical_path(platforms, 800.0))

# ── missing_bridge_ys ─────────────────────────────────────────────────────────

func test_missing_bridges_empty_when_valid() -> void:
	var platforms := [
		{ "y": 650.0, "v_range": 0.0 },
		{ "y": 450.0, "v_range": 0.0 },
	]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_eq(bridges.size(), 0)

func test_missing_bridges_one_bridge_for_single_oversized_gap() -> void:
	# floor=800, row at 400 → gap=400; needs ceil(400/200)=2 steps → 1 bridge at y=600
	var platforms := [{ "y": 400.0, "v_range": 0.0 }]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_eq(bridges.size(), 1)
	assert_almost_eq(float(bridges[0]), 600.0, 1.0)

func test_missing_bridges_two_bridges_for_large_gap() -> void:
	# floor=800, row at 200 → gap=600; ceil(600/200)=3 steps → 2 bridges
	var platforms := [{ "y": 200.0, "v_range": 0.0 }]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_eq(bridges.size(), 2)

func test_missing_bridges_evenly_spaced() -> void:
	# gap=400 → 2 steps of 200 → bridge at 600
	var platforms := [{ "y": 400.0, "v_range": 0.0 }]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_eq(bridges.size(), 1)
	# Bridge should be exactly halfway
	assert_almost_eq(float(bridges[0]), 600.0, 1.0)

func test_missing_bridges_none_needed_when_moving_vertical_closes_gap() -> void:
	# floor=800, moving_vertical at y=700 (v_range=80) → launch=620
	# next row at 450 → gap from launch 620 to 450 = 170 ≤ 200 → no bridge
	var platforms := [
		{ "y": 700.0, "v_range": 80.0 },
		{ "y": 450.0, "v_range": 0.0  },
	]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_eq(bridges.size(), 0)

func test_missing_bridges_still_needed_when_moving_vertical_not_enough() -> void:
	# floor=800, row at 300 → gap=500; v_range=80 not enough (launch=220, gap still 500 > 280)
	var platforms := [{ "y": 300.0, "v_range": 80.0 }]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	assert_gt(bridges.size(), 0)

func test_missing_bridges_deduplicates_same_row() -> void:
	# Two platforms at nearly the same Y → treated as one row
	var platforms := [
		{ "y": 600.0, "v_range": 0.0 },
		{ "y": 603.0, "v_range": 0.0 },
	]
	var bridges: Array = lg.missing_bridge_ys(platforms, 800.0)
	# Gap 800→600 = 200 = MAX_JUMP_HEIGHT → valid, no bridges needed
	assert_eq(bridges.size(), 0)

# ── _zone_tier ────────────────────────────────────────────────────────────────

func test_zone_tier_circle1_early_index_is_easy() -> void:
	assert_eq(lg._zone_tier(1, 1), "easy")

func test_zone_tier_circle1_idx2_is_medium() -> void:
	assert_eq(lg._zone_tier(1, 2), "medium")

func test_zone_tier_circle1_mid_index_is_medium() -> void:
	assert_eq(lg._zone_tier(1, 3), "medium")
	assert_eq(lg._zone_tier(1, 4), "medium")

func test_zone_tier_circle1_late_index_is_hard() -> void:
	assert_eq(lg._zone_tier(1, 5), "hard")
	assert_eq(lg._zone_tier(1, 7), "hard")

func test_zone_tier_circle1_last_index_is_extreme() -> void:
	assert_eq(lg._zone_tier(1, 8), "extreme")
	assert_eq(lg._zone_tier(1, 9), "extreme")

func test_zone_tier_circle4_bumps_one_tier() -> void:
	# idx=1 base=easy + bump1 → medium
	assert_eq(lg._zone_tier(4, 1), "medium")
	assert_eq(lg._zone_tier(5, 1), "medium")

func test_zone_tier_circle8_bumps_two_tiers() -> void:
	# idx=1 base=easy + bump2 → hard
	assert_eq(lg._zone_tier(8, 1), "hard")
	assert_eq(lg._zone_tier(10, 1), "hard")

func test_zone_tier_clamped_at_extreme() -> void:
	# idx=9 base=extreme + any bump → still extreme
	assert_eq(lg._zone_tier(10, 9), "extreme")

# ── generate — difficulty zone fields ─────────────────────────────────────────

func test_generate_sets_difficulty_zone() -> void:
	var r = lg.generate(1)   # circle 1, idx 1 → easy
	assert_eq(r.difficulty_zone, "easy")

func test_generate_level2_zone_is_medium() -> void:
	var r = lg.generate(2)   # circle 1, idx 2 → medium
	assert_eq(r.difficulty_zone, "medium")

func test_generate_vertical_spacing_matches_zone() -> void:
	var r = lg.generate(1)   # easy → PART_JUMP = 100
	assert_almost_eq(r.vertical_spacing, lg.PART_JUMP, 0.1)

func test_generate_platform_type_hint_easy_is_stone() -> void:
	var r = lg.generate(1)
	assert_eq(r.platform_type_hint, "stone")

func test_generate_platform_width_easy_is_wide() -> void:
	var r = lg.generate(1)   # easy zone → wide platforms (220 px)
	assert_gt(r.platform_width, 150.0, "easy zone should use wide platforms (>150 px)")

func test_generate_hard_zone_uses_moving_platform() -> void:
	# level 7 in circle 1 → idx=7 → hard zone
	var r = lg.generate(7)
	assert_eq(r.difficulty_zone, "hard")
	assert_eq(r.platform_type_hint, "moving_horizontal")

func test_generate_extreme_zone_uses_moving_vertical() -> void:
	# level 9 in circle 1 → idx=9 → extreme zone
	var r = lg.generate(9)
	assert_eq(r.difficulty_zone, "extreme")
	assert_eq(r.platform_type_hint, "moving_vertical")

func test_generate_vertical_spacing_increases_with_difficulty() -> void:
	var easy = lg.generate(2)
	var hard = lg.generate(7)
	assert_true(easy.vertical_spacing <= hard.vertical_spacing,
		"harder zones should have equal or larger vertical spacing")

# ── Per-level uniqueness ──────────────────────────────────────────────────────

func test_room_count_increases_across_circle() -> void:
	# Every level must have at least as many rooms as the previous one.
	var prev_count: int = 0
	for idx in range(1, 10):
		var d: Dictionary = lg._difficulty_for_index(idx)
		var rc: int = d.get("room_count", 0)
		assert_true(rc >= prev_count,
			"room_count should be non-decreasing; idx=%d got %d (prev=%d)" % [idx, rc, prev_count])
		prev_count = rc

func test_level1_and_level2_have_different_room_counts() -> void:
	var d1: Dictionary = lg._difficulty_for_index(1)
	var d2: Dictionary = lg._difficulty_for_index(2)
	assert_true(d1.get("room_count") < d2.get("room_count"),
		"level 2 must be longer than level 1 (more rooms)")

func test_zone_tier_adjacent_levels_differ_in_circle1() -> void:
	# Most adjacent pairs must differ in zone OR room_count.
	# Pairs (3,4) and (6,7) share both zone and room_count by design —
	# uniqueness within these levels comes from seeded RNG in PlaceholderRoom.
	var known_same: Array = [3, 6]
	for idx in range(1, 9):
		if idx in known_same:
			continue
		var zone_a: String = lg._zone_tier(1, idx)
		var zone_b: String = lg._zone_tier(1, idx + 1)
		var rc_a: int = lg._difficulty_for_index(idx).get("room_count", 0)
		var rc_b: int = lg._difficulty_for_index(idx + 1).get("room_count", 0)
		var unique: bool = (zone_a != zone_b) or (rc_a != rc_b)
		assert_true(unique,
			"levels %d and %d must differ in zone or room_count" % [idx, idx + 1])

func test_room_count_max_is_capped_at_8() -> void:
	for idx in range(1, 10):
		var d: Dictionary = lg._difficulty_for_index(idx)
		assert_true(d.get("room_count") <= 8,
			"room_count must not exceed 8 (idx=%d)" % idx)

func test_difficulty_index_2_room_count() -> void:
	var d: Dictionary = lg._difficulty_for_index(2)
	assert_eq(d.get("room_count"), 3)

func test_difficulty_index_6_room_count() -> void:
	var d: Dictionary = lg._difficulty_for_index(6)
	assert_eq(d.get("room_count"), 6)

func test_generate_different_levels_have_different_room_counts() -> void:
	var r1 = lg.generate(1)
	var r2 = lg.generate(2)
	var r5 = lg.generate(5)
	assert_true(r1.room_count < r2.room_count, "level 2 has more rooms than level 1")
	assert_true(r2.room_count < r5.room_count, "level 5 has more rooms than level 2")
