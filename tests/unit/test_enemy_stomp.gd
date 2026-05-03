extends GutTest

# Unit tests for the stomp interaction on BaseEnemy.
#
# Covers:
#   - stomp_killable=true → enemy is removed from the "enemy" group
#     and receive_stomp returns "killed".
#   - stomp_killable=false → enemy enters STUNNED state and
#     receive_stomp returns "stunned".
#   - Already-stunned unkillable enemy → returns "ignored".
#
# Tests run against BaseEnemy directly. The script extends
# CharacterBody2D, so it's safe to instantiate without a scene; we
# autofree the node to avoid leaks across the suite.

var enemy: CharacterBody2D


func before_each() -> void:
	enemy = autofree(preload("res://scripts/enemies/BaseEnemy.gd").new())
	add_child(enemy)
	enemy.add_to_group("enemy")


# ── stomp_killable=true ───────────────────────────────────────────────────────

func test_killable_stomp_returns_killed() -> void:
	enemy.stomp_killable = true
	var result: String = enemy.receive_stomp()
	assert_eq(result, "killed")


func test_killable_stomp_removes_from_enemy_group() -> void:
	enemy.stomp_killable = true
	enemy.receive_stomp()
	assert_false(enemy.is_in_group("enemy"),
		"killed enemy should be removed from 'enemy' group so the player " +
		"stomp loop and other AI scans skip it during the death fade")


func test_killable_stomp_zeroes_collision() -> void:
	# After a stomp-kill the player must be able to bounce up through the
	# corpse without being blocked by it.
	enemy.stomp_killable = true
	enemy.receive_stomp()
	assert_eq(enemy.collision_layer, 0)
	assert_eq(enemy.collision_mask,  0)


# ── stomp_killable=false (armoured) ───────────────────────────────────────────

func test_unkillable_stomp_returns_stunned() -> void:
	enemy.stomp_killable = false
	var result: String = enemy.receive_stomp()
	assert_eq(result, "stunned")


func test_unkillable_stomp_enters_stunned_state() -> void:
	enemy.stomp_killable = false
	enemy.receive_stomp()
	# State enum lives on BaseEnemy — we compare the int value.
	assert_eq(enemy.state, enemy.State.STUNNED)


func test_unkillable_stomp_keeps_enemy_in_group() -> void:
	# Stunned enemies are still enemies; the player can later finish them
	# off with the staff or another stomp.
	enemy.stomp_killable = false
	enemy.receive_stomp()
	assert_true(enemy.is_in_group("enemy"))


# ── Repeated stomps ───────────────────────────────────────────────────────────

func test_already_stunned_unkillable_returns_ignored() -> void:
	# A second stomp on a stunned, armoured enemy should not refresh the
	# stun nor add another sin penalty for the player; receive_stomp must
	# return "ignored" so Player skips the FX/sin path.
	enemy.stomp_killable = false
	enemy.receive_stomp()
	var second: String = enemy.receive_stomp()
	assert_eq(second, "ignored")
