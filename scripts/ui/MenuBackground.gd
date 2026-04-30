extends Node

# Animated parallax background for MainMenu. Replaces the static
# Background_01.png with a layered look:
#
#   L0 — animated red-sky shader (procedural FBM noise, no asset
#        needed). Slow vertical drift + a subtle pulse so the sky
#        always reads as living.
#   L1 — mid-distance silhouette (cathedral spires). Optional
#        TextureRect that loads `Assets/menu_bg_mid.png` if present;
#        gracefully skipped if the asset isn't there yet.
#   L2 — foreground hills / rocks silhouette, slightly darker.
#        Loads `Assets/menu_bg_near.png` with the same graceful
#        skip.
#
# All layers drift horizontally with the device tilt (mobile) or
# mouse position (desktop) at different rates — L0 barely moves,
# L1 drifts at half speed, L2 at full. Builds the parallax depth.
#
# Reduce-motion aware: when MotionSettings is enabled the shader
# time uniform freezes and the tilt drift is skipped, but the
# layered colour stays so the visual identity isn't lost.
#
# Usage:
#   var bg = preload("res://scripts/ui/MenuBackground.gd").new()
#   root.add_child(bg)
#   bg.setup(root)

const MID_TEX_PATH  := "res://Assets/menu_bg_mid.png"
const NEAR_TEX_PATH := "res://Assets/menu_bg_near.png"
const PARALLAX_STRENGTH := Vector2(8.0, 0.0)   # L2 max drift; L1 = ½, L0 = ¼
const PARALLAX_SMOOTH   := 4.0


var _root: Control = null
var _sky: ColorRect = null
var _mid: TextureRect = null
var _near: TextureRect = null
var _sky_mat: ShaderMaterial = null
var _t: float = 0.0
var _tilt: Vector2 = Vector2.ZERO
var _reduce_motion: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

func setup(root: Control) -> void:
	name = "MenuBackground"
	_root = root
	_build()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	if _root == null:
		return
	_reduce_motion = _read_reduce_motion()
	# When the .tscn already provides a static Background TextureRect
	# with a full hellscape image (Background_01/02.png), DON'T fight
	# it — let the static art read as the primary backdrop and only
	# add the optional silhouette layers + parallax tilt drift on top.
	# Skip the procedural sky shader entirely in that case.
	#
	# When there's no static texture (e.g. someone removed it from
	# the .tscn), fall back to building the FBM red-sky shader so
	# the menu still has a backdrop.
	var has_static_bg: bool = _root.has_node("Background") \
			and (_root.get_node("Background") as Control).visible
	if not has_static_bg:
		_build_sky()
	_build_silhouette_layer(MID_TEX_PATH,  "MidSilhouette",  0.5)
	_build_silhouette_layer(NEAR_TEX_PATH, "NearSilhouette", 1.0)
	# Insert above the existing static Background (so it covers it
	# fully) but below all interactive controls.
	if _root.has_node("Background"):
		var bg_idx: int = _root.get_node("Background").get_index()
		var ordered := [_sky, _mid, _near]
		var i := 1
		for child in ordered:
			if child and child.is_inside_tree():
				_root.move_child(child, bg_idx + i)
				i += 1
	set_process(true)


func _build_sky() -> void:
	_sky = ColorRect.new()
	_sky.name = "AnimatedSky"
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky.color = Color.WHITE   # actual rendering done by the shader
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

// Animated red-sky background. FBM noise drifts upward over time,
// a pulsing red gradient gives the whole thing a "smouldering"
// feel. Cheap on mobile — a few sin/hash calls per fragment.

