extends GutTest

# Integration tests for BossAI.gd (CharacterBody2D).
#
# BossAI._ready() loads bosses_config.json and calls _find_player() via
# get_tree() — so add_child_autofree on a bare node would crash.
# All tests use autofree() which skips _ready() entirely.
# @onready vars (_anim, _sprite) stay null but all code paths we test either
# guard them (if not _anim: return) or don't reach them.
#
# State/signal/logic tests inject _phase_cfg, _mechanic, _player directly.

const BossAIScript := preload("res://scripts/enemies/BossAI.gd")

# ── Initial state ─────────────────────────────────────────────────────────────

func test_initial_state_is_idle() -> void:
	var boss: Node = autofree(BossAIScript.new())
	assert_eq(boss.state, boss.BossState.IDLE)

func test_initial_boss_defeated_flag_false() -> void:
	# _boss_defeated is a BossLevel concept; BossAI just tracks _prayer_progress
	var boss: Node = autofree(BossAIScript.new())
	assert_almost_eq(boss._prayer_progress, 0.0, 0.001)

func test_initial_current_phase_zero() -> void:
	var boss: Node = autofree(BossAIScript.new())
	assert_eq(boss._current_phase, 0)

# ── receive_knockback / stun ──────────────────────────────────────────────────

func test_receive_knockback_sets_stunned_state() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.RIGHT * 100.0, 2.0)
	assert_eq(boss.state, boss.BossState.STUNNED)

func test_receive_knockback_sets_stun_timer() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.ZERO, 3.5)
	assert_almost_eq(boss._stun_timer, 3.5, 0.001)

func test_receive_knockback_ignored_when_already_stunned() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.ZERO, 6.0)   # first stun
	boss._stun_timer = 6.0                       # reset to full manually
	boss.receive_knockback(Vector2.ZERO, 2.0)   # second call should no-op
	assert_almost_eq(boss._stun_timer, 6.0, 0.001)  # unchanged

func test_boss_stunned_signal_emitted_on_knockback() -> void:
	var boss: Node = autofree(BossAIScript.new())
	watch_signals(boss)
	boss.receive_knockback(Vector2.ZERO, 2.0)
	assert_signal_emitted(boss, "boss_stunned")

# ── Prayer ritual ─────────────────────────────────────────────────────────────

func test_reset_prayer_clears_progress() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._prayer_progress = 5.0
	boss.reset_prayer()
	assert_almost_eq(boss._prayer_progress, 0.0, 0.001)

func test_tick_prayer_accumulates_with_prayer_phase_config() -> void:
	var boss: Node = autofree(BossAIScript.new())
	# Inject a phase that has prayer_ritual mechanic
	boss._phase_cfg = [
		{"behavior": "chase",
		 "mechanic": {"type": "prayer_ritual", "hold_duration": 8.0}}
	]
	boss.tick_prayer(1.5)
	assert_almost_eq(boss._prayer_progress, 1.5, 0.001)

func test_tick_prayer_no_accumulate_without_prayer_phase() -> void:
	# Default empty _phase_cfg → tick_prayer returns early
	var boss: Node = autofree(BossAIScript.new())
	boss.tick_prayer(1.0)
	assert_almost_eq(boss._prayer_progress, 0.0, 0.001)

func test_tick_prayer_emits_win_at_threshold() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [
		{"behavior": "chase",
		 "mechanic": {"type": "prayer_ritual", "hold_duration": 2.0}}
	]
	watch_signals(boss)
	boss.tick_prayer(2.5)  # exceeds hold_duration
	assert_signal_emitted(boss, "win_condition_met")

# ── Collectibles & win condition ──────────────────────────────────────────────

func test_on_collectible_picked_increments_counter() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.on_collectible_picked()
	assert_eq(boss._collectibles_collected, 1)

func test_win_condition_collect_and_escape_emits_signal() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic         = {"type": "collect_and_escape"}
	boss._collectibles_total = 1
	watch_signals(boss)
	boss.on_collectible_picked()
	assert_signal_emitted(boss, "win_condition_met")

