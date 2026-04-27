extends GutTest

# Tests for Player soul-carry array logic (soul_echo upgrade support).
# Pure-state asserts — no scene tree gymnastics, no awaits.

var player: Node

func before_each() -> void:
	# Player has @onready references (Camera, Sprite, AnimationPlayer) that
	# would crash on .new(), so we instantiate the scene instead.
	var packed := load("res://scenes/Player.tscn") as PackedScene
	if packed:
		player = packed.instantiate()
	else:
		# Fall back to bare script if the scene is unavailable in the test env.
		player = preload("res://scripts/Player.gd").new()
	add_child_autofree(player)
	if SaveManager:
		SaveManager._reset()

# ── Default state ────────────────────────────────────────────────────────────

func test_default_carried_list_is_empty() -> void:
	assert_eq(player.carried_soul_ids.size(), 0)

func test_is_carrying_false_by_default() -> void:
	assert_false(player.is_carrying())

func test_soul_capacity_default_is_one() -> void:
	# Without the upgrade we can carry one soul.
	assert_eq(player.soul_capacity(), 1)

# ── soul_echo upgrade flips capacity ─────────────────────────────────────────

func test_soul_capacity_with_upgrade_is_two() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	SaveManager.set_upgrade_level("soul_echo", 1)
	assert_eq(player.soul_capacity(), 2)

func test_is_full_respects_capacity_one() -> void:
	player.carried_soul_ids.append("alpha")
	assert_true(player.is_full(),
		"1 carried with capacity 1 should be full")

func test_is_full_with_upgrade_two_slots() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	SaveManager.set_upgrade_level("soul_echo", 1)
	player.carried_soul_ids.append("alpha")
	assert_false(player.is_full(),
		"1 carried with capacity 2 should NOT be full")
	player.carried_soul_ids.append("beta")
	assert_true(player.is_full(),
		"2 carried with capacity 2 should be full")

# ── _drop_soul clears everything ─────────────────────────────────────────────

func test_drop_soul_clears_array() -> void:
	player.carried_soul_ids.append("alpha")
	player.carried_soul_ids.append("beta")
	player._drop_soul()
	assert_eq(player.carried_soul_ids.size(), 0)
	assert_false(player.is_carrying())

func test_drop_soul_emits_carry_changed_zero() -> void:
	if not player.has_signal("carry_changed"):
		pending("carry_changed signal not present")
		return
	player.carried_soul_ids.append("alpha")
	watch_signals(player)
	player._drop_soul()
	assert_signal_emitted_with_parameters(player, "carry_changed",
		[0, player.soul_capacity()])
