extends GutTest

# Integration tests for AltarNode.gd.
#
# AltarNode is a Node2D with an Area2D child, AnimationPlayer, and InteractPrompt.
# _ready() connects area signals — we use add_child_autofree() so _ready() fires.
# For pure-logic tests we also use a SafeAltarNode that adds minimal children.

# ── Helpers ───────────────────────────────────────────────────────────────────

## Build a minimal but functional AltarNode: Area2D + CollisionShape2D + InteractPrompt.
func _make_altar() -> AltarNode:
	var altar: AltarNode = preload("res://scripts/AltarNode.gd").new()

	# Area2D with a small circle shape so body_entered can fire
	var area := Area2D.new()
	area.name = "Area2D"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 64.0
	shape.shape = circle
	area.add_child(shape)
	altar.add_child(area)

	# InteractPrompt (Label is a Node so visible works)
	var prompt := Label.new()
	prompt.name  = "InteractPrompt"
	prompt.text  = "[E] Прив'язати"
	altar.add_child(prompt)

	add_child_autofree(altar)
	return altar

## Stub player body in the "player" group.
func _make_player() -> CharacterBody2D:
	var p := CharacterBody2D.new()
	p.add_to_group("player")
	add_child_autofree(p)
	return p

# ── is_active initial state ───────────────────────────────────────────────────

func test_is_active_false_on_start() -> void:
	var altar := _make_altar()
	assert_false(altar.is_active())

# ── _activate ─────────────────────────────────────────────────────────────────

func test_activate_sets_is_active_true() -> void:
	var altar := _make_altar()
	altar._activate()
	assert_true(altar.is_active())

func test_activate_emits_respawn_bound_signal() -> void:
	var altar := _make_altar()
	watch_signals(altar)
	altar._activate()
	assert_signal_emitted(altar, "respawn_bound")

func test_activate_signal_carries_altar_global_position() -> void:
	var altar := _make_altar()
	altar.global_position = Vector2(320.0, -480.0)
	watch_signals(altar)
	altar._activate()
	var args: Array = get_signal_parameters(altar, "respawn_bound")
	assert_eq(args[0], Vector2(320.0, -480.0))

func test_activate_twice_emits_signal_only_once() -> void:
	var altar := _make_altar()
	watch_signals(altar)
	altar._activate()
	altar._activate()
	assert_signal_emit_count(altar, "respawn_bound", 1)

func test_is_active_blocks_second_activate() -> void:
	var altar := _make_altar()
	altar._activate()
	watch_signals(altar)  # re-watch after first activate
	altar._activate()
	assert_signal_not_emitted(altar, "respawn_bound")

# ── bind_silently ─────────────────────────────────────────────────────────────

func test_bind_silently_sets_is_active_true() -> void:
	var altar := _make_altar()
	altar.bind_silently()
	assert_true(altar.is_active())

func test_bind_silently_does_not_emit_signal() -> void:
	var altar := _make_altar()
	watch_signals(altar)
	altar.bind_silently()
	assert_signal_not_emitted(altar, "respawn_bound")

# ── InteractPrompt visibility ─────────────────────────────────────────────────

func test_prompt_hidden_on_start() -> void:
	var altar := _make_altar()
	var prompt: Node = altar.get_node_or_null("InteractPrompt")
	assert_not_null(prompt)
	assert_false(prompt.visible)

func test_prompt_visible_after_player_enters() -> void:
	var altar := _make_altar()
	# Simulate area callback directly
	var player := _make_player()
	altar._on_body_entered(player)
	var prompt: Node = altar.get_node_or_null("InteractPrompt")
	assert_true(prompt.visible)

func test_prompt_hidden_after_player_leaves() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	altar._on_body_exited(player)
	var prompt: Node = altar.get_node_or_null("InteractPrompt")
	assert_false(prompt.visible)

func test_prompt_hidden_after_activation_even_when_player_in_range() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	altar._activate()
	var prompt: Node = altar.get_node_or_null("InteractPrompt")
	assert_false(prompt.visible)

func test_prompt_no_crash_when_prompt_node_absent() -> void:
	# Altar without InteractPrompt child must not crash
	var altar: AltarNode = preload("res://scripts/AltarNode.gd").new()
	add_child_autofree(altar)
	altar._update_prompt()   # direct call — must not error
	assert_true(true)

# ── _on_body_entered / _on_body_exited ────────────────────────────────────────

func test_non_player_body_does_not_show_prompt() -> void:
	var altar := _make_altar()
	var enemy := CharacterBody2D.new()
	enemy.add_to_group("enemy")
	add_child_autofree(enemy)
	altar._on_body_entered(enemy)
	var prompt: Node = altar.get_node_or_null("InteractPrompt")
	assert_false(prompt.visible)

