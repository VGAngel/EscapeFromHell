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

# ── receive_hit (pursuer / external hazard) ────────────────────────────────────

const PlayerScript := preload("res://scripts/Player.gd")

func test_receive_hit_reduces_hp() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp = 3
	p.max_hp     = 3
	p.receive_hit(1, Vector2.ZERO)
	assert_eq(p.current_hp, 2)

func test_receive_hit_applies_knockback_when_not_invincible() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp          = 3
	p._invincibility_timer = 0.0
	p._soul_shield_timer   = 0.0
	p.velocity            = Vector2.ZERO
	p.receive_hit(1, Vector2(0.0, -400.0))
	assert_lt(p.velocity.y, 0.0)   # velocity pushed upward

func test_receive_hit_blocked_when_invincible() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp          = 3
	p._invincibility_timer = 1.0   # already invincible
	p.velocity            = Vector2.ZERO
	p.receive_hit(1, Vector2(0.0, -400.0))
	assert_eq(p.current_hp, 3)          # HP unchanged
	assert_almost_eq(p.velocity.y, 0.0, 0.001)  # no knockback

func test_receive_hit_blocked_by_soul_shield() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp         = 3
	p._soul_shield_timer  = 2.0
	p.velocity           = Vector2.ZERO
	p.receive_hit(1, Vector2(0.0, -400.0))
	assert_eq(p.current_hp, 3)

func test_receive_hit_sets_invincibility_after_hit() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp          = 3
	p._invincibility_timer = 0.0
	p.receive_hit(1, Vector2.ZERO)
	assert_gt(p._invincibility_timer, 0.0)

func test_receive_hit_emits_hp_changed_signal() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp = 3
	p.max_hp     = 3
	watch_signals(p)
	p.receive_hit(1, Vector2.ZERO)
	assert_signal_emitted(p, "hp_changed")

func test_receive_hit_kills_at_zero_hp() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp = 1
	watch_signals(p)
	p.receive_hit(1, Vector2.ZERO)
	assert_signal_emitted(p, "player_died")

func test_receive_hit_knockback_adds_to_existing_velocity() -> void:
	var p: Node = autofree(PlayerScript.new())
	p.current_hp = 3
	p.velocity   = Vector2(100.0, 0.0)   # already moving right
	p.receive_hit(1, Vector2(0.0, -300.0))
	assert_almost_eq(p.velocity.x, 100.0, 0.001)  # horizontal unchanged
	assert_lt(p.velocity.y, 0.0)                   # vertical pushed up

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

# ── Fall damage tiers (test 5) + walk-off-ledge regression (test 6) ───────────
#
# _update_fall_tracking is pure: takes (on_floor, current_y), updates
# _fall_start_y, and on landing dispatches to _apply_fall_damage_for(fallen)
# which maps fallen px → tier → _take_damage.
#
# We can't fake CharacterBody2D.is_on_floor() because Godot 4 forbids
# overriding native methods, so tests drive _update_fall_tracking and
# _apply_fall_damage_for directly without touching physics.

func _make_test_player() -> CharacterBody2D:
	# autofree() avoids add_child → _ready() never runs, but signals
	# (hp_changed, player_died) and instance fields are still usable.
	var p: CharacterBody2D = autofree(PlayerScript.new())
	p.current_hp           = 3
	p.max_hp               = 3
	p._fall_start_y        = -INF
	p._invincibility_timer = 0.0
	p._soul_shield_timer   = 0.0
	p._upgrade_soft_landing = false
	return p

# ─── Tier thresholds (defaults: 1.5 / 2.5 / 4 × MAX_JUMP_HEIGHT=200 px) ────

func test_fall_under_300_takes_no_damage() -> void:
	var p := _make_test_player()
	p._apply_fall_damage_for(250.0)
	assert_eq(p.current_hp, 3, "fall of 250 px (< 300) must not damage")

func test_fall_300_to_500_takes_one_hp() -> void:
	var p := _make_test_player()
	p._apply_fall_damage_for(400.0)
	assert_eq(p.current_hp, 2, "fall of 400 px (300-500 tier) must apply -1 HP")

func test_fall_500_to_800_takes_two_hp() -> void:
	var p := _make_test_player()
	p._apply_fall_damage_for(700.0)
	assert_eq(p.current_hp, 1, "fall of 700 px (500-800 tier) must apply -2 HP")

func test_fall_over_800_kills_player() -> void:
	var p := _make_test_player()
	p._apply_fall_damage_for(1000.0)
	assert_lt(p.current_hp, 1, "fall of 1000 px (> 800) must kill (instant tier)")

