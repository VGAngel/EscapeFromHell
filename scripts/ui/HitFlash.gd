extends Control

# Black edge-vignette pulse fired when the player's staff connects with
# an enemy. Sister widget to DamageFlash:
#   • DamageFlash = RED — the player took damage.
#   • HitFlash    = BLACK — the player dealt damage ("кров чорна").
#
# Listens to:
#   • Player.enemy_struck(was_last) — found by group "player" the same
#     way DamageFlash hunts for the player node. `was_last` thickens the
#     pulse a touch so a "last enemy down" moment feels punchier.
#
# Visual: solid black ring along the screen edges, clear in the centre,
# very fast attack and a short fade so the swing reads as a single
# "thump" without lingering.

const PEAK_TIME       := 0.04
const FADE_TIME       := 0.22
const MAX_ALPHA       := 0.55
const LAST_ENEMY_BOOST := 0.20  # +alpha when was_last

var _shader_mat: ShaderMaterial = null
var _player: Node = null
var _current_tween: Tween = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shader()
	modulate.a = 0.0
	_try_connect_player()
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if _player != null:
		return
	if node.has_signal("enemy_struck"):
		_player = node
		_connect_player()
	else:
		call_deferred("_late_check_player", node)


# Variant param so a freed Object delivered via call_deferred (transient
# children created during another node's _ready) doesn't crash the cast.
func _late_check_player(node: Variant) -> void:
	if _player != null or not is_instance_valid(node):
		return
	var n: Node = node as Node
	if n == null:
		return
	if n.is_in_group("player") or n.has_signal("enemy_struck"):
		_player = n
		_connect_player()


func _try_connect_player() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p:
		_player = p
		_connect_player()


func _connect_player() -> void:
	if _player == null:
		return
	if _player.has_signal("enemy_struck") \
			and not _player.enemy_struck.is_connected(_on_enemy_struck):
		_player.enemy_struck.connect(_on_enemy_struck)


# ── Public ────────────────────────────────────────────────────────────────────

func flash(was_last: bool = false) -> void:
	var peak_a: float = MAX_ALPHA + (LAST_ENEMY_BOOST if was_last else 0.0)
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	# Tween must keep running during the hit-stop / slow-mo, so use the
	# always-process pause mode (Engine.time_scale doesn't pause it).
	_current_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_current_tween.tween_property(self, "modulate:a", peak_a, PEAK_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(self, "modulate:a", 0.0, FADE_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


# ── Hooks ─────────────────────────────────────────────────────────────────────

func _on_enemy_struck(was_last: bool) -> void:
	flash(was_last)


# ── Shader ────────────────────────────────────────────────────────────────────

func _build_shader() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform vec3 flash_color : source_color = vec3(0.0, 0.0, 0.0);

// Edge ring identical in shape to DamageFlash so the visual language
// reads as a sibling effect (same shape, different colour).
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
	_shader_mat.set_shader_parameter("flash_color", Vector3(0.0, 0.0, 0.0))
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.color = Color.WHITE
	rect.material = _shader_mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
