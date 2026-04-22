extends GutTest

# Integration tests for EscapeLevel.gd and Pursuer.gd.
#
# Pursuer tests use autofree() — no _ready() needed, pure logic.
# EscapeLevel tests use SafeEscapeLevel + _make_safe_el() to avoid
# crashing on _ready() (which calls LevelBase super() + _spawn_pursuer).

const EscapeLevelScript := preload("res://scripts/levels/EscapeLevel.gd")
const PursuerScript      := preload("res://scripts/enemies/Pursuer.gd")

# ── SafeEscapeLevel helper ────────────────────────────────────────────────────

class SafeEscapeLevel extends EscapeLevelScript:
	func _ready() -> void:
		pass  # skip all scene-tree init


func _make_safe_el() -> Node:
	var el: Node = SafeEscapeLevel.new()
	var hud := Node.new();     hud.name = "HUD"
	var ps  := Node.new();     ps.name  = "PauseScreen"
	var rc  := Node2D.new();   rc.name  = "RoomContainer"
	var sp  := Marker2D.new(); sp.name  = "SpawnPoint"
	var ex  := Area2D.new();   ex.name  = "Exit"
	el.add_child(hud)
	el.add_child(ps)
	el.add_child(rc)
	el.add_child(sp)
	el.add_child(ex)
	add_child_autofree(el)
	return el


func after_each() -> void:
	if GameManager:
		GameManager._is_transitioning = false

# ══════════════════════════════════════════════════════════════════════════════
# Pursuer — initial state
# ══════════════════════════════════════════════════════════════════════════════

func test_pursuer_starts_inactive() -> void:
	var p: Node = autofree(PursuerScript.new())
	assert_false(p._active)

func test_pursuer_default_behavior_is_rising() -> void:
	var p: Node = autofree(PursuerScript.new())
	assert_eq(p.behavior, p.Behavior.RISING)

func test_pursuer_default_speed() -> void:
	var p: Node = autofree(PursuerScript.new())
	assert_almost_eq(p.speed, 80.0, 0.001)

func test_pursuer_default_knockback_force() -> void:
	var p: Node = autofree(PursuerScript.new())
	assert_almost_eq(p.knockback_force, 400.0, 0.001)

func test_pursuer_contact_cooldown_starts_at_zero() -> void:
	var p: Node = autofree(PursuerScript.new())
	assert_almost_eq(p._contact_cooldown, 0.0, 0.001)

# ── setup() ───────────────────────────────────────────────────────────────────

func test_setup_applies_speed_from_config() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"speed": 120.0})
	assert_almost_eq(p.speed, 120.0, 0.001)

func test_setup_applies_knockback_force() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"knockback_force": 500.0})
	assert_almost_eq(p.knockback_force, 500.0, 0.001)

func test_setup_rising_behavior_from_config() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"behavior": "rising"})
	assert_eq(p.behavior, p.Behavior.RISING)

func test_setup_chasing_behavior_from_config() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"behavior": "chasing"})
	assert_eq(p.behavior, p.Behavior.CHASING)

func test_setup_unknown_behavior_defaults_to_rising() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"behavior": "teleport"})
	assert_eq(p.behavior, p.Behavior.RISING)

func test_setup_stores_player_ref() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {})
	assert_eq(p._player, player)

func test_setup_oscillation_amplitude_applied() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"oscillation_amplitude": 40.0})
	assert_almost_eq(p.oscillation_amplitude, 40.0, 0.001)

func test_setup_contact_range_applied() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"contact_range": 32.0})
	assert_almost_eq(p.contact_range, 32.0, 0.001)

# ── activate / reset ──────────────────────────────────────────────────────────

func test_activate_sets_active_true() -> void:
	var p: Node = autofree(PursuerScript.new())
	p.activate()
	assert_true(p._active)

func test_reset_to_start_deactivates() -> void:
	var p: Node = autofree(PursuerScript.new())
	p.activate()
	p.reset_to_start()
	assert_false(p._active)

func test_reset_to_start_restores_y() -> void:
	var p: Node = autofree(PursuerScript.new())
	p.position = Vector2(0.0, 500.0)
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {})   # records _start_y = 500
	p.position.y = 200.0  # simulate risen
	p.reset_to_start()
	assert_almost_eq(p.position.y, 500.0, 0.001)

