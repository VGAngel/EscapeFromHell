@tool
extends Area2D

# Circle 4 environment hazard — swampy ground that slows horizontal movement
# and optionally ticks poison damage while the player is inside.
#
# Slow is applied by multiplying body.velocity.x every physics frame (works
# for any CharacterBody2D with a `velocity` property — Player qualifies).
# Poison damage uses Player.receive_hit like the lava zone but with a much
# gentler tick rate and no knockback.

@export var zone_size: Vector2 = Vector2(240, 64) :
	set(v):
		zone_size = v
		_rebuild_shape()
		queue_redraw()
@export var slow_factor:      float = 0.55     # velocity.x *= slow_factor
@export var poison_per_tick:  int   = 0        # 0 = no poison, just slow
@export var poison_interval:  float = 1.5

var _shape:  CollisionShape2D = null
var _bodies: Array            = []
var _tick:   float            = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1
	monitoring  = true
	monitorable = false
	_rebuild_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _rebuild_shape() -> void:
	if _shape and is_instance_valid(_shape):
		_shape.queue_free()
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = zone_size
	_shape.shape = rect
	add_child(_shape)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _bodies.is_empty():
		return

	# Per-frame: dampen horizontal velocity so moving through swamp is sluggish.
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if "velocity" not in body:
			continue
		body.velocity.x *= slow_factor

	# Optional poison tick.
	if poison_per_tick <= 0:
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = poison_interval
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if body.has_method("receive_hit"):
			body.receive_hit(poison_per_tick, Vector2.ZERO)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body in _bodies:
		return
	_bodies.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)

func _draw() -> void:
	# Murky base
	draw_rect(Rect2(-zone_size * 0.5, zone_size), Color(0.12, 0.22, 0.10, 0.82))
	# Oily surface highlight
	var surf := zone_size.y * 0.18
	draw_rect(Rect2(-zone_size * 0.5, Vector2(zone_size.x, surf)),
			  Color(0.30, 0.45, 0.22, 0.6))
