extends GutTest

# Tests for SaveManager pure in-memory logic.
# Uses a fresh instance per test; _ready() calls _ensure_dir() + _reset().

var sm: Node

func before_each() -> void:
	sm = preload("res://scripts/managers/SaveManager.gd").new()
	add_child_autofree(sm)
	# _ready() already called _reset() — state is clean

# ── _reset ────────────────────────────────────────────────────────────────────

func test_reset_produces_default_state() -> void:
	sm.add_sin(50.0)
	sm.add_light(100)
	sm._reset()
	assert_eq(sm.get_sin(), 0.0, "sin should be 0 after reset")
	assert_eq(sm.get_light(), 0, "light should be 0 after reset")
	assert_eq(sm.get_total_souls(), 0, "souls should be 0 after reset")

func test_reset_sets_version() -> void:
	sm._reset()
	assert_eq(sm.data.get("version"), 2)

# ── Sin ───────────────────────────────────────────────────────────────────────

func test_get_sin_default_zero() -> void:
	assert_eq(sm.get_sin(), 0.0)

func test_add_sin() -> void:
	sm.add_sin(30.0)
	assert_eq(sm.get_sin(), 30.0)

func test_add_sin_accumulates() -> void:
	sm.add_sin(20.0)
	sm.add_sin(15.0)
	assert_eq(sm.get_sin(), 35.0)

func test_add_sin_clamped_at_100() -> void:
	sm.add_sin(150.0)
	assert_eq(sm.get_sin(), 100.0, "sin cannot exceed 100")

func test_reduce_sin() -> void:
	sm.add_sin(50.0)
	sm.reduce_sin(20.0)
	assert_eq(sm.get_sin(), 30.0)

func test_reduce_sin_clamped_at_zero() -> void:
	sm.add_sin(10.0)
	sm.reduce_sin(50.0)
	assert_eq(sm.get_sin(), 0.0, "sin cannot go below 0")

func test_set_sin_direct() -> void:
	sm.set_sin(75.0)
	assert_eq(sm.get_sin(), 75.0)

func test_set_sin_clamps_negative() -> void:
	sm.set_sin(-10.0)
	assert_eq(sm.get_sin(), 0.0)

func test_set_sin_clamps_over_100() -> void:
	sm.set_sin(120.0)
	assert_eq(sm.get_sin(), 100.0)

# ── Light ─────────────────────────────────────────────────────────────────────

func test_get_light_default_zero() -> void:
	assert_eq(sm.get_light(), 0)

func test_add_light() -> void:
	sm.add_light(50)
	assert_eq(sm.get_light(), 50)

func test_add_light_accumulates() -> void:
	sm.add_light(30)
	sm.add_light(20)
	assert_eq(sm.get_light(), 50)

func test_add_light_ignores_negative() -> void:
	sm.add_light(-10)
	assert_eq(sm.get_light(), 0, "negative amounts should be ignored")

func test_spend_light_success() -> void:
	sm.add_light(100)
	var ok: bool = sm.spend_light(40)
	assert_true(ok, "spend should succeed when enough light")
	assert_eq(sm.get_light(), 60)

func test_spend_light_exact_amount() -> void:
	sm.add_light(50)
	var ok: bool = sm.spend_light(50)
	assert_true(ok)
	assert_eq(sm.get_light(), 0)

func test_spend_light_fail_not_enough() -> void:
	sm.add_light(10)
	var ok: bool = sm.spend_light(50)
	assert_false(ok, "spend should fail when insufficient light")
	assert_eq(sm.get_light(), 10, "balance unchanged on failure")

func test_spend_light_zero() -> void:
	var ok: bool = sm.spend_light(0)
	assert_true(ok)

# ── Souls ─────────────────────────────────────────────────────────────────────

func test_get_total_souls_default_zero() -> void:
	assert_eq(sm.get_total_souls(), 0)

func test_add_soul_increments_count() -> void:
	sm.add_soul(1)
	assert_eq(sm.get_total_souls(), 1)

func test_add_multiple_souls() -> void:
	sm.add_soul(1)
	sm.add_soul(2)
	sm.add_soul(3)
	assert_eq(sm.get_total_souls(), 3)

func test_add_soul_no_duplicates() -> void:
	sm.add_soul(5)
	sm.add_soul(5)
	assert_eq(sm.get_total_souls(), 1, "duplicate soul_id should not be added twice")

func test_has_soul_true() -> void:
	sm.add_soul(7)
	assert_true(sm.has_soul(7))

func test_has_soul_false() -> void:
	assert_false(sm.has_soul(99))

func test_get_saved_soul_ids() -> void:
	sm.add_soul(10)
	sm.add_soul(20)
	var ids: Array = sm.get_saved_soul_ids()
	assert_true(10 in ids)
	assert_true(20 in ids)
	assert_eq(ids.size(), 2)

# ── Hidden souls ──────────────────────────────────────────────────────────────

func test_add_hidden_soul() -> void:
	sm.add_hidden_soul("hidden_01")
	assert_eq(sm.get_total_hidden_souls(), 1)

func test_add_hidden_soul_no_duplicates() -> void:
	sm.add_hidden_soul("hidden_01")
	sm.add_hidden_soul("hidden_01")
	assert_eq(sm.get_total_hidden_souls(), 1)