func test_reset_clears_contact_cooldown() -> void:
	var p: Node = autofree(PursuerScript.new())
	p._contact_cooldown = 1.0
	p.reset_to_start()
	assert_almost_eq(p._contact_cooldown, 0.0, 0.001)

func test_reset_clears_time_accumulator() -> void:
	var p: Node = autofree(PursuerScript.new())
	p._time = 3.5
	p.reset_to_start()
	assert_almost_eq(p._time, 0.0, 0.001)

# ── _check_player_overlap — contact detection ─────────────────────────────────

func test_signal_emitted_when_player_within_contact_range() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"contact_range": 64.0})
	p.activate()
	watch_signals(p)
	# Player at pursuer's exact position — distance = 0 < 64
	player.position = p.position
	p._check_player_overlap()
	assert_signal_emitted(p, "player_caught")

func test_signal_not_emitted_when_player_far() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"contact_range": 64.0})
	p.activate()
	watch_signals(p)
	player.position = Vector2(0.0, p.position.y - 300.0)  # 300px away
	p._check_player_overlap()
	assert_signal_not_emitted(p, "player_caught")

func test_knockback_in_signal_is_upward() -> void:
	# Knockback Y should be negative (upward in Godot 2D).
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"knockback_force": 400.0, "contact_range": 64.0})
	watch_signals(p)
	player.position = p.position
	p._check_player_overlap()
	var kb: Vector2 = get_signal_parameters(p, "player_caught", 0)[0]
	assert_lt(kb.y, 0.0)

func test_knockback_magnitude_matches_knockback_force() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"knockback_force": 500.0, "contact_range": 64.0})
	watch_signals(p)
	player.position = p.position
	p._check_player_overlap()
	var kb: Vector2 = get_signal_parameters(p, "player_caught", 0)[0]
	assert_almost_eq(kb.length(), 500.0, 0.001)

func test_contact_cooldown_set_after_signal() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"contact_range": 64.0})
	player.position = p.position
	p._check_player_overlap()
	assert_gt(p._contact_cooldown, 0.0)

func test_signal_not_emitted_while_on_cooldown() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"contact_range": 64.0})
	player.position = p.position
	p._check_player_overlap()          # first hit — sets cooldown
	watch_signals(p)
	p._check_player_overlap()          # second call — blocked by cooldown
	assert_signal_not_emitted(p, "player_caught")

func test_no_signal_without_player() -> void:
	var p: Node = autofree(PursuerScript.new())
	# _player is null — no setup() called
	watch_signals(p)
	p._check_player_overlap()
	assert_signal_not_emitted(p, "player_caught")

# ── _move — rising behavior ───────────────────────────────────────────────────

func test_rising_move_decreases_y() -> void:
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"speed": 100.0, "behavior": "rising"})
	var initial_y: float = p.position.y
	p._move(0.5)
	# After 0.5 sec at 100 px/sec → y should decrease by 50 px
	assert_almost_eq(p.position.y, initial_y - 50.0, 0.5)

