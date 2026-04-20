extends GutTest

# Integration tests for BossLevel.gd (extends LevelBase).
#
# BossLevel._ready() calls super() which spawns a player and connects scene
# nodes — cannot use add_child_autofree on a bare node.
#
# Strategies:
# 1. autofree() — for pure constants / flag logic that needs no scene tree.
# 2. SafeBossLevel — overrides _ready() to only build the notify layer
#    (so _notify_label exists), adds stub children before entering tree,
#    then add_child_autofree().  Used for anything that calls _flash_notify
#    or get_viewport() / get_tree().

const BossLevelScript := preload("res://scripts/levels/BossLevel.gd")

class SafeBossLevel extends BossLevelScript:
	func _ready() -> void:
		_build_notify_layer()  # creates _notify_label; skip super() game init


func _make_safe_bl() -> Node:
	var bl: Node = SafeBossLevel.new()
	# @onready fires before _ready() in Godot 4, so add stubs beforehand.
	var hud := Node.new();    hud.name = "HUD"
	var rc  := Node2D.new();  rc.name  = "RoomContainer"
	var sp  := Marker2D.new(); sp.name = "SpawnPoint"
	var ex  := Area2D.new();  ex.name  = "Exit"
	bl.add_child(hud)
	bl.add_child(rc)
	bl.add_child(sp)
	bl.add_child(ex)
	add_child_autofree(bl)
	return bl


func after_each() -> void:
	if GameManager:
		GameManager._is_transitioning = false

# ── Constants ─────────────────────────────────────────────────────────────────

func test_boss_names_has_10_entries() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	assert_eq(bl.BOSS_NAMES.size(), 10)

func test_phase_labels_has_3_entries() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	assert_eq(bl.PHASE_LABELS.size(), 3)

func test_phase_labels_first_entry_is_empty() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	assert_eq(bl.PHASE_LABELS[0], "")

func test_boss_defeated_false_by_default() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	assert_false(bl._boss_defeated)

# ── Exit override ─────────────────────────────────────────────────────────────

func test_exit_locked_when_boss_not_defeated() -> void:
	# Uses _make_safe_bl because the not-defeated path calls _flash_notify
	# → create_tween() which needs the scene tree.
	var bl: Node = _make_safe_bl()
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	bl._player        = player
	bl._boss_defeated = false
	bl._on_exit_body_entered(player)
	assert_false(bl._is_complete)

func test_exit_completes_when_boss_defeated() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	bl._player        = player
	bl._boss_defeated = true
	bl._on_exit_body_entered(player)
	assert_true(bl._is_complete)

func test_exit_ignored_when_already_complete() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	bl._player        = player
	bl._boss_defeated = true
	bl._is_complete   = true
	bl._on_exit_body_entered(player)
	assert_true(bl._is_complete)  # still true; _complete_level not called twice

func test_exit_ignored_for_non_player_body() -> void:
	var bl: Node = autofree(BossLevelScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	var other: CharacterBody2D  = autofree(CharacterBody2D.new())
	bl._player        = player
	bl._boss_defeated = true
	bl._on_exit_body_entered(other)
	assert_false(bl._is_complete)

# ── Notify layer ──────────────────────────────────────────────────────────────

func test_build_notify_layer_creates_label() -> void:
	var bl: Node = _make_safe_bl()
	assert_not_null(bl._notify_label)

func test_flash_notify_sets_label_text() -> void:
	var bl: Node = _make_safe_bl()
	bl._flash_notify("Тест повідомлення")
	assert_eq(bl._notify_label.text, "Тест повідомлення")

func test_on_boss_stunned_sets_notify_text() -> void:
	var bl: Node = _make_safe_bl()
	bl._on_boss_stunned(2.0)
	assert_eq(bl._notify_label.text, "ОГЛУШЕНО!")

# ── Phase tracking ────────────────────────────────────────────────────────────

func test_on_phase_changed_updates_current_phase() -> void:
	var bl: Node = _make_safe_bl()
	bl._on_phase_changed(1)
	assert_eq(bl._current_phase, 1)

func test_on_phase_changed_sets_notify_flash() -> void:
	var bl: Node = _make_safe_bl()
	bl._on_phase_changed(1)
	# PHASE_LABELS[1] = "— Друга форма —"
	assert_eq(bl._notify_label.text, bl.PHASE_LABELS[1])

func test_on_phase_changed_phase_zero_no_flash() -> void:
	var bl: Node = _make_safe_bl()
	bl._flash_notify("попереднє")   # set some prior text
	bl._on_phase_changed(0)
	# Phase 0 label is "" → no flash; label stays unchanged
	assert_eq(bl._notify_label.text, "попереднє")

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_intro_overlay_created_on_ready() -> void:
	# TODO: requires full _ready() init (LevelBase + boss wiring)
	pass

func test_intro_overlay_removed_after_hold_time() -> void:
	# TODO: requires tween time simulation (INTRO_HOLD_SECONDS ≈ 2.8 s)
	pass

func test_boss_win_sets_defeated_flag() -> void:
	# TODO: _on_boss_win() has `await create_timer(5.0)` — async, timer fires
	# after test ends and may reference freed objects
	pass

func test_boss_win_hides_phase_panel() -> void:
	# TODO: phase panel only exists after intro tween completes (async)
	pass

func test_auto_complete_after_delay() -> void:
	# TODO: requires awaiting AUTO_COMPLETE_DELAY (5 s) in test
	pass

func test_phase_dots_built_for_multi_phase_boss() -> void:
	# TODO: _build_phase_panel() reads _boss._phase_cfg — requires mock boss
	pass

func test_phase_dot_updates_on_phase_change() -> void:
	# TODO: same — needs phase_dots array populated first
	pass

func test_pray_action_calls_tick_prayer() -> void:
	# TODO: requires InputEvent simulation for "pray" action
	pass

func test_release_pray_calls_reset_prayer() -> void:
	# TODO: requires InputEvent hold + release simulation
	pass
