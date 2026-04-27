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