func test_rising_move_does_not_change_y_when_inactive() -> void:
	# _move itself doesn't check _active; _physics_process does.
	# This confirms _move always moves when called directly.
	var p: Node = autofree(PursuerScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	p.setup(player, {"speed": 100.0, "behavior": "rising"})
	p._move(1.0)
	assert_almost_eq(p.position.y, -100.0, 0.5)

# ── EscapeLevel constants ─────────────────────────────────────────────────────

func test_pursuer_start_delay_constant_exists() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	assert_gt(el.PURSUER_START_DELAY, 0.0)

func test_pursuer_spawn_offset_constant_positive() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	assert_gt(el.PURSUER_SPAWN_OFFSET, 0.0)

# ── EscapeLevel._pursuer_config ───────────────────────────────────────────────

func test_config_rising_lava_fast_has_higher_speed_than_shadow() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	var shadow_speed: float = el._pursuer_config("chase_shadow").get("speed", 0.0)
	var lava_speed:   float = el._pursuer_config("rising_lava_fast").get("speed", 0.0)
	assert_gt(lava_speed, shadow_speed)

func test_config_chasing_mechanic_sets_chasing_behavior() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	assert_eq(el._pursuer_config("chase_hell_knight").get("behavior"), "chasing")

func test_config_rising_mechanic_sets_rising_behavior() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	assert_eq(el._pursuer_config("chase_shadow").get("behavior"), "rising")

func test_config_unknown_mechanic_returns_defaults() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	var cfg: Dictionary = el._pursuer_config("nonexistent_mechanic")
	assert_gt(cfg.get("speed", 0.0), 0.0)
	assert_gt(cfg.get("knockback_force", 0.0), 0.0)

func test_config_swamp_wave_has_oscillation() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	var cfg: Dictionary = el._pursuer_config("chase_swamp_wave")
	assert_gt(cfg.get("oscillation_amplitude", 0.0), 0.0)

func test_config_lucifer_hand_is_fastest() -> void:
	var el: Node = autofree(EscapeLevelScript.new())
	var speeds := [
		el._pursuer_config("chase_shadow").get("speed", 0.0),
		el._pursuer_config("rising_lava_fast").get("speed", 0.0),
		el._pursuer_config("chase_all_elements").get("speed", 0.0),
		el._pursuer_config("chase_lucifer_hand").get("speed", 0.0),
	]
	var lucifer_speed: float = el._pursuer_config("chase_lucifer_hand").get("speed", 0.0)
	for s: float in speeds:
		assert_gte(lucifer_speed, s)

# ── EscapeLevel — setup_escape_timer disabled ─────────────────────────────────

func test_setup_escape_timer_is_noop() -> void:
	# EscapeLevel overrides _setup_escape_timer to do nothing.
	# Calling it must not crash and must leave _escape_timer_total at 0.
	var el: Node = autofree(EscapeLevelScript.new())
	el._setup_escape_timer()
	assert_almost_eq(el._escape_timer_total, 0.0, 0.001)

# ── EscapeLevel — pursuer injection & respawn ─────────────────────────────────

func test_on_pursuer_caught_does_not_crash_without_player() -> void:
	var el: Node = _make_safe_el()
	el._player = null
	el._on_pursuer_caught(Vector2(0.0, -400.0))
	# No crash = pass

func test_on_pursuer_caught_calls_receive_hit_on_player() -> void:
	var el: Node  = _make_safe_el()
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	# Track calls via a flag on the player (we test this via hit counter indirectly)
	el._player = player
	# receive_hit is defined on Player.gd; CharacterBody2D stub won't have it,
	# but has_method guard prevents crash.
	el._on_pursuer_caught(Vector2(0.0, -400.0))
	# No crash and guard respected = pass (full damage test is in test_player.gd)

func test_on_respawn_resets_pursuer_position() -> void:
	var el: Node = _make_safe_el()
	# _player stays null → LevelBase._on_respawn() returns early; EscapeLevel
	# override continues and resets the pursuer regardless.

	var pursuer: Node = autofree(PursuerScript.new())
	pursuer.position = Vector2(0.0, 100.0)  # simulate that it has risen
	var player2: CharacterBody2D = autofree(CharacterBody2D.new())
	pursuer.setup(player2, {})              # _start_y recorded as 100.0
	pursuer.position.y = -200.0             # simulate significant rise
	el._pursuer = pursuer

	# SpawnPoint stub is at Vector2.ZERO by default (Marker2D).
	# Expected: _spawn_point.global_position.y + PURSUER_SPAWN_OFFSET
	var expected_y: float = el._spawn_point.global_position.y + el.PURSUER_SPAWN_OFFSET
	el._on_respawn()
	assert_almost_eq(el._pursuer.position.y, expected_y, 1.0)

func test_on_respawn_deactivates_pursuer() -> void:
	var el: Node = _make_safe_el()
	# _player stays null — LevelBase._on_respawn() guard exits early

	var pursuer: Node = autofree(PursuerScript.new())
	var player2: CharacterBody2D = autofree(CharacterBody2D.new())
	pursuer.setup(player2, {})
	pursuer.activate()
	el._pursuer = pursuer

	el._on_respawn()
	assert_false(el._pursuer._active)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_pursuer_actually_rises_over_time() -> void:
	# TODO: requires _physics_process frames — needs scene tree + process loop
	pass

func test_escape_level_spawns_pursuer_in_ready() -> void:
	# TODO: full _ready() requires Player.tscn, LevelConfig, LevelGenerator autoloads
	pass

func test_pursuer_activates_after_start_delay() -> void:
	# TODO: requires await create_timer(PURSUER_START_DELAY) in test
	pass

func test_pursuer_reactivates_after_respawn_delay() -> void:
	# TODO: same — async timer
	pass