func test_player_in_range_flag_set_on_enter() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	assert_true(altar._player_in_range)

func test_player_in_range_flag_cleared_on_exit() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	altar._on_body_exited(player)
	assert_false(altar._player_in_range)

# ── _unhandled_input guard conditions ────────────────────────────────────────

func test_input_ignored_when_player_not_in_range() -> void:
	var altar := _make_altar()
	watch_signals(altar)
	# Simulate "interact" press without player in range
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	altar._unhandled_input(ev)
	assert_signal_not_emitted(altar, "respawn_bound")

func test_input_ignored_when_already_active() -> void:
	var altar := _make_altar()
	altar._activate()   # already active
	altar._player_in_range = true
	watch_signals(altar)
	var ev := InputEventKey.new()
	ev.keycode = KEY_E
	ev.pressed = true
	altar._unhandled_input(ev)
	assert_signal_not_emitted(altar, "respawn_bound")

# ── LevelBase._respawn_position integration ───────────────────────────────────

func test_level_base_respawn_position_updated_on_altar_signal() -> void:
	# Use autofree (no scene-tree entry) to avoid @onready / _ready() errors.
	# _on_altar_respawn_bound only writes _respawn_position — no child nodes needed.
	const LevelBaseScript := preload("res://scripts/levels/LevelBase.gd")
	var lb: Node = autofree(LevelBaseScript.new())
	lb.set("_respawn_position", Vector2.ZERO)
	lb.call("_on_altar_respawn_bound", Vector2(128.0, -256.0))
	assert_eq(lb.get("_respawn_position"), Vector2(128.0, -256.0))

func test_level_base_respawn_uses_altar_position_over_spawn_point() -> void:
	const LevelBaseScript := preload("res://scripts/levels/LevelBase.gd")
	var lb: Node = autofree(LevelBaseScript.new())
	lb.set("_respawn_position", Vector2(200.0, -300.0))
	lb.call("_on_altar_respawn_bound", Vector2(400.0, -600.0))
	assert_eq(lb.get("_respawn_position"), Vector2(400.0, -600.0))

# ── pray action as alternate input ───────────────────────────────────────────

func test_pray_action_activates_altar_when_player_in_range() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	watch_signals(altar)
	var ev := InputEventAction.new()
	ev.action  = "pray"
	ev.pressed = true
	altar._unhandled_input(ev)
	assert_signal_emitted(altar, "respawn_bound")

func test_pray_action_ignored_when_player_not_in_range() -> void:
	var altar := _make_altar()
	watch_signals(altar)
	var ev := InputEventAction.new()
	ev.action  = "pray"
	ev.pressed = true
	altar._unhandled_input(ev)
	assert_signal_not_emitted(altar, "respawn_bound")

func test_pray_action_ignored_when_altar_already_active() -> void:
	var altar := _make_altar()
	var player := _make_player()
	altar._on_body_entered(player)
	altar._activate()
	watch_signals(altar)
	var ev := InputEventAction.new()
	ev.action  = "pray"
	ev.pressed = true
	altar._unhandled_input(ev)
	assert_signal_not_emitted(altar, "respawn_bound")

# ── pray button via HUD group ─────────────────────────────────────────────────

func test_set_pray_button_no_crash_without_hud_in_tree() -> void:
	var altar := _make_altar()
	# No HUD in scene → must not crash
	altar._set_pray_button(true)
	assert_true(true)

func test_set_pray_button_shows_via_hud_in_group() -> void:
	var altar := _make_altar()
	var hud: Node = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child_autofree(hud)   # _ready() adds it to "hud" group

	altar._set_pray_button(true)
	assert_true(hud._mobile_controls.btn_pray.visible)

func test_set_pray_button_hides_via_hud_in_group() -> void:
	var altar := _make_altar()
	var hud: Node = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child_autofree(hud)

	altar._set_pray_button(true)
	altar._set_pray_button(false)
	assert_false(hud._mobile_controls.btn_pray.visible)

func test_pray_button_shown_on_body_entered() -> void:
	var altar := _make_altar()
	var hud: Node = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child_autofree(hud)
	var player := _make_player()

	altar._on_body_entered(player)
	assert_true(hud._mobile_controls.btn_pray.visible)

func test_pray_button_hidden_on_body_exited() -> void:
	var altar := _make_altar()
	var hud: Node = preload("res://scenes/ui/HUD.tscn").instantiate()
	add_child_autofree(hud)
	var player := _make_player()

	altar._on_body_entered(player)
	altar._on_body_exited(player)
	assert_false(hud._mobile_controls.btn_pray.visible)
