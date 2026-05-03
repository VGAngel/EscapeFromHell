extends GutTest

# Unit tests for LevelCamera's combat lock-on zoom contract.
#
# Drive _enemy_in_combat_range directly with stub Node2Ds that mimic
# BaseEnemy's `state` field. Avoids spinning up the whole player +
# camera + room setup just to assert a state-based predicate.

var camera: Camera2D
var player: Node2D


func before_each() -> void:
	# Player stub provides a global_position for distance checks.
	player = autofree(Node2D.new())
	add_child(player)
	player.global_position = Vector2.ZERO

	camera = autofree(preload("res://scripts/managers/LevelCamera.gd").new())
	# Skip _ready (it loads camera_config.json + queries scene tree).
	# Just instantiate so we can call methods.
	add_child(camera)


# Helper: build a fake enemy in the "enemy" group with a given AI state
# at a given offset from origin (= player position in tests).
func _spawn_fake_enemy(at: Vector2, state_int: int) -> Node2D:
	var e := Node2D.new()
	add_child_autofree(e)
	e.add_to_group("enemy")
	e.global_position = at
	e.set("state", state_int)
	return e


# ── _enemy_in_combat_range ────────────────────────────────────────────────────

func test_no_enemies_returns_false() -> void:
	assert_false(camera._enemy_in_combat_range(player))


func test_far_alert_enemy_returns_false() -> void:
	# COMBAT_ZOOM_RADIUS = 400 px. 600 px out is comfortably ignored.
	_spawn_fake_enemy(Vector2(600, 0), 1)  # 1 = ALERT
	assert_false(camera._enemy_in_combat_range(player))


func test_close_alert_enemy_returns_true() -> void:
	_spawn_fake_enemy(Vector2(200, 0), 1)  # 1 = ALERT
	assert_true(camera._enemy_in_combat_range(player))


func test_close_chase_enemy_returns_true() -> void:
	_spawn_fake_enemy(Vector2(150, 50), 2)  # 2 = CHASE
	assert_true(camera._enemy_in_combat_range(player))


func test_close_patrol_enemy_returns_false() -> void:
	# Patrolling enemies don't trigger the boost — only active threats.
	_spawn_fake_enemy(Vector2(100, 0), 0)  # 0 = PATROL
	assert_false(camera._enemy_in_combat_range(player))


func test_close_stunned_enemy_returns_false() -> void:
	_spawn_fake_enemy(Vector2(100, 0), 5)  # 5 = STUNNED
	assert_false(camera._enemy_in_combat_range(player))


func test_mixed_one_chase_among_patrols_triggers() -> void:
	# Single chase enemy among multiple harmless patrollers should still
	# raise the boost — combat focus tracks the most threatening member.
	_spawn_fake_enemy(Vector2(100, 0), 0)
	_spawn_fake_enemy(Vector2(120, 30), 0)
	_spawn_fake_enemy(Vector2(140, -30), 2)
	assert_true(camera._enemy_in_combat_range(player))


func test_null_player_returns_false() -> void:
	# Defensive: parent could be null right after a scene swap.
	assert_false(camera._enemy_in_combat_range(null))