func test_win_condition_not_emitted_before_all_collected() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic           = {"type": "collect_and_escape"}
	boss._collectibles_total = 3
	watch_signals(boss)
	boss.on_collectible_picked()   # only 1 of 3
	assert_signal_not_emitted(boss, "win_condition_met")

# ── Totem sequence ────────────────────────────────────────────────────────────

func test_on_totem_activated_in_sequence_increments_count() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "activate_in_sequence",
					  "totems": {"count": 3}}
	boss.on_totem_activated(0)
	assert_eq(boss._totems_activated, 1)

func test_on_totem_activated_wrong_order_ignored() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "activate_in_sequence",
					  "totems": {"count": 3}}
	boss.on_totem_activated(1)   # wrong: expected 0 first
	assert_eq(boss._totems_activated, 0)

func test_totem_sequence_win_when_all_activated() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "activate_in_sequence",
					  "totems": {"count": 2}}
	watch_signals(boss)
	boss.on_totem_activated(0)
	boss.on_totem_activated(1)
	assert_signal_emitted(boss, "win_condition_met")

# ── Phase config ──────────────────────────────────────────────────────────────

func test_get_current_phase_data_empty_with_no_phases() -> void:
	var boss: Node = autofree(BossAIScript.new())
	assert_true(boss._get_current_phase_data().is_empty())

func test_get_current_phase_data_returns_correct_entry() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [
		{"behavior": "chase"},
		{"behavior": "slow_patrol"},
	]
	boss._current_phase = 1
	assert_eq(boss._get_current_phase_data().get("behavior"), "slow_patrol")

func test_advance_phase_increments_current_phase() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{"behavior": "chase"}, {"behavior": "slow_patrol"}]
	boss.advance_phase()
	assert_eq(boss._current_phase, 1)

func test_advance_phase_emits_phase_changed_signal() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{"behavior": "chase"}, {"behavior": "slow_patrol"}]
	watch_signals(boss)
	boss.advance_phase()
	assert_signal_emitted(boss, "phase_changed")

# ── Copy setup ────────────────────────────────────────────────────────────────

func test_setup_as_copy_clears_real_boss_flag() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.setup_as_copy(null)
	assert_false(boss._is_real_boss)

# ── Idle → Chase transition ───────────────────────────────────────────────────

func test_do_idle_transitions_to_chase_when_player_in_range() -> void:
	var boss: Node = autofree(BossAIScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	# Both at Vector2.ZERO by default → distance = 0 < detection_range (300)
	boss._player = player
	boss._do_idle()
	assert_eq(boss.state, boss.BossState.CHASE)

func test_do_idle_stays_idle_when_player_out_of_range() -> void:
	var boss: Node = autofree(BossAIScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	player.position = Vector2(5000.0, 0.0)  # far beyond detection_range (300)
	boss._player = player
	boss._do_idle()
	assert_eq(boss.state, boss.BossState.IDLE)

# ── Sin aura ──────────────────────────────────────────────────────────────────

func test_tick_sin_aura_emits_signal_when_player_close() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{"sin_aura": {"radius": 500, "sin_per_second": 3}}]
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	boss._player = player  # same position → within 500 radius
	watch_signals(boss)
	boss._tick_sin_aura(1.0)   # fills timer to 1.0 → emit
	assert_signal_emitted(boss, "sin_aura_tick")

func test_tick_sin_aura_no_signal_when_player_far() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{"sin_aura": {"radius": 100, "sin_per_second": 3}}]
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	player.position = Vector2(5000.0, 0.0)
	boss._player = player
	watch_signals(boss)
	boss._tick_sin_aura(1.0)
	assert_signal_not_emitted(boss, "sin_aura_tick")

func test_tick_sin_aura_no_signal_before_one_second() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{"sin_aura": {"radius": 500, "sin_per_second": 3}}]
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	boss._player = player
	watch_signals(boss)
	boss._tick_sin_aura(0.4)   # timer < 1.0 → no emit yet
	assert_signal_not_emitted(boss, "sin_aura_tick")

# ── _tick_timers — stun expiry ────────────────────────────────────────────────

func test_stun_ends_after_duration() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.ZERO, 2.0)
	boss._tick_timers(2.1)   # delta > stun_timer → _on_stun_ended()
	assert_eq(boss.state, boss.BossState.CHASE)

