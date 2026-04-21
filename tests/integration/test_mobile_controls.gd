extends GutTest

# Integration tests for MobileControls.gd.
# Verifies button creation, layout, and input event emission.

const MobileControlsScript := preload("res://scripts/ui/MobileControls.gd")

var mc: Control

func before_each() -> void:
	mc = MobileControlsScript.new()
	add_child_autofree(mc)

# ── Button creation ───────────────────────────────────────────────────────────

func test_btn_left_created() -> void:
	assert_not_null(mc.btn_left)

func test_btn_right_created() -> void:
	assert_not_null(mc.btn_right)

func test_btn_jump_created() -> void:
	assert_not_null(mc.btn_jump)

func test_btn_staff_created() -> void:
	assert_not_null(mc.btn_staff)

func test_btn_pray_created() -> void:
	assert_not_null(mc.btn_pray)

# ── Default visibility ────────────────────────────────────────────────────────

func test_btn_pray_hidden_by_default() -> void:
	assert_false(mc.btn_pray.visible)

func test_movement_buttons_visible_by_default() -> void:
	assert_true(mc.btn_left.visible)
	assert_true(mc.btn_right.visible)

func test_action_buttons_visible_by_default() -> void:
	assert_true(mc.btn_jump.visible)
	assert_true(mc.btn_staff.visible)

# ── show_pray_button ──────────────────────────────────────────────────────────

func test_show_pray_button_true_makes_visible() -> void:
	mc.show_pray_button(true)
	assert_true(mc.btn_pray.visible)

func test_show_pray_button_false_hides() -> void:
	mc.show_pray_button(true)
	mc.show_pray_button(false)
	assert_false(mc.btn_pray.visible)

# ── Button sizes ──────────────────────────────────────────────────────────────

func test_jump_button_is_largest() -> void:
	assert_gt(mc.btn_jump.custom_minimum_size.x, mc.btn_staff.custom_minimum_size.x)
	assert_gt(mc.btn_jump.custom_minimum_size.y, mc.btn_staff.custom_minimum_size.y)

func test_movement_buttons_same_size() -> void:
	assert_eq(mc.btn_left.custom_minimum_size, mc.btn_right.custom_minimum_size)

# ── Layout — left cluster is left of center ───────────────────────────────────

func test_btn_left_is_to_left_of_btn_right() -> void:
	assert_lt(mc.btn_left.position.x, mc.btn_right.position.x)

func test_btn_staff_is_left_of_btn_jump() -> void:
	assert_lt(mc.btn_staff.position.x, mc.btn_jump.position.x)

func test_movement_cluster_left_of_action_cluster() -> void:
	var left_edge: float  = mc.btn_left.position.x
	var right_edge: float = mc.btn_staff.position.x
	assert_lt(left_edge, right_edge)

# ── Layout — all buttons at same Y baseline (within 40 px) ───────────────────

func test_movement_buttons_same_baseline() -> void:
	var diff: float = abs(mc.btn_left.position.y - mc.btn_right.position.y)
	assert_lt(diff, 1.0)

# ── Focus mode ────────────────────────────────────────────────────────────────

func test_all_buttons_have_no_focus() -> void:
	assert_eq(mc.btn_left.focus_mode,  Control.FOCUS_NONE)
	assert_eq(mc.btn_right.focus_mode, Control.FOCUS_NONE)
	assert_eq(mc.btn_jump.focus_mode,  Control.FOCUS_NONE)
	assert_eq(mc.btn_staff.focus_mode, Control.FOCUS_NONE)
	assert_eq(mc.btn_pray.focus_mode,  Control.FOCUS_NONE)

# ── Input event emission ──────────────────────────────────────────────────────

func test_press_left_fires_move_left_action() -> void:
	# Simulate button_down signal → check Input registers the action
	mc.btn_left.emit_signal("button_down")
	assert_true(Input.is_action_pressed("move_left"))
	mc.btn_left.emit_signal("button_up")

func test_release_left_clears_move_left_action() -> void:
	mc.btn_left.emit_signal("button_down")
	mc.btn_left.emit_signal("button_up")
	assert_false(Input.is_action_pressed("move_left"))

func test_press_right_fires_move_right_action() -> void:
	mc.btn_right.emit_signal("button_down")
	assert_true(Input.is_action_pressed("move_right"))
	mc.btn_right.emit_signal("button_up")

func test_press_jump_fires_jump_action() -> void:
	mc.btn_jump.emit_signal("button_down")
	assert_true(Input.is_action_pressed("jump"))
	mc.btn_jump.emit_signal("button_up")

func test_press_staff_fires_action_action() -> void:
	mc.btn_staff.emit_signal("button_down")
	assert_true(Input.is_action_pressed("action"))
	mc.btn_staff.emit_signal("button_up")

func test_press_pray_fires_pray_action() -> void:
	mc.btn_pray.emit_signal("button_down")
	assert_true(Input.is_action_pressed("pray"))
	mc.btn_pray.emit_signal("button_up")

# ── HUD integration ───────────────────────────────────────────────────────────

func test_hud_exposes_show_pray_button() -> void:
	var hud: Node = preload("res://scripts/ui/HUD.gd").new()
	add_child_autofree(hud)
	assert_true(hud.has_method("show_pray_button"))

func test_hud_show_pray_button_delegates_to_mobile_controls() -> void:
	var hud: Node = preload("res://scripts/ui/HUD.gd").new()
	add_child_autofree(hud)
	hud.show_pray_button(true)
	assert_not_null(hud._mobile_controls)
	assert_true(hud._mobile_controls.btn_pray.visible)

func test_hud_show_pray_button_false_hides() -> void:
	var hud: Node = preload("res://scripts/ui/HUD.gd").new()
	add_child_autofree(hud)
	hud.show_pray_button(true)
	hud.show_pray_button(false)
	assert_false(hud._mobile_controls.btn_pray.visible)
