extends GutTest

# Tests for BaseEnemy fatigue lerp + vertical sight clamp constants.
# Pure-state asserts — no scene tree, no physics ticks.

var enemy: Node

func before_each() -> void:
	enemy = preload("res://scripts/enemies/BaseEnemy.gd").new()
	add_child_autofree(enemy)

# ── Constants ────────────────────────────────────────────────────────────────

func test_fatigue_constants_match_design() -> void:
	assert_almost_eq(enemy.FATIGUE_MAX_SECONDS, 14.0, 0.001,
		"Circle 1 fatigue should be ~14s")
	assert_almost_eq(enemy.FATIGUE_MIN_SECONDS,  6.0, 0.001,
		"Circle 10 fatigue should be ~6s")
	assert_lt(enemy.FATIGUE_MIN_SECONDS, enemy.FATIGUE_MAX_SECONDS,
		"min must be less than max for the lerp to make sense")

# ── _fatigue_for_circle (no room context = mid-tier fallback) ────────────────

func test_fatigue_no_room_returns_default() -> void:
	# No parent room with "circle" → mid-tier 10s fallback so the enemy is
	# still usable in tests / sandbox scenes.
	assert_eq(enemy._fatigue_for_circle(), 10.0)

# ── _fatigue_for_circle with synthetic parent ────────────────────────────────

func _wrap_in_room(circle: int) -> Node2D:
	# The parent walk in _resolve_room_circle uses the property `circle`.
	# A small Resource-free Node2D with a script that exposes it works.
	var room := Node2D.new()
	var script := GDScript.new()
	script.source_code = "extends Node2D\n@export var circle: int = 0\n"
	script.reload()
	room.set_script(script)
	room.circle = circle
	add_child_autofree(room)
	# Re-parent the enemy under the new room.
	if enemy.get_parent():
		enemy.get_parent().remove_child(enemy)
	room.add_child(enemy)
	return room

func test_fatigue_circle_1_returns_max() -> void:
	_wrap_in_room(1)
	assert_almost_eq(enemy._fatigue_for_circle(), 14.0, 0.001)

func test_fatigue_circle_10_returns_min() -> void:
	_wrap_in_room(10)
	assert_almost_eq(enemy._fatigue_for_circle(), 6.0, 0.001)

func test_fatigue_circle_5_is_mid_range() -> void:
	_wrap_in_room(5)
	# Linear interp: 14 - (4/9)*8 ≈ 10.44
	assert_almost_eq(enemy._fatigue_for_circle(), 10.444, 0.05)

func test_fatigue_clamps_above_circle_10() -> void:
	_wrap_in_room(99)
	assert_almost_eq(enemy._fatigue_for_circle(), 6.0, 0.001,
		"clampf prevents going below FATIGUE_MIN_SECONDS")

# ── _begin_fatigue + reset_to_patrol ─────────────────────────────────────────

func test_begin_fatigue_sets_timer() -> void:
	enemy._begin_fatigue()
	assert_gt(enemy._fatigue_timer, 0.0,
		"_begin_fatigue should leave the timer counting down")

func test_reset_to_patrol_clears_fatigue() -> void:
	enemy._fatigue_timer = 5.0
	enemy.reset_to_patrol()
	assert_eq(enemy._fatigue_timer, 0.0,
		"respawn clears any leftover fatigue")

func test_explicit_fatigue_duration_overrides_circle() -> void:
	_wrap_in_room(1)   # would normally yield 14s
	enemy.fatigue_duration = 3.5
	enemy._begin_fatigue()
	assert_almost_eq(enemy._fatigue_timer, 3.5, 0.001,
		"non-zero export wins over circle-derived value")

# ── max_vertical_sight ───────────────────────────────────────────────────────

func test_max_vertical_sight_default_value() -> void:
	assert_eq(enemy.max_vertical_sight, 100.0,
		"default vertical sight clamp should be 100 px")

func test_max_vertical_sight_writable() -> void:
	enemy.max_vertical_sight = 0.0
	assert_eq(enemy.max_vertical_sight, 0.0,
		"0 disables the clamp (e.g. flying enemies)")
	enemy.max_vertical_sight = 250.0
	assert_eq(enemy.max_vertical_sight, 250.0)
