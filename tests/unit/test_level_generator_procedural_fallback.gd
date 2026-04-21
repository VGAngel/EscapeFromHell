extends GutTest

# Covers LevelGenerator.generate_procedural() — used by LevelBase when a
# static-flagged level (circle opener, milestone) has no hand-authored
# content in its scene. Without this fallback level 1 spawns the player
# into an empty RoomContainer and they fall forever.
#
# Uses the autoload directly (same instance the runtime uses) so the
# config is already loaded.

var lg: Node

func before_each() -> void:
	lg = LevelGenerator

# ── Sanity: a "static" level normally returns no room paths ───────────────────

func test_static_level_has_no_rooms_in_plain_generate() -> void:
	var res: Object = lg.generate(1)   # level 1 — circle opener
	assert_true(res.is_static)
	assert_eq(res.room_scenes.size(), 0,
		"plain generate() short-circuits for static levels")

# ── generate_procedural forces real generation ────────────────────────────────

func test_generate_procedural_bypasses_static_flag_for_circle_opener() -> void:
	var res: Object = lg.generate_procedural(1)
	assert_false(res.is_static)
	assert_gt(res.room_scenes.size(), 0,
		"generate_procedural must return a populated room list even when " +
		"the level is tagged as static")

func test_generate_procedural_returns_expected_room_count_for_level_1() -> void:
	var res: Object = lg.generate_procedural(1)
	# levels_1_3 difficulty → room_count = 3 (entrance + main + exit)
	assert_eq(res.room_scenes.size(), 3)

func test_generate_procedural_first_is_entrance_last_is_exit() -> void:
	var res: Object = lg.generate_procedural(1)
	assert_true(res.room_scenes[0].contains("entrance"))
	assert_true(res.room_scenes[res.room_scenes.size() - 1].contains("exit"))

# ── Restores static flag afterwards (no permanent state mutation) ─────────────

func test_generate_procedural_does_not_permanently_remove_static_flag() -> void:
	var _tmp: Object = lg.generate_procedural(1)
	assert_true(lg.is_static(1),
		"generate_procedural must restore the level's static flag once it " +
		"returns — otherwise subsequent generate() calls would no longer " +
		"short-circuit.")
