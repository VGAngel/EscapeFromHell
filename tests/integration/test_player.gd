extends GutTest

# Integration tests for Player.gd.
# Require a full scene tree with physics, input, and child nodes.
# Most tests are stubs — implement after scene setup is stable.

var player: CharacterBody2D

func before_each() -> void:
	# TODO: load Player.tscn, add to scene, wait one physics frame
	# player = preload("res://scenes/Player.tscn").instantiate()
	# add_child_autofree(player)
	# await get_tree().physics_frame
	pass

# ── Pure helpers (no physics) ─────────────────────────────────────────────────

func test_state_to_anim_idle() -> void:
	# TODO: assert player._state_to_anim(Player.State.IDLE) == "player_idle"
	pass

func test_state_to_anim_walk() -> void:
	# TODO: assert player._state_to_anim(Player.State.WALK) == "player_walk"
	pass

func test_state_to_anim_jump() -> void:
	# TODO: assert player._state_to_anim(Player.State.JUMP) == "player_jump"
	pass

func test_state_to_anim_fall() -> void:
	# TODO: assert player._state_to_anim(Player.State.FALL) == "player_fall"
	pass

func test_is_carrying_false_by_default() -> void:
	# TODO: assert player.is_carrying() == false
	pass

func test_is_carrying_true_when_soul_set() -> void:
	# TODO: player.carried_soul_id = "soul_01"; assert player.is_carrying()
	pass

func test_get_staff_cooldown_ratio_full_at_start() -> void:
	# TODO: assert player.get_staff_cooldown_ratio() == 1.0 at start
	pass

# ── Movement ──────────────────────────────────────────────────────────────────

func test_player_moves_right_on_input() -> void:
	# TODO: simulate "move_right" action press, process one physics frame,
	# assert velocity.x > 0
	pass

func test_player_jumps_on_input_when_on_floor() -> void:
	# TODO: place player on floor, simulate "jump" action,
	# assert velocity.y < 0
	pass

func test_player_wall_hang_on_wall_contact() -> void:
	# TODO: place player against wall mid-air,
	# assert _state == Player.State.WALL_HANG
	pass

func test_player_deceleration_on_release() -> void:
	# TODO: simulate move_right, then release, assert velocity.x approaches 0
	pass

func test_landing_decel_burst_after_fall() -> void:
	# TODO: drop player from height, on landing assert _landing_decel_timer > 0
	pass

# ── Damage / Death ────────────────────────────────────────────────────────────

func test_player_hp_decreases_on_damage() -> void:
	# TODO: call player._take_damage(1); assert HP decreased
	pass

func test_player_dies_when_hp_reaches_zero() -> void:
	# TODO: call _take_damage repeatedly; assert player_died signal emitted
	pass

func test_player_death_emits_signal() -> void:
	# TODO: watch player_died signal, reduce HP to 0, assert signal received
	pass

func test_player_knockback_applied_on_hit() -> void:
	# TODO: call _apply_knockback(Vector2.RIGHT); assert _knockback_vel.x > 0
	pass

# ── Staff ─────────────────────────────────────────────────────────────────────

func test_staff_hit_damages_enemy_in_range() -> void:
	# TODO: spawn enemy in StaffArea, simulate "action" press, assert enemy HP reduced
	pass

func test_staff_cooldown_prevents_double_swing() -> void:
	# TODO: swing staff twice rapidly, assert second swing has no hit
	pass

func test_hit_stop_pauses_time_scale() -> void:
	# TODO: confirm Engine.time_scale goes to 0 during hit-stop then returns to 1
	pass

# ── Soul carry ────────────────────────────────────────────────────────────────

func test_player_picks_up_soul() -> void:
	# TODO: place Soul node near player, trigger body_entered,
	# assert player.is_carrying()
	pass

func test_soul_carry_visual_becomes_visible() -> void:
	# TODO: assert SoulCarryVisual.visible == true when carrying
	pass

# ── Respawn ───────────────────────────────────────────────────────────────────

func test_respawn_restores_hp() -> void:
	# TODO: damage player, call respawn(), assert hp == max_hp
	pass

func test_respawn_sprite_fade_in() -> void:
	# TODO: after respawn(), assert _sprite.modulate.a increases from 0 to 1
	pass

func test_respawn_clears_knockback() -> void:
	# TODO: after respawn(), assert _knockback_vel == Vector2.ZERO
	pass
