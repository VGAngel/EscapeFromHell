extends GutTest

# Tests for SaveManager statistics helpers (used by StatisticsScreen).

var sm: Node

func before_each() -> void:
	sm = preload("res://scripts/managers/SaveManager.gd").new()
	add_child_autofree(sm)
	# _ready already called _reset()

# ── add_stat / get_stat ───────────────────────────────────────────────────────

func test_get_stat_returns_default_when_unset() -> void:
	assert_eq(sm.get_stat("anything", 42), 42)

func test_add_stat_creates_and_increments() -> void:
	sm.add_stat("deaths_total", 1)
	sm.add_stat("deaths_total", 2)
	assert_eq(sm.get_stat("deaths_total"), 3)

func test_add_stat_independent_keys() -> void:
	sm.add_stat("a", 5)
	sm.add_stat("b", 10)
	assert_eq(sm.get_stat("a"), 5)
	assert_eq(sm.get_stat("b"), 10)

# ── deaths_by_cause ───────────────────────────────────────────────────────────

func test_deaths_by_cause_starts_empty() -> void:
	assert_eq(sm.get_deaths_by_cause(), {})

func test_incr_death_cause_increments_per_cause() -> void:
	sm.incr_death_cause("fall")
	sm.incr_death_cause("fall")
	sm.incr_death_cause("enemy_hit")
	var causes: Dictionary = sm.get_deaths_by_cause()
	assert_eq(causes.get("fall"), 2)
	assert_eq(causes.get("enemy_hit"), 1)

# ── play time ─────────────────────────────────────────────────────────────────

func test_add_play_time_accumulates() -> void:
	sm.add_play_time(30.5)
	sm.add_play_time(60.0)
	assert_almost_eq(sm.get_stat("total_play_seconds", 0.0), 90.5, 0.001)

# ── spend_light writes light_spent_total ──────────────────────────────────────

func test_spend_light_records_total_spent() -> void:
	sm.add_light(50)
	assert_true(sm.spend_light(20))
	assert_eq(sm.get_stat("light_spent_total"), 20)
	assert_true(sm.spend_light(15))
	assert_eq(sm.get_stat("light_spent_total"), 35)

func test_spend_light_failure_does_not_record() -> void:
	# get_light() returns 0 by default; spending more than balance should fail
	# AND not bump the stat.
	assert_false(sm.spend_light(100))
	assert_eq(sm.get_stat("light_spent_total", 0), 0)