func test_stun_end_emits_boss_stun_ended_signal() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.ZERO, 1.0)
	watch_signals(boss)
	boss._tick_timers(1.1)
	assert_signal_emitted(boss, "boss_stun_ended")

func test_stun_timer_not_expired_before_duration() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.receive_knockback(Vector2.ZERO, 3.0)
	boss._tick_timers(1.0)   # partial delta — still stunned
	assert_eq(boss.state, boss.BossState.STUNNED)

# ── _do_stunned ────────────────────────────────────────────────────────────────

func test_do_stunned_decelerates_velocity() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.velocity.x = 500.0
	boss._do_stunned(0.016)
	assert_lt(boss.velocity.x, 500.0)

# ── Charge telegraph & charging ───────────────────────────────────────────────

func test_begin_charge_telegraph_sets_state() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"charge_cycle": {"telegraph_duration": 1.2}}
	boss._player   = autofree(CharacterBody2D.new())
	boss._begin_charge_telegraph()
	assert_eq(boss.state, boss.BossState.CHARGE_TELEGRAPH)

func test_begin_charge_telegraph_sets_timer() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"charge_cycle": {"telegraph_duration": 1.5}}
	boss._player   = autofree(CharacterBody2D.new())
	boss._begin_charge_telegraph()
	assert_almost_eq(boss._charge_telegraph, 1.5, 0.001)

func test_charge_starts_after_telegraph_expires() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"charge_cycle": {"telegraph_duration": 0.1,
	                                   "charge_duration": 0.8,
	                                   "charge_speed": 450},
	                  "type": "dodge_and_collect"}
	boss._stats = {"charge_speed": 450}
	boss._player = autofree(CharacterBody2D.new())
	boss._begin_charge_telegraph()
	boss._tick_timers(0.2)   # telegraph expires → _start_charge()
	assert_eq(boss.state, boss.BossState.CHARGING)

func test_charging_transitions_to_chase_when_timer_expires() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"charge_cycle": {"cooldown_after_charge": 2.5}}
	boss.state          = boss.BossState.CHARGING
	boss._charge_timer  = 0.001
	boss._do_charging(0.002)
	assert_eq(boss.state, boss.BossState.CHASE)

func test_charging_sets_cooldown_after_timer_expires() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"charge_cycle": {"cooldown_after_charge": 2.5}}
	boss.state         = boss.BossState.CHARGING
	boss._charge_timer = 0.001
	boss._do_charging(0.002)
	assert_almost_eq(boss._charge_cooldown, 2.5, 0.001)

# ── Win condition — all mechanic types ────────────────────────────────────────

func test_win_condition_dodge_and_collect() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic           = {"type": "dodge_and_collect"}
	boss._collectibles_total = 1
	watch_signals(boss)
	boss.on_collectible_picked()
	assert_signal_emitted(boss, "win_condition_met")

func test_win_condition_lure_into_trap() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic           = {"type": "lure_into_trap"}
	boss._collectibles_total = 2
	boss.on_collectible_picked()
	watch_signals(boss)
	boss.on_collectible_picked()
	assert_signal_emitted(boss, "win_condition_met")

func test_win_condition_identify_and_evade_no_emit_on_collectible() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "identify_and_evade"}
	watch_signals(boss)
	boss.on_collectible_picked()
	assert_signal_not_emitted(boss, "win_condition_met")

# ── on_player_reached_exit ────────────────────────────────────────────────────

func test_on_player_reached_exit_win_when_collected_all() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic           = {"type": "collect_and_escape"}
	boss._collectibles_total = 1
	boss._collectibles_collected = 1
	watch_signals(boss)
	boss.on_player_reached_exit()
	assert_signal_emitted(boss, "win_condition_met")

func test_on_player_reached_exit_no_win_when_not_collected_all() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic           = {"type": "collect_and_escape"}
	boss._collectibles_total = 3
	boss._collectibles_collected = 1
	watch_signals(boss)
	boss.on_player_reached_exit()
	assert_signal_not_emitted(boss, "win_condition_met")

