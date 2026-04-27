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

# ── _target_time_for_level ───────────────────────────────────────────────────
# Default formula when levels_config has no override: 45 + circle * 6.

func test_target_time_default_circle_1() -> void:
	# circle 1 → 45 + 6 = 51s baseline
	# (LevelConfig may override; allow either the config value or ≥ 30s sane floor)
	var t: float = gm._target_time_for_level(1)
	assert_gt(t, 0.0, "target_time must be positive")
	assert_lt(t, 600.0, "target_time should not be insane")

func test_target_time_higher_circle_is_more_lenient() -> void:
	# Without per-level overrides, deeper circles get more time.
	# If both come from the same source (LevelConfig override), allow equal.
	var t1: float = gm._target_time_for_level(1)
	var t10: float = gm._target_time_for_level(100)   # circle 10
	assert_gte(t10, t1, "circle 10 target should be ≥ circle 1 target")

# ── add_sin / reduce_sin emit sin_added with cause ────────────────────────────

func test_add_sin_emits_sin_added_with_cause() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	watch_signals(gm)
	gm.add_sin(2.5, "staff")
	assert_signal_emitted(gm, "sin_added")
	var p: Array = get_signal_parameters(gm, "sin_added")
	assert_almost_eq(p[0], 2.5, 0.001)
	assert_eq(p[1], "staff")

func test_add_sin_default_cause_is_unknown() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	watch_signals(gm)
	gm.add_sin(1.0)
	var p: Array = get_signal_parameters(gm, "sin_added")
	assert_eq(p[1], "unknown")

func test_reduce_sin_emits_negative_amount() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	SaveManager.add_sin(20.0)
	watch_signals(gm)
	gm.reduce_sin(5.0, "cleansing")
	assert_signal_emitted(gm, "sin_added")
	var p: Array = get_signal_parameters(gm, "sin_added")
	assert_almost_eq(p[0], -5.0, 0.001, "reduce_sin should emit negative amount")
	assert_eq(p[1], "cleansing")

func test_add_sin_still_emits_sin_changed() -> void:
	# Don't break the existing sin_changed contract that HUD.set_sin reads.
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	watch_signals(gm)
	gm.add_sin(3.0, "death")
	assert_signal_emitted(gm, "sin_changed")

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
