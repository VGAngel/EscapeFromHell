extends Node2D

# Pulsing gold halo that draws the eye to a freshly-discovered object
# while its tutorial hint is shown at the top of the screen.
#
# Usage:
#   var hl = preload("res://scripts/ui/DiscoveryHighlight.gd").new()
#   hl.lifetime = 6.0
#   target_node.add_child(hl)
#
# Self-frees after `lifetime` seconds (with a final fade-out tween).
# The halo size auto-fits the parent: we measure the parent's bounding
# rect (CollisionShape2D, Sprite2D, or fallback constant) and draw a
# ring slightly larger than that. Pulses scale + alpha at TRANS_SINE.
#
# Reduce-motion aware: static gold ring without pulse if MotionSettings
# is enabled — colour-blind / motion-sensitive players still get the
# visual cue, just not the animation.

@export var lifetime: float = 6.0
@export var color: Color = Color(1.0, 0.85, 0.35, 0.85)
@export var pulse_period: float = 0.9   # seconds per full pulse cycle
@export var pulse_scale: float = 1.18    # peak scale relative to base

var _base_radius: float = 32.0
var _ring: Sprite2D = null
var _t: float = 0.0
var _life_t: float = 0.0
var _fading_out: bool = false
var _reduce_motion: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	z_index = 5  # draw above sibling sprites in the same room
	_resolve_radius()
	_build_ring()
	var ms: Node = get_node_or_null("/root/MotionSettings")
	_reduce_motion = (
			ms and ms.has_method("is_enabled") and ms.is_enabled())
	# Fade-in
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	_life_t += delta
	if not _fading_out and _life_t >= lifetime:
		_start_fade_out()
		return
	if _reduce_motion or _ring == null:
		return
	_t += delta
	# Sine pulse: scale 1.0 ↔ pulse_scale, alpha 0.65 ↔ 1.0
	var phase: float = sin(_t * TAU / pulse_period)
	var scale_v: float = lerp(1.0, pulse_scale, (phase + 1.0) * 0.5)
	_ring.scale = Vector2(scale_v, scale_v)
	_ring.modulate.a = lerp(0.65, 1.0, (phase + 1.0) * 0.5)


# ── Internal ──────────────────────────────────────────────────────────────────

# Try to size the halo to the parent's bounding box. CollisionShape2D
# (CircleShape2D / RectangleShape2D) is the cheapest source; falls
# back to the parent's first Sprite2D, then a sane constant.
func _resolve_radius() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	# CollisionShape2D circle?
	for child in parent.get_children():
		if child is CollisionShape2D:
			var shape: Shape2D = (child as CollisionShape2D).shape
			if shape is CircleShape2D:
				_base_radius = (shape as CircleShape2D).radius + 14.0
				return
			if shape is RectangleShape2D:
				var ext: Vector2 = (shape as RectangleShape2D).size * 0.5
				_base_radius = maxf(ext.x, ext.y) + 14.0
				return
	# Sprite2D fallback
	for child in parent.get_children():
		if child is Sprite2D and (child as Sprite2D).texture:
			var sp: Sprite2D = child
			var sz: Vector2 = sp.texture.get_size() * sp.scale
			_base_radius = max(sz.x, sz.y) * 0.5 + 14.0
			return


func _build_ring() -> void:
	# Procedurally build a gold ring as an ImageTexture so we don't
	# need a separate halo asset. Drawn at 2× resolution then scaled
	# down — keeps the edge crisp on FHD.
	var diameter: int = int(_base_radius * 2.0)
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var center: Vector2 = Vector2(diameter * 0.5, diameter * 0.5)
	var outer_r: float = float(diameter) * 0.5
	var inner_r: float = outer_r - 6.0
	for y in diameter:
		for x in diameter:
			var d: float = Vector2(x, y).distance_to(center)
			if d <= outer_r and d >= inner_r:
				# Soft edge: full alpha at mid-ring, taper at outer + inner
				var ring_pos: float = (d - inner_r) / (outer_r - inner_r)
				var soft: float = sin(ring_pos * PI)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, soft))
	var tex := ImageTexture.create_from_image(img)
	_ring = Sprite2D.new()
	_ring.texture = tex
	_ring.modulate = color
	add_child(_ring)


func _start_fade_out() -> void:
	_fading_out = true
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.45) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
