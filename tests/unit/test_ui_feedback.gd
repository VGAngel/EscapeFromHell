extends GutTest

# Tests for UIFeedback — auto-wires every BaseButton with a tap-grow
# scale tween and a HapticManager.tap_light() pulse on press.

const FeedbackScript := preload("res://scripts/managers/UIFeedback.gd")

var fb: Node

func before_each() -> void:
	fb = FeedbackScript.new()
	add_child_autofree(fb)
	# _ready hooks node_added + wires existing — children added later
	# in the test will also be wired automatically.

# ── Auto-wire ─────────────────────────────────────────────────────────────────

func test_wires_button_added_after_ready() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	# Same instance_id should now be in the registry.
	assert_true(fb._wired.has(btn.get_instance_id()),
			"button should be auto-wired on tree-enter")

func test_wires_existing_buttons_at_boot() -> void:
	# Add a button, then create a fresh feedback node — it should
	# pick the existing button up via _wire_existing_buttons.
	var btn := Button.new()
	add_child_autofree(btn)
	var fb2: Node = FeedbackScript.new()
	add_child_autofree(fb2)
	assert_true(fb2._wired.has(btn.get_instance_id()))

func test_double_wire_is_idempotent() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	var conns_before: int = btn.pressed.get_connections().size()
	fb._wire(btn)   # explicit re-wire
	fb._wire(btn)
	var conns_after: int = btn.pressed.get_connections().size()
	assert_eq(conns_after, conns_before,
			"second _wire() must not add another connection")

func test_tree_exit_drops_from_registry() -> void:
	var btn := Button.new()
	add_child(btn)
	var id: int = btn.get_instance_id()
	assert_true(fb._wired.has(id))
	remove_child(btn)
	btn.free()
	assert_false(fb._wired.has(id), "freed button must drop from registry")

# ── Pulse ─────────────────────────────────────────────────────────────────────

func test_press_starts_pulse_tween() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	btn.size = Vector2(100, 50)
	btn.emit_signal("pressed")
	# A tween was stashed under meta so subsequent presses can kill it.
	assert_true(btn.has_meta("ui_feedback_tween"))

func test_pivot_offset_set_to_centre_on_press() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	btn.size = Vector2(120, 40)
	btn.pivot_offset = Vector2.ZERO
	btn.emit_signal("pressed")
	assert_eq(btn.pivot_offset, btn.size * 0.5)

func test_disabled_button_skips_feedback() -> void:
	var btn := Button.new()
	btn.disabled = true
	add_child_autofree(btn)
	btn.size = Vector2(80, 30)
	btn.emit_signal("pressed")
	# No tween stashed → meta missing.
	assert_false(btn.has_meta("ui_feedback_tween"))

func test_feel_disabled_meta_skips_feedback() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	btn.size = Vector2(80, 30)
	btn.set_meta("feel_disabled", true)
	btn.emit_signal("pressed")
	assert_false(btn.has_meta("ui_feedback_tween"))

# ── Amplitude per variation ───────────────────────────────────────────────────

func test_icon_button_gets_smaller_amplitude() -> void:
	var btn := Button.new()
	btn.theme_type_variation = "IconButton"
	add_child_autofree(btn)
	assert_almost_eq(fb._amp_for(btn), fb.PULSE_AMP_ICON, 0.0001)

func test_default_button_gets_default_amplitude() -> void:
	var btn := Button.new()
	add_child_autofree(btn)
	assert_almost_eq(fb._amp_for(btn), fb.PULSE_AMP_DEFAULT, 0.0001)
