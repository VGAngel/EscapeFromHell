extends Node

# (No `class_name` — headless GUT runs don't register editor globals,
# so callers preload this script and instantiate via .new() + setup().)

# Ambient effects for MainMenu (and reusable for any Control screen):
#   • Embers rising from the bottom (warm orange CPUParticles2D)
#   • Ash falling from the top (cool grey CPUParticles2D)
#   • Warm radial flicker (factor of a torch flame)
#   • Sin-tinted red vignette whose alpha tracks SaveManager.get_sin()
#   • Parallax drift on embers/ash from mouse position or accelerometer
#   • Subtle "breathing" scale-tween on a configurable Label
#
# Built entirely in code — no new assets, no .tscn changes. Attach via
# MenuAmbient.attach(self, $TitleLabel) from MainMenu._ready().
#
# Respects the global "reduce_motion" toggle if present in SettingsScreen
# (read once via SaveManager.get_setting fallback). Cleans up on free.

const EMBER_COUNT       := 22
const ASH_COUNT         := 18
const PARALLAX_STRENGTH := Vector2(14.0, 8.0)
const PARALLAX_SMOOTH   := 6.0
const FLICKER_PERIOD    := 1.7
const SIN_TINT_MAX      := 0.22
const TITLE_BREATH_AMP  := 0.018
const TITLE_BREATH_HZ   := 0.45

var _root: Control = null
var _title: Label = null
var _embers: CPUParticles2D = null
var _ash: CPUParticles2D = null
var _flicker: ColorRect = null
var _sin_tint: ColorRect = null
var _t: float = 0.0
var _tilt: Vector2 = Vector2.ZERO
var _sin_poll: float = 0.0
var _reduce_motion: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

# Caller pattern (works in both editor builds and headless tests):
#   var amb = preload("res://scripts/ui/MenuAmbient.gd").new()
#   root.add_child(amb)
#   amb.setup(root, title_label)
func setup(root: Control, title: Label = null) -> void:
	name = "MenuAmbient"
	_root = root
	_title = title
	_build()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	if _root == null:
		return
	_reduce_motion = _read_reduce_motion()
	_build_flicker()
	_build_embers()
	_build_ash()
	_build_sin_tint()
	# Insert ourselves above Background but below TitleLabel/buttons.
	# Background is typically child index 0 in MainMenu.tscn.
	if _root.has_node("Background"):
		var bg_idx: int = _root.get_node("Background").get_index()
		# Move particle/visual nodes right after the background.
		for child in [_flicker, _embers, _ash, _sin_tint]:
			if child and child.is_inside_tree():
				_root.move_child(child, bg_idx + 1)
	set_process(true)
	# Refresh sin tint immediately (don't wait for first poll).
	_refresh_sin_tint()


# Embers rising from the bottom edge.
func _build_embers() -> void:
	_embers = CPUParticles2D.new()
	_embers.name = "Embers"
	_embers.amount = EMBER_COUNT
	_embers.lifetime = 4.5
	_embers.preprocess = 3.0
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var size := _viewport_size()
	_embers.emission_rect_extents = Vector2(size.x * 0.5, 4.0)
	_embers.position = Vector2(size.x * 0.5, size.y + 8.0)
	_embers.direction = Vector2(0, -1)
	_embers.spread = 22.0
	_embers.gravity = Vector2(0, -18)
	_embers.initial_velocity_min = 18.0
	_embers.initial_velocity_max = 42.0
	_embers.scale_amount_min = 1.4
	_embers.scale_amount_max = 3.0
	_embers.color = Color(1.0, 0.55, 0.18, 0.85)
	# Slight orange→red drift via colour-ramp would need a Gradient; keep simple.
	_root.add_child(_embers)
	if _reduce_motion:
		_embers.emitting = false


# Ash drifting down from the top edge.
func _build_ash() -> void:
	_ash = CPUParticles2D.new()
	_ash.name = "Ash"
	_ash.amount = ASH_COUNT
	_ash.lifetime = 8.0
	_ash.preprocess = 4.0
	_ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var size := _viewport_size()
	_ash.emission_rect_extents = Vector2(size.x * 0.5, 4.0)
	_ash.position = Vector2(size.x * 0.5, -8.0)
	_ash.direction = Vector2(0, 1)
	_ash.spread = 18.0
	_ash.gravity = Vector2(0, 8)
	_ash.initial_velocity_min = 10.0
	_ash.initial_velocity_max = 22.0
	_ash.scale_amount_min = 1.0
	_ash.scale_amount_max = 2.2
	_ash.color = Color(0.78, 0.74, 0.70, 0.40)
	_root.add_child(_ash)
	if _reduce_motion:
		_ash.emitting = false


