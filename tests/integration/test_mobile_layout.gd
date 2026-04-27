extends GutTest

# Tests for the mobile-control customisation layer (C5):
# size scale + per-button offset + persistence round-trip via SaveManager.

var mc: Node
var sm: Node

const MobileControlsScript := preload("res://scripts/ui/MobileControls.gd")
const SaveManagerScript    := preload("res://scripts/managers/SaveManager.gd")

func before_each() -> void:
	# Fresh SaveManager so leftover state from previous tests doesn't leak.
	if SaveManager:
		SaveManager._reset()
		SaveManager.set_mobile_layout({})
	mc = autofree(MobileControlsScript.new())
	add_child(mc)   # _ready runs → _build/_apply_safe_area
	# Wait for _ready / _build to complete its add_to_tree path
	await get_tree().process_frame

# ── Defaults ─────────────────────────────────────────────────────────────────

func test_default_size_scale_is_one() -> void:
	assert_almost_eq(mc.get_size_scale(), 1.0, 0.001)

func test_default_layout_dict_has_no_offsets() -> void:
	var layout: Dictionary = mc.get_layout()
	assert_true(layout.get("offsets", {}).is_empty())

# ── Size scale ───────────────────────────────────────────────────────────────

func test_set_size_scale_clamped_low() -> void:
	mc.set_size_scale(0.1)
	assert_almost_eq(mc.get_size_scale(), 0.5, 0.001,
		"clamped to floor 0.5")

func test_set_size_scale_clamped_high() -> void:
	mc.set_size_scale(5.0)
	assert_almost_eq(mc.get_size_scale(), 1.6, 0.001,
		"clamped to ceiling 1.6")

func test_set_size_scale_resizes_jump_button() -> void:
	mc.set_size_scale(1.0)
	var base_w: float = mc.btn_jump.size.x
	mc.set_size_scale(1.4)
	assert_almost_eq(mc.btn_jump.size.x, base_w * 1.4, 0.5)

# ── Edit mode toggle ─────────────────────────────────────────────────────────

func test_set_edit_mode_true_then_false() -> void:
	mc.set_edit_mode(true)
	assert_true(mc.is_edit_mode())
	mc.set_edit_mode(false)
	assert_false(mc.is_edit_mode())

# ── Layout persistence ──────────────────────────────────────────────────────

func test_save_and_load_layout_round_trip() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	mc.set_size_scale(1.2)
	mc._btn_offsets["jump"] = Vector2(40.0, -20.0)
	mc.save_layout()
	# Round-trip — fresh MobileControls reading from SaveManager should
	# reproduce the same scale and offset.
	var mc2: Node = autofree(MobileControlsScript.new())
	add_child(mc2)
	await get_tree().process_frame
	assert_almost_eq(mc2.get_size_scale(), 1.2, 0.001)
	var off: Vector2 = mc2._btn_offsets.get("jump", Vector2.ZERO)
	assert_almost_eq(off.x, 40.0, 0.5)
	assert_almost_eq(off.y, -20.0, 0.5)

func test_reset_layout_clears_offsets_and_scale() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	mc.set_size_scale(0.8)
	mc._btn_offsets["action"] = Vector2(10.0, 10.0)
	mc.reset_layout()
	assert_almost_eq(mc.get_size_scale(), 1.0, 0.001)
	assert_eq(mc._btn_offsets.size(), 0)
	# Persisted as empty dict — fresh load should also be defaults.
	var saved: Dictionary = SaveManager.get_mobile_layout()
	assert_true(saved.is_empty())

# ── Layout shape & serialization ─────────────────────────────────────────────

func test_get_layout_returns_size_scale_and_offsets_keys() -> void:
	mc.set_size_scale(1.1)
	mc._btn_offsets["jump"] = Vector2(15.0, -25.0)
	var layout: Dictionary = mc.get_layout()
	assert_true(layout.has("size_scale"), "layout missing size_scale key")
	assert_true(layout.has("offsets"),    "layout missing offsets key")
	assert_almost_eq(float(layout.size_scale), 1.1, 0.001)

func test_get_layout_serializes_vector2_as_json_safe_dict() -> void:
	# Vector2 doesn't survive JSON.stringify → JSON.parse round-trip.
	# Each offset must be {x, y} dict so save/load works.
	mc._btn_offsets["jump"] = Vector2(40.0, -20.0)
	var layout: Dictionary = mc.get_layout()
	var jump_off: Variant = layout.offsets.get("jump")
	assert_true(jump_off is Dictionary,
		"offset must be a Dict (Vector2 is not JSON-safe)")
	assert_almost_eq(float(jump_off.get("x", 0)),  40.0, 0.5)
	assert_almost_eq(float(jump_off.get("y", 0)), -20.0, 0.5)

func test_load_layout_accepts_legacy_vector2_or_dict() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	# Hand-craft a dict-shaped offset (the standard JSON form).
	SaveManager.set_mobile_layout({
		"size_scale": 1.3,
		"offsets":    {"jump": {"x": 50.0, "y": 10.0}},
	})
	var mc2: Node = autofree(MobileControlsScript.new())
	add_child(mc2)
	await get_tree().process_frame
	var off: Vector2 = mc2._btn_offsets.get("jump", Vector2.ZERO)
	assert_almost_eq(off.x, 50.0, 0.5)
	assert_almost_eq(off.y, 10.0, 0.5)
	assert_almost_eq(mc2.get_size_scale(), 1.3, 0.001)

# ── Offset survives scale changes ────────────────────────────────────────────

func test_offset_independent_of_size_scale() -> void:
	# Setting an offset, then changing size_scale, must not lose the offset
	# (it's stored per-action, not derived from position).
	mc._btn_offsets["jump"] = Vector2(60.0, 0.0)
	mc.set_size_scale(0.7)
	assert_eq(mc._btn_offsets.get("jump"), Vector2(60.0, 0.0))
	mc.set_size_scale(1.4)
	assert_eq(mc._btn_offsets.get("jump"), Vector2(60.0, 0.0))

# ── Edit-mode safety ─────────────────────────────────────────────────────────

func test_set_edit_mode_clears_pressed_finger_state() -> void:
	# Simulate a finger holding "jump", then enter edit mode — it must
	# release so the player doesn't get stuck pressing jump.
	mc._finger_actions[0] = "jump"
	mc.set_edit_mode(true)
	assert_eq(mc._finger_actions.size(), 0,
		"edit mode must wipe held actions to prevent stuck input")

# ── Settings save invocation ─────────────────────────────────────────────────

func test_save_layout_writes_through_to_save_manager() -> void:
	if not SaveManager:
		pending("SaveManager autoload missing")
		return
	mc.set_size_scale(1.25)
	mc._btn_offsets["action"] = Vector2(-30.0, 5.0)
	mc.save_layout()
	var saved: Dictionary = SaveManager.get_mobile_layout()
	assert_almost_eq(float(saved.get("size_scale", 0.0)), 1.25, 0.001)
	var off: Variant = saved.get("offsets", {}).get("action")
	assert_true(off is Dictionary)
	assert_almost_eq(float(off.x), -30.0, 0.5)