func test_on_player_reached_exit_win_when_stunned_identify_evade() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "identify_and_evade"}
	boss.state     = boss.BossState.STUNNED
	watch_signals(boss)
	boss.on_player_reached_exit()
	assert_signal_emitted(boss, "win_condition_met")

func test_on_player_reached_exit_no_win_when_chasing_identify_evade() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "identify_and_evade"}
	boss.state     = boss.BossState.CHASE
	watch_signals(boss)
	boss.on_player_reached_exit()
	assert_signal_not_emitted(boss, "win_condition_met")

# ── is_blocking_totem ─────────────────────────────────────────────────────────

func test_is_blocking_totem_true_when_close() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic  = {"totems": {"blocked_when_boss_within": 120}}
	boss.position   = Vector2.ZERO
	assert_true(boss.is_blocking_totem(Vector2(100.0, 0.0)))

func test_is_blocking_totem_false_when_far() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"totems": {"blocked_when_boss_within": 120}}
	boss.position  = Vector2.ZERO
	assert_false(boss.is_blocking_totem(Vector2(200.0, 0.0)))

# ── register_arena_objects ────────────────────────────────────────────────────

func test_register_arena_objects_sets_total() -> void:
	var boss: Node = autofree(BossAIScript.new())
	var obj1: Node = autofree(Node.new())
	var obj2: Node = autofree(Node.new())
	boss.register_arena_objects([obj1, obj2])
	assert_eq(boss._collectibles_total, 2)

func test_register_arena_objects_replaces_previous() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.register_arena_objects([autofree(Node.new()), autofree(Node.new())])
	boss.register_arena_objects([autofree(Node.new())])
	assert_eq(boss._collectibles_total, 1)

# ── boss_10 phase advance at 3 collectibles ───────────────────────────────────

func test_boss10_advances_phase_at_three_collectibles() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.boss_id              = "boss_10"
	boss._mechanic            = {"type": "collect_and_escape"}
	boss._collectibles_total  = 10
	boss._phase_cfg = [{"behavior": "chase"}, {"behavior": "slow_patrol"}]
	boss.on_collectible_picked()
	boss.on_collectible_picked()
	boss.on_collectible_picked()   # third → advance_phase
	assert_eq(boss._current_phase, 1)

func test_non_boss10_does_not_advance_at_three() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.boss_id             = "boss_05"
	boss._mechanic           = {"type": "dodge_and_collect"}
	boss._collectibles_total = 10
	boss._phase_cfg = [{"behavior": "chase"}, {"behavior": "slow_patrol"}]
	boss.on_collectible_picked()
	boss.on_collectible_picked()
	boss.on_collectible_picked()
	assert_eq(boss._current_phase, 0)  # no auto-advance for other bosses

# ── _get_anim_name ────────────────────────────────────────────────────────────

func test_get_anim_name_idle() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.IDLE
	assert_eq(boss._get_anim_name(), "boss_idle")

func test_get_anim_name_chase() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.CHASE
	assert_eq(boss._get_anim_name(), "boss_walk")

func test_get_anim_name_stunned() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.STUNNED
	assert_eq(boss._get_anim_name(), "boss_stun")

func test_get_anim_name_charging() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.CHARGING
	assert_eq(boss._get_anim_name(), "boss_charge")

func test_get_anim_name_charge_telegraph() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.CHARGE_TELEGRAPH
	assert_eq(boss._get_anim_name(), "boss_charge_telegraph")

func test_get_anim_name_phase_transition() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.state = boss.BossState.PHASE_TRANSITION
	assert_eq(boss._get_anim_name(), "boss_idle")

# ── _do_wind_gust ─────────────────────────────────────────────────────────────

func test_do_wind_gust_applies_force_to_player() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"wind_hazard": {"push_force": 200, "gusts_interval": 4.0}}
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	player.position = Vector2(300.0, 0.0)
	boss._player    = player
	boss._do_wind_gust()
	assert_ne(player.velocity, Vector2.ZERO)

func test_do_wind_gust_no_crash_without_player() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"wind_hazard": {"push_force": 200, "gusts_interval": 4.0}}
	boss._player   = null
	boss._do_wind_gust()
	assert_true(true)