# Warm radial vignette that pulses softly — mimics a torch flicker.
func _build_flicker() -> void:
	_flicker = ColorRect.new()
	_flicker.name = "FlickerVignette"
	_flicker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flicker.color = Color.WHITE  # actual color set by shader
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 tint : source_color = vec3(0.18, 0.06, 0.02);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv);
	// Bright in the centre, dark at corners — additive warmth on top
	// of the bg, plus a darker outer ring that sells "torchlight".
	float warm = (1.0 - smoothstep(0.0, 0.55, d)) * 0.35 * strength;
	float dark = smoothstep(0.45, 0.95, d) * 0.55 * strength;
	vec3 col = tint * warm;
	COLOR = vec4(col, dark + warm * 0.4);
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("strength", 1.0)
	sm.set_shader_parameter("tint", Vector3(0.55, 0.18, 0.05))
	_flicker.material = sm
	_root.add_child(_flicker)


# Red sin-tint vignette — alpha proportional to current sin %.
func _build_sin_tint() -> void:
	_sin_tint = ColorRect.new()
	_sin_tint.name = "SinTint"
	_sin_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sin_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sin_tint.color = Color(0.45, 0.04, 0.04, 0.0)
	_root.add_child(_sin_tint)


# ── Per-frame updates ─────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_t += delta
	_update_parallax(delta)
	_update_flicker()
	_update_title_breathing()
	_sin_poll += delta
	if _sin_poll >= 0.5:
		_sin_poll = 0.0
		_refresh_sin_tint()


# Smoothly track tilt (mouse on desktop, accelerometer on mobile) and
# offset embers/ash so the foreground feels parallaxed against bg.
func _update_parallax(delta: float) -> void:
	if _reduce_motion:
		return
	var target := Vector2.ZERO
	if OS.has_feature("mobile"):
		var accel := Input.get_accelerometer()
		# Map accelerometer X/Z to a -1..1 range (rough — the device is held
		# roughly upright, so lateral tilt is X and forward/back is Z).
		target = Vector2(clamp(accel.x / 5.0, -1.0, 1.0),
				clamp(-accel.z / 5.0, -1.0, 1.0))
	else:
		var size := _viewport_size()
		var mp := _root.get_local_mouse_position()
		target = Vector2(
			clamp(mp.x / size.x * 2.0 - 1.0, -1.0, 1.0),
			clamp(mp.y / size.y * 2.0 - 1.0, -1.0, 1.0))
	_tilt = _tilt.lerp(target, clamp(delta * PARALLAX_SMOOTH, 0.0, 1.0))
	var off := -_tilt * PARALLAX_STRENGTH
	if _embers:
		_embers.position.x = _viewport_size().x * 0.5 + off.x
	if _ash:
		_ash.position.x = _viewport_size().x * 0.5 + off.x * 0.6


# Flame-like flicker: low-frequency sine + small high-frequency jitter.
func _update_flicker() -> void:
	if _flicker == null:
		return
	if _reduce_motion:
		return
	var sm := _flicker.material as ShaderMaterial
	if sm == null:
		return
	var base := 1.0 + 0.10 * sin(_t * TAU / FLICKER_PERIOD)
	var jitter := 0.04 * sin(_t * 9.31 + 1.7)
	sm.set_shader_parameter("strength", base + jitter)


# Subtle "breathing" scale on title, anchored at its centre.
func _update_title_breathing() -> void:
	if _title == null:
		return
	if _reduce_motion:
		return
	var s := 1.0 + TITLE_BREATH_AMP * sin(_t * TAU * TITLE_BREATH_HZ)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2(s, s)


# Sin tint alpha = (sin / 100) clamped, lerped toward target so it
# never snaps. Reads SaveManager once per poll interval.
func _refresh_sin_tint() -> void:
	if _sin_tint == null:
		return
	if not Engine.has_singleton("SaveManager") and not _has_save_manager():
		return
	var sin_pct: float = 0.0
	if _has_save_manager():
		sin_pct = float(SaveManager.get_sin())
	var target_a: float = clamp(sin_pct / 100.0, 0.0, 1.0) * SIN_TINT_MAX
	# Ease toward the new value via short tween (kept short so closing
	# Settings or finishing a level reflects fast).
	var c := _sin_tint.color
	var tw := create_tween()
	tw.tween_property(_sin_tint, "color",
			Color(c.r, c.g, c.b, target_a), 0.4)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _viewport_size() -> Vector2:
	if _root and _root.is_inside_tree():
		return _root.get_viewport_rect().size
	return Vector2(1080, 1920)


func _has_save_manager() -> bool:
	return get_node_or_null("/root/SaveManager") != null


# Tries to read settings.json (via SaveManager.get_setting) — falls back to
# false if the autoload or method is missing.
func _read_reduce_motion() -> bool:
	if not _has_save_manager():
		return false
	if SaveManager.has_method("get_setting"):
		return bool(SaveManager.get_setting("reduce_motion", false))
	return false