func test_get_hidden_soul_ids() -> void:
	sm.add_hidden_soul("hidden_02")
	assert_true("hidden_02" in sm.get_hidden_soul_ids())

# ── Upgrades ──────────────────────────────────────────────────────────────────

func test_get_upgrade_level_default_zero() -> void:
	assert_eq(sm.get_upgrade_level("vitality"), 0)

func test_set_and_get_upgrade_level() -> void:
	sm.set_upgrade_level("vitality", 2)
	assert_eq(sm.get_upgrade_level("vitality"), 2)

func test_set_upgrade_level_multiple() -> void:
	sm.set_upgrade_level("vitality", 1)
	sm.set_upgrade_level("dash", 3)
	assert_eq(sm.get_upgrade_level("vitality"), 1)
	assert_eq(sm.get_upgrade_level("dash"), 3)

func test_has_upgrade_false_when_zero() -> void:
	assert_false(sm.has_upgrade("forgiveness"))

func test_has_upgrade_true_when_set() -> void:
	sm.set_upgrade_level("forgiveness", 1)
	assert_true(sm.has_upgrade("forgiveness"))

func test_upgrade_level_not_negative() -> void:
	sm.set_upgrade_level("vitality", -5)
	assert_eq(sm.get_upgrade_level("vitality"), 0, "upgrade level cannot be negative")

# ── Flags ─────────────────────────────────────────────────────────────────────

func test_get_flag_default_false() -> void:
	assert_false(sm.get_flag("no_ads_purchased"))

func test_set_flag_true() -> void:
	sm.set_flag("no_ads_purchased", true)
	assert_true(sm.get_flag("no_ads_purchased"))

func test_set_flag_false() -> void:
	sm.set_flag("no_ads_purchased", true)
	sm.set_flag("no_ads_purchased", false)
	assert_false(sm.get_flag("no_ads_purchased"))

func test_has_reward_alias() -> void:
	sm.set_flag("no_ads_purchased", true)
	assert_true(sm.has_reward("no_ads_purchased"))

# ── Hints / Tutorial ──────────────────────────────────────────────────────────

func test_is_hint_seen_default_false() -> void:
	assert_false(sm.is_hint_seen("prologue_done"))

func test_mark_hint_seen() -> void:
	sm.mark_hint_seen("prologue_done")
	assert_true(sm.is_hint_seen("prologue_done"))

func test_mark_hint_seen_no_duplicates() -> void:
	sm.mark_hint_seen("tip_01")
	sm.mark_hint_seen("tip_01")
	assert_eq(sm.data.get("seen_tutorial_hints", []).size(), 1)

func test_clear_all_hints() -> void:
	sm.mark_hint_seen("tip_01")
	sm.mark_hint_seen("tip_02")
	sm.clear_all_hints()
	assert_false(sm.is_hint_seen("tip_01"))
	assert_eq(sm.data.get("seen_tutorial_hints", []).size(), 0)

# ── Stats ─────────────────────────────────────────────────────────────────────

func test_demon_deals_default_zero() -> void:
	assert_eq(sm.get_demon_deals_accepted(), 0)

func test_increment_demon_deals() -> void:
	sm.increment_demon_deals()
	sm.increment_demon_deals()
	assert_eq(sm.get_demon_deals_accepted(), 2)

func test_deals_refused_default_zero() -> void:
	assert_eq(sm.get_deals_refused(), 0)

func test_increment_deals_refused() -> void:
	sm.increment_deals_refused()
	assert_eq(sm.get_deals_refused(), 1)

func test_secret_levels_found() -> void:
	assert_eq(sm.get_secret_levels_found(), 0)
	sm.increment_secret_levels()
	assert_eq(sm.get_secret_levels_found(), 1)

# ── Progress ──────────────────────────────────────────────────────────────────

func test_current_level_default_one() -> void:
	assert_eq(sm.get_current_level(), 1)

func test_set_current_level() -> void:
	sm.set_current_level(15)
	assert_eq(sm.get_current_level(), 15)

func test_set_current_level_not_less_than_one() -> void:
	sm.set_current_level(0)
	assert_eq(sm.get_current_level(), 1)

func test_current_circle_default_one() -> void:
	assert_eq(sm.get_current_circle(), 1)

func test_set_current_circle() -> void:
	sm.set_current_circle(3)
	assert_eq(sm.get_current_circle(), 3)

# ── Migration v1 → v2 ─────────────────────────────────────────────────────────

func test_migrate_v1_moves_active_rewards_to_flags() -> void:
	sm.data = {
		"version": 1,
		"active_rewards": ["no_ads_purchased"],
		"flags": {},
	}
	sm._migrate()
	assert_true(sm.get_flag("no_ads_purchased"), "reward should become a flag after migration")
	assert_eq(sm.data.get("version"), 2)

func test_migrate_skips_if_already_v2() -> void:
	sm._reset()
	var original_data: Dictionary = sm.data.duplicate(true)
	sm._migrate()
	assert_eq(sm.data, original_data, "v2 data should be unchanged")

# ── Endings ───────────────────────────────────────────────────────────────────

func test_unlock_ending() -> void:
	sm.unlock_ending("true_ending")
	assert_true("true_ending" in sm.get_unlocked_endings())

func test_unlock_ending_no_duplicates() -> void:
	sm.unlock_ending("true_ending")
	sm.unlock_ending("true_ending")
	assert_eq(sm.get_unlocked_endings().size(), 1)