# ── _destroy_copies ───────────────────────────────────────────────────────────

func test_destroy_copies_clears_array() -> void:
	var boss: Node = autofree(BossAIScript.new())
	var copy1 := Node2D.new()
	var copy2 := Node2D.new()
	add_child_autofree(copy1)
	add_child_autofree(copy2)
	boss._copies = [copy1, copy2]
	boss._destroy_copies()
	assert_eq(boss._copies.size(), 0)

# ── TODO (requires physics or scene tree) ─────────────────────────────────────

func test_transitions_back_to_patrol_when_player_out_of_range() -> void:
	# TODO: requires processing frames to observe state machine over time
	pending("not yet implemented")

func test_phase_2_increases_speed() -> void:
	# TODO: move_speed is set once from stats, not per-phase — no current mechanism
	pending("not yet implemented")

func test_phase_3_activates_special_attack() -> void:
	# TODO: special attacks are behavior-string driven; need config + scene
	pending("not yet implemented")

# ── Progress bar (#40) ────────────────────────────────────────────────────────

func test_progress_signal_emitted_on_collectible_pickup() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._collectibles_total = 3
	watch_signals(boss)
	boss.on_collectible_picked()
	assert_signal_emitted(boss, "progress_updated")

func test_progress_signal_value_matches_count() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._collectibles_total = 5
	watch_signals(boss)
	boss.on_collectible_picked()
	boss.on_collectible_picked()
	# Latest emit should carry value=2, max=5.
	var p: Array = get_signal_parameters(boss, "progress_updated")
	assert_eq(p[1], 2.0, "value should be the new collectible count")
	assert_eq(p[2], 5.0, "max should be the configured total")

func test_progress_signal_emitted_on_totem_activation_in_order() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "activate_in_sequence", "totems": {"count": 3}}
	boss._next_totem_index = 0
	watch_signals(boss)
	boss.on_totem_activated(0)
	assert_signal_emitted(boss, "progress_updated")
	var p: Array = get_signal_parameters(boss, "progress_updated")
	assert_eq(p[0], "Тотеми")
	assert_eq(p[1], 1.0)
	assert_eq(p[2], 3.0)

func test_progress_signal_skipped_on_wrong_totem_order() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._mechanic = {"type": "activate_in_sequence", "totems": {"count": 3}}
	boss._next_totem_index = 0
	watch_signals(boss)
	boss.on_totem_activated(2)   # wrong — expecting 0
	assert_signal_emit_count(boss, "progress_updated", 0)

func test_progress_signal_during_prayer_tick() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{
		"behavior": "stationary_final",
		"mechanic": {"type": "prayer_ritual", "hold_duration": 8.0},
	}]
	boss._current_phase = 0
	watch_signals(boss)
	boss.tick_prayer(2.5)
	assert_signal_emitted(boss, "progress_updated")
	var p: Array = get_signal_parameters(boss, "progress_updated")
	assert_eq(p[0], "Молитва")
	assert_almost_eq(p[1], 2.5, 0.01)
	assert_eq(p[2], 8.0)

func test_reset_prayer_emits_zeroed_progress_when_in_prayer_phase() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss._phase_cfg = [{
		"behavior": "stationary_final",
		"mechanic": {"type": "prayer_ritual", "hold_duration": 8.0},
	}]
	boss._current_phase = 0
	boss._prayer_progress = 4.0
	watch_signals(boss)
	boss.reset_prayer()
	# UI must see the meter snap back to 0 so it doesn't appear stuck.
	assert_signal_emitted(boss, "progress_updated")
	var p: Array = get_signal_parameters(boss, "progress_updated")
	assert_eq(p[1], 0.0)
	assert_eq(p[2], 8.0)

func test_collectible_label_per_boss() -> void:
	var boss: Node = autofree(BossAIScript.new())
	boss.boss_id = "boss_10"
	assert_eq(boss._collectible_label(), "Душі")
	boss.boss_id = "boss_03"
	assert_eq(boss._collectible_label(), "Кристали")
	boss.boss_id = "boss_99"   # unknown → fallback
	assert_eq(boss._collectible_label(), "Зібрано")
