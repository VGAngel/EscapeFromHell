extends GutTest

# Tests for GameManager pure scoring/calculation logic.
# Uses a fresh GameManager instance to avoid polluting the autoload singleton.

var gm: Node

func before_each() -> void:
	gm = preload("res://scripts/managers/GameManager.gd").new()
	add_child_autofree(gm)
	# Clean SaveManager state so _base_max_hp reads fresh upgrades
	if SaveManager:
		SaveManager._reset()

# ── _calc_stars ───────────────────────────────────────────────────────────────
# New rubric (per per-level personal-best system):
#   1 = clear (any completion)
#   2 = clear + no deaths
#   3 = clear + no deaths + finished within target_time

func test_calc_stars_all_souls_no_deaths_under_target_gives_3() -> void:
	# elapsed=1.0 is well under any target_time → max stars
	assert_eq(gm._calc_stars(10, 10, 0, 1.0), 3)

func test_calc_stars_all_souls_no_deaths_over_target_gives_2() -> void:
	# Without an explicit elapsed, default INF means "missed gold time"
	assert_eq(gm._calc_stars(10, 10, 0), 2)

func test_calc_stars_one_death_caps_at_1() -> void:
	# Any death drops the run to 1 star regardless of soul count or time
	assert_eq(gm._calc_stars(10, 10, 1, 1.0), 1)

func test_calc_stars_three_deaths_gives_1() -> void:
	assert_eq(gm._calc_stars(10, 10, 3, 1.0), 1)

func test_calc_stars_missing_souls_gives_1() -> void:
	assert_eq(gm._calc_stars(5, 10, 0, 1.0), 1, "missing souls always 1 star")

func test_calc_stars_zero_souls_zero_total_under_target_gives_3() -> void:
	# Edge: found >= total when both are 0; elapsed under target → 3
	assert_eq(gm._calc_stars(0, 0, 0, 1.0), 3)

func test_calc_stars_zero_found_nonzero_total_gives_1() -> void:
	assert_eq(gm._calc_stars(0, 5, 0, 1.0), 1)

func test_calc_stars_found_exceeds_total_under_target_gives_3() -> void:
	# Defensive: found > total still counts as cleared
	assert_eq(gm._calc_stars(12, 10, 0, 1.0), 3)

# ── _calc_light ───────────────────────────────────────────────────────────────

func test_calc_light_all_souls_no_deaths() -> void:
	assert_eq(gm._calc_light(10, 10, 0), 15, "base 10 + 5 bonus = 15")

func test_calc_light_partial_souls_no_deaths() -> void:
	assert_eq(gm._calc_light(5, 10, 0), 10, "base 10, no bonus")

func test_calc_light_deaths_reduce_reward() -> void:
	assert_eq(gm._calc_light(10, 10, 2), 11, "15 - 2*2 = 11")

func test_calc_light_many_deaths_clamped_to_one() -> void:
	assert_eq(gm._calc_light(0, 10, 10), 1, "10 - 20 = -10, clamped to 1")

func test_calc_light_all_souls_with_deaths_clamped() -> void:
	assert_eq(gm._calc_light(10, 10, 10), 1, "15 - 20 = -5, clamped to 1")

func test_calc_light_never_returns_zero() -> void:
	var result: int = gm._calc_light(0, 100, 100)
	assert_gte(result, 1, "light reward minimum is 1")

func test_calc_light_zero_souls_zero_total_no_deaths() -> void:
	assert_eq(gm._calc_light(0, 0, 0), 15, "0 >= 0 triggers bonus")

# ── _base_max_hp ──────────────────────────────────────────────────────────────

func test_base_max_hp_default_three() -> void:
	assert_eq(gm._base_max_hp(), 3, "default HP is 3")

func test_base_max_hp_with_vitality_1() -> void:
	if not SaveManager:
		pass_test("SaveManager not available — skipping")
		return
	SaveManager.set_upgrade_level("vitality", 1)
	assert_eq(gm._base_max_hp(), 4)

func test_base_max_hp_with_vitality_3() -> void:
	if not SaveManager:
		pass_test("SaveManager not available — skipping")
		return
	SaveManager.set_upgrade_level("vitality", 3)
	assert_eq(gm._base_max_hp(), 6)

func test_base_max_hp_capped_at_six() -> void:
	if not SaveManager:
		pass_test("SaveManager not available — skipping")
		return
	SaveManager.set_upgrade_level("vitality", 10)
	assert_eq(gm._base_max_hp(), 6, "HP capped at 6 regardless of vitality")

func test_base_max_hp_minimum_one() -> void:
	# Clampi lower bound — base is always >= 1
	assert_gte(gm._base_max_hp(), 1)
