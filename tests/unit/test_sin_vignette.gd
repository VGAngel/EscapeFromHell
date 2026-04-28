extends GutTest

# Tests for SinVignette — the poison-veins HUD overlay driven by sin %.

const SinVignetteScript := preload("res://scripts/ui/SinVignette.gd")

var v: Control

func before_each() -> void:
	v = SinVignetteScript.new()
	v.size = Vector2(1080, 1920)
	add_child_autofree(v)

# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_shader_material() -> void:
	assert_not_null(v._shader_mat, "shader material should be built")
	# A child ColorRect carries the material so the shader has UV.
	var rect_count: int = 0
	for child in v.get_children():
		if child is ColorRect:
			rect_count += 1
	assert_eq(rect_count, 1, "exactly one ColorRect host for the shader")

func test_initial_modulate_is_zero_alpha() -> void:
	# Before _initial_poll runs (or on a save with sin=0), alpha is 0.
	assert_lt(v.modulate.a, 0.05)

# ── set_sin ───────────────────────────────────────────────────────────────────

func test_set_sin_updates_shader_intensity() -> void:
	v.set_sin(50.0)
	assert_almost_eq(
			v._shader_mat.get_shader_parameter("intensity"), 0.5, 0.01,
			"intensity should be 0.5 at 50% sin")

func test_set_sin_pulse_scales_with_value() -> void:
	v.set_sin(0.0)
	var lo: float = v._shader_mat.get_shader_parameter("pulse_hz")
	v.set_sin(100.0)
	var hi: float = v._shader_mat.get_shader_parameter("pulse_hz")
	assert_gt(hi, lo, "pulse should be faster at higher sin")

func test_set_sin_clamps_above_100() -> void:
	v.set_sin(200.0)
	assert_eq(v._sin_pct, 100.0)
	assert_almost_eq(
			v._shader_mat.get_shader_parameter("intensity"), 1.0, 0.001)

func test_set_sin_clamps_below_zero() -> void:
	v.set_sin(-10.0)
	assert_eq(v._sin_pct, 0.0)

# ── Process ───────────────────────────────────────────────────────────────────

func test_process_advances_time_uniform() -> void:
	var t0: float = v._shader_mat.get_shader_parameter("time")
	v._process(0.5)
	var t1: float = v._shader_mat.get_shader_parameter("time")
	assert_gt(t1, t0)
