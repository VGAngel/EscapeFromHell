extends Control

# Red border vignette flash on player damage. Sister of SinVignette but
# transient: each `damage_taken` event triggers a 0 → peak → 0 alpha
# tween over ~0.3s with a sharp attack and slower decay so it reads
# as a "punch" rather than a smooth fade.
#
# Listens to:
#   • Player.damage_taken(amount) — found by group "player" on first
#     hit, then connected. Multi-hit safe (overlapping flashes
#     additive-clamped to MAX_ALPHA).
#
# Visual:
#   • Full-rect ColorRect with a canvas_item shader that draws a
#     solid red ring along the screen edges (radial mask). The
#     centre stays clear so the player can still see what hit them.
#   • Intensity = clamp(amount / 3, 0.4, 1.0). A 1-damage tick is
#     softer than a 3-damage spike-impact.
#
# Mouse filter is IGNORE so taps still pass through to gameplay.

const PEAK_TIME   := 0.06     # fast attack — punch
const FADE_TIME   := 0.28     # slower decay
const MAX_ALPHA   := 0.55
const MIN_INTENSITY := 0.4
const MAX_INTENSITY := 1.0

var _shader_mat: ShaderMaterial = null
var _player: Node = null
var _current_tween: Tween = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shader()
	modulate.a = 0.0
	# Listen for player to appear and connect — handles scene-load
	# ordering where HUD is built before Player.
	_try_connect_player()
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _player != null:
		return
	# Group membership is added in Player._ready, which fires AFTER
	# node_added — defer the actual check by one frame so the group
	# is in place. We also accept any node that already exposes the
	# damage_taken signal (covers test fakes).
	if node.has_signal("damage_taken"):
		_player = node
		_connect_player()
	else:
		call_deferred("_late_check_player", node)


func _late_check_player(node: Node) -> void:
	if _player != null or not is_instance_valid(node):
		return
	if node.is_in_group("player") or node.has_signal("damage_taken"):
		_player = node
		_connect_player()


func _try_connect_player() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p:
		_player = p
		_connect_player()


func _connect_player() -> void:
	if _player == null:
		return
	if _player.has_signal("damage_taken") \
			and not _player.damage_taken.is_connected(_on_damage_taken):
		_player.damage_taken.connect(_on_damage_taken)


# ── Public ────────────────────────────────────────────────────────────────────

# Manually trigger a flash. Tests call this directly without needing a
# Player node; HUD installs us as a listener so gameplay code doesn't
# need to know we exist.
func flash(amount: int = 1) -> void:
	var intensity: float = clamp(
			float(max(amount, 1)) / 3.0, MIN_INTENSITY, MAX_INTENSITY)
	var peak_a: float = MAX_ALPHA * intensity
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(self, "modulate:a", peak_a, PEAK_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# ── Hooks ─────────────────────────────────────────────────────────────────────

func _on_damage_taken(amount: int) -> void:
	flash(amount)


# ── Shader ────────────────────────────────────────────────────────────────────

func _build_shader() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec3 flash_color : source_color = vec3(0.85, 0.10, 0.10);

// Solid red ring along the screen edges, clear in the middle.
// Mask is bright at the corners (r near 1.0) and fades quickly toward
// the centre (smoothstep 0.45 → 1.0).
float edge_ring(vec2 uv) {
	vec2 d = uv - vec2(0.5);
	float r = length(d) * 1.5;
	return smoothstep(0.45, 1.0, r);
}

void fragment() {
	float mask = edge_ring(UV);
	COLOR = vec4(flash_color, mask);
}
"""
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = sh
	_shader_mat.set_shader_parameter("flash_color", Vector3(0.85, 0.10, 0.10))
	# Carrier ColorRect — its alpha is multiplied by parent modulate.
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	rect.material = _shader_mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