uniform float time = 0.0;
uniform vec3  top_color    : source_color = vec3(0.30, 0.04, 0.06);
uniform vec3  bottom_color : source_color = vec3(0.06, 0.01, 0.02);
uniform vec3  ember_color  : source_color = vec3(0.95, 0.40, 0.18);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x)
			+ (d - b) * u.x * u.y;
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	// Vertical gradient — bright at the bottom (where the ember
	// glow lives), darker at the top (deep sky).
	vec3 base = mix(bottom_color, top_color, UV.y);

	// Drifting cloud / smoke pattern: low-frequency FBM moving up.
	vec2 p = UV * vec2(2.5, 4.0) + vec2(time * 0.02, -time * 0.04);
	float cloud = fbm(p) * 0.45;

	// Ember pulse: brighter near the bottom, slow sin breath.
	float pulse = 0.5 + 0.5 * sin(time * 0.7);
	float bottom_glow = pow(1.0 - UV.y, 3.0) * (0.30 + 0.20 * pulse);

	vec3 col = base + ember_color * bottom_glow + vec3(cloud * 0.10,
			cloud * 0.04, cloud * 0.02);

	COLOR = vec4(col, 1.0);
}
"""
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = sh
	_sky_mat.set_shader_parameter("time", 0.0)
	_sky.material = _sky_mat
	_root.add_child(_sky)


# Loads `path` into a TextureRect anchored full-rect. If the texture
# isn't present we silently skip — the sky shader alone still looks
# good enough to ship.
func _build_silhouette_layer(path: String, label: String, depth: float) -> void:
	# `ResourceLoader.exists()` returns true as long as the .import
	# stub is present, even when the imported .ctex binary hasn't
	# been generated yet (fresh checkout, CI without an --import
	# pass, MJ-pending placeholder, etc). Use a silent ResourceLoader
	# .load() so a missing binary skips the layer instead of pushing
	# an error into GUT's unexpected-errors bucket.
	if not ResourceLoader.exists(path):
		return
	var tex: Resource = ResourceLoader.load(
			path, "", ResourceLoader.CACHE_MODE_REUSE)
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.name = label
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture = tex
	rect.set_meta("parallax_depth", depth)
	_root.add_child(rect)
	if depth >= 1.0:
		_near = rect
	else:
		_mid = rect


# ── Per-frame drive ───────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _reduce_motion:
		return
	_t += delta
	if _sky_mat:
		_sky_mat.set_shader_parameter("time", _t)
	_update_parallax(delta)


func _update_parallax(delta: float) -> void:
	var target := Vector2.ZERO
	if OS.has_feature("mobile"):
		var accel := Input.get_accelerometer()
		target = Vector2(clamp(accel.x / 5.0, -1.0, 1.0), 0.0)
	else:
		var size := _viewport_size()
		var mp := _root.get_local_mouse_position()
		target = Vector2(clamp(mp.x / size.x * 2.0 - 1.0, -1.0, 1.0), 0.0)
	_tilt = _tilt.lerp(target, clamp(delta * PARALLAX_SMOOTH, 0.0, 1.0))
	# Static Background TextureRect drifts at quarter speed too —
	# subtle "the wall is breathing" feel without showing the edges.
	var legacy_bg: Node = _root.get_node_or_null("Background")
	if legacy_bg and legacy_bg is Control:
		(legacy_bg as Control).position.x = (
				-_tilt.x * PARALLAX_STRENGTH.x * 0.25)
	# Sky shader (when active — only when no static bg).
	if _sky:
		_sky.position.x = -_tilt.x * PARALLAX_STRENGTH.x * 0.25
	# Silhouettes drift at depth-weighted speeds.
	for layer in [_mid, _near]:
		if layer == null:
			continue
		var d: float = float(layer.get_meta("parallax_depth", 1.0))
		layer.position.x = -_tilt.x * PARALLAX_STRENGTH.x * d


# ── Helpers ───────────────────────────────────────────────────────────────────

func _viewport_size() -> Vector2:
	if _root and _root.is_inside_tree():
		return _root.get_viewport_rect().size
	return Vector2(1080, 1920)


func _read_reduce_motion() -> bool:
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_method("is_enabled"):
		return bool(ms.is_enabled())
	return false
