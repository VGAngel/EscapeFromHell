extends Control

# Poison-veins vignette overlay for the in-game HUD. Replaces the cold
# sin progress bar with a diegetic, atmospheric red border that pulses
# stronger and faster as sin climbs.
#
# Shader draws curving "veins" via warped sin functions, masked by a
# radial vignette so the pattern only shows at the screen edges. The
# alpha and pulse-rate are driven by uniforms updated each frame from
# the current sin %.
#
# Hooks:
#   • GameManager.sin_changed(new_value) → set_sin(new_value)
#   • _process(dt) drives time uniform
#
# Visual contract: zero impact at 0% sin (fully transparent), barely
# noticeable up to 30%, clearly red at 60%, intense pulsing red at 100%.

const FADE := 0.6                # alpha tween when sin changes
const MAX_ALPHA := 0.55           # cap so it never blocks gameplay reading
const PULSE_HZ_MIN := 0.4         # at low sin, slow breath
const PULSE_HZ_MAX := 2.0         # at full sin, panicked pulse

var _shader_mat: ShaderMaterial = null
var _t: float = 0.0
var _sin_pct: float = 0.0
var _reduce_motion: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shader()
	# Start fully transparent — let _on_sin_changed drive the actual alpha.
	modulate.a = 0.0
	# Subscribe to the live signal first; if it's not available, fall back to
	# a one-shot poll of SaveManager. Use the global autoload symbol —
	# Engine.has_singleton() returns false for project autoloads (those
	# are global script symbols, not engine singletons), so the previous
	# OR-with-Engine.has_singleton was always evaluating only the
	# get_node_or_null branch.
	if GameManager and GameManager.has_signal("sin_changed"):
		GameManager.sin_changed.connect(_on_sin_changed)
	_initial_poll()
	# Reduce-motion: the pulsing veins are exactly the kind of animation
	# motion-sensitive players want disabled. We freeze the time uniform
	# (so no pulse) but keep intensity intact (so the static red ring
	# remains as a visual sin indicator).
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_signal("changed"):
		ms.changed.connect(_on_motion_changed)
	_reduce_motion = (ms and ms.has_method("is_enabled") and ms.is_enabled())


func _process(delta: float) -> void:
	if _reduce_motion:
		# Freeze time so the pulsing/vein animation stops; the static
		# red ring stays visible (intensity is set in set_sin).
		return
	_t += delta
	if _shader_mat:
		_shader_mat.set_shader_parameter("time", _t)


func _on_motion_changed(enabled: bool) -> void:
	_reduce_motion = enabled


# ── Public ────────────────────────────────────────────────────────────────────

func set_sin(pct: float) -> void:
	# Clamp + mark for shader. Tween modulate.a to target so changes
	# don't pop visually.
	_sin_pct = clamp(pct, 0.0, 100.0)
	var p: float = _sin_pct / 100.0
	if _shader_mat:
		_shader_mat.set_shader_parameter("intensity", p)
		_shader_mat.set_shader_parameter("pulse_hz",
				lerp(PULSE_HZ_MIN, PULSE_HZ_MAX, p))
	var target_a: float = p * MAX_ALPHA
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", target_a, FADE)


# ── Hooks ─────────────────────────────────────────────────────────────────────

func _on_sin_changed(new_value: float) -> void:
	set_sin(new_value)


# Pull current sin from SaveManager once at start — covers the case
# where the player resumed a run with sin already > 0 and no
# sin_changed has fired yet.
func _initial_poll() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm and sm.has_method("get_sin"):
		set_sin(float(sm.get_sin()))


# ── Shader ────────────────────────────────────────────────────────────────────

func _build_shader() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_hz  : hint_range(0.0, 4.0) = 0.5;
uniform float time = 0.0;
uniform vec3  vein_color : source_color = vec3(0.55, 0.05, 0.05);

// Vignette mask — bright (1.0) at the edges, dark (0.0) in the centre.
float edge_mask(vec2 uv) {
	vec2 d = uv - vec2(0.5);
	float r = length(d) * 1.5;       // 0 centre, ~1 corner
	return smoothstep(0.45, 1.0, r);
}

// Cheap "veins" using a warped sin field — sharp dark ridges.
float veins(vec2 uv, float t) {
	float warp = sin(uv.y * 12.0 + t * 0.7) * 0.18;
	float a = sin(uv.x * 20.0 + warp + t * 0.4);
	float b = sin((uv.x + uv.y) * 14.0 - t * 0.3 + warp);
	float v = abs(a + b) * 0.5;
	v = 1.0 - v;
	return pow(clamp(v, 0.0, 1.0), 8.0);  // sharpen ridges
}

void fragment() {
	float mask = edge_mask(UV);
	if (mask <= 0.0001 || intensity <= 0.0001) {
		COLOR = vec4(0.0);
	} else {
		float pulse = 0.5 + 0.5 * sin(time * pulse_hz * 6.2831853);
		float v = veins(UV, time) * mask;
		float a = (mask * 0.5 + v * 0.5) * (0.55 + 0.45 * pulse) * intensity;
		COLOR = vec4(vein_color, a);
	}
}
"""
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	_shader_mat.set_shader_parameter("intensity", 0.0)
	_shader_mat.set_shader_parameter("pulse_hz",  PULSE_HZ_MIN)
	_shader_mat.set_shader_parameter("time", 0.0)
	# Fill the rect so the shader has UV to draw on.
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	rect.material = _shader_mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