func test_fall_at_exact_threshold_falls_into_lower_tier() -> void:
	# Tier table uses strict ">" so exactly 300 px stays in the no-damage band.
	# Locks the boundary contract — change carefully if rebalancing.
	var p := _make_test_player()
	p._apply_fall_damage_for(300.0)
	assert_eq(p.current_hp, 3, "fall of exactly 300 px stays in no-damage band")

# ─── Soft Landing upgrade scales every threshold by 1.5× ────────────────────

func test_soft_landing_raises_no_damage_band() -> void:
	# 400 px would normally cost 1 HP; with soft_landing the tier-1 threshold
	# becomes 300 × 1.5 = 450 px → 400 is now "safe".
	var p := _make_test_player()
	p._upgrade_soft_landing = true
	p._apply_fall_damage_for(400.0)
	assert_eq(p.current_hp, 3, "soft_landing: 400 px stays under raised 450 threshold")

func test_soft_landing_still_damages_above_scaled_threshold() -> void:
	# 500 px is above 450 but below 750 (500 × 1.5) → tier 1 → -1 HP.
	var p := _make_test_player()
	p._upgrade_soft_landing = true
	p._apply_fall_damage_for(500.0)
	assert_eq(p.current_hp, 2, "soft_landing: 500 px hits scaled tier 1 (-1 HP)")

# ─── _update_fall_tracking — high-water-mark logic ───────────────────────────

func test_jump_then_fall_tracks_apex_as_start() -> void:
	# Rising frames push _fall_start_y up (toward smaller Y). Landing measures
	# from the apex, not from the original floor — so a jump that returns to
	# the same Y reads as 0 fallen, not 200.
	var p := _make_test_player()
	# Frame 1: on floor at y=100 → baseline.
	p._update_fall_tracking(true, 100.0)
	assert_eq(p._fall_start_y, 100.0)
	# Frame 2: rising to y=80 (higher on screen).
	p._update_fall_tracking(false, 80.0)
	assert_eq(p._fall_start_y, 80.0, "rising must lower _fall_start_y to apex")
	# Frame 3: at apex y=60.
	p._update_fall_tracking(false, 60.0)
	assert_eq(p._fall_start_y, 60.0)
	# Frame 4: falling back, must NOT raise the high-water mark.
	p._update_fall_tracking(false, 80.0)
	assert_eq(p._fall_start_y, 60.0, "falling must keep apex as start")
	# Frame 5: lands back at original y=100. Fallen = 100 - 60 = 40 < 300 → no damage.
	p._update_fall_tracking(true, 100.0)
	assert_eq(p.current_hp, 3, "jump arc returning to start floor: no damage")

# ─── Walk-off-ledge regression (the bug fixed in 72835063) ──────────────────

func test_walk_off_ledge_applies_fall_damage_without_prior_jump() -> void:
	# Old _check_fall_damage only set _fall_start_y while velocity.y < 0
	# (rising). Walk-off → velocity.y > 0 from frame 1 → _fall_start_y stayed
	# at 0 → no damage. _update_fall_tracking now baselines on every floor
	# frame so the next walk-off measures from the right Y.
	var p := _make_test_player()
	# Stand on ledge at y=0
	p._update_fall_tracking(true, 0.0)
	# Walk off — first off-floor frame at y=10
	p._update_fall_tracking(false, 10.0)
	# Continue falling — _fall_start_y must STAY at 0 (smallest seen)
	p._update_fall_tracking(false, 200.0)
	# Land at y=400 → fallen = 400 - 0 = 400 → tier 1 (-1 HP)
	p._update_fall_tracking(true, 400.0)
	assert_eq(p.current_hp, 2,
		"walk-off-ledge of 400 px must apply -1 HP even without a prior jump")

func test_walk_off_ledge_short_fall_still_safe() -> void:
	# Symmetric sanity: walking off into a short drop still respects the
	# < 300 px no-damage band.
	var p := _make_test_player()
	p._update_fall_tracking(true, 0.0)
	p._update_fall_tracking(false, 50.0)
	p._update_fall_tracking(false, 200.0)
	p._update_fall_tracking(true, 250.0)
	assert_eq(p.current_hp, 3,
		"walk-off-ledge of 250 px must remain in the no-damage band")

func test_first_landing_after_spawn_does_not_damage() -> void:
	# Spawn sentinel: _fall_start_y starts at -INF so the very first floor
	# frame just baselines without applying phantom damage.
	var p := _make_test_player()
	p._fall_start_y = -INF  # explicit (already default)
	p._update_fall_tracking(true, 1000.0)  # spawned high up
	assert_eq(p.current_hp, 3, "first floor frame after spawn must not damage")
	assert_eq(p._fall_start_y, 1000.0, "and must baseline _fall_start_y")
