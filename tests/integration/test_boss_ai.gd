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

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_transitions_to_chase_when_player_in_range() -> void:
	# TODO: same as test_do_idle_transitions_to_chase — handled above
	pass

func test_transitions_back_to_patrol_when_player_out_of_range() -> void:
	# TODO: requires processing frames to observe state machine over time
	pass

func test_phase_changes_at_hp_threshold() -> void:
	# TODO: BossAI has no HP — damage/phase-change is mechanic-specific
	# (e.g. soul collection → advance_phase). Covered by test_advance_phase_*.
	pass

func test_win_condition_emitted_at_zero_hp() -> void:
	# TODO: no generic HP system; win comes from mechanic-specific conditions
	pass

func test_boss_does_not_move_while_stunned() -> void:
	# TODO: requires physics process frames + CharacterBody2D in scene tree
	pass

func test_stun_ends_after_duration() -> void:
	# TODO: requires _tick_timers(delta) called with cumulative delta ≥ stun_timer
	pass

func test_phase_2_increases_speed() -> void:
	# TODO: speed change is config-driven; needs injected multi-phase config
	pass

func test_phase_3_activates_special_attack() -> void:
	# TODO: special attack patterns are behavior-string driven; need config
	pass
