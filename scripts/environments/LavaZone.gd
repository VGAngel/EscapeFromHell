@tool
extends Area2D

# Circle 3 environment hazard — a lava pool (or vertical jet) that damages
# the player on contact and keeps ticking while they stay inside.
#
# Damage is dealt via Player.receive_hit(amount, knockback) — the knockback
# pushes the player UP (and away from the center horizontally) so walking
# into lava doesn't instantly one-shot you at low HP.

@export var zone_size: Vector2 = Vector2(160, 40) :
	set(v):
		zone_size = v
		_rebuild_shape()
		queue_redraw()
@export var damage_per_tick: int   = 1
@export var tick_interval:   float = 0.7
@export var knockback_force: float = 320.0

var _shape:     CollisionShape2D = null
var _bodies:    Array            = []
var _tick:      float            = 0.0

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
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = tick_interval
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if not body.has_method("receive_hit"):
			continue
		var dx: float = signf(body.global_position.x - global_position.x)
		if dx == 0.0:
			dx = 1.0
		var kb := Vector2(dx * knockback_force * 0.4, -knockback_force)
		body.receive_hit(damage_per_tick, kb, "lava")

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body in _bodies:
		return
	_bodies.append(body)
	# First touch deals damage immediately
	_tick = 0.0

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)

func _draw() -> void:
	# Molten body
	draw_rect(Rect2(-zone_size * 0.5, zone_size), Color(0.85, 0.22, 0.05, 0.85))
	# Hotter top band
	var top_h: float = zone_size.y * 0.25
	draw_rect(Rect2(-zone_size * 0.5, Vector2(zone_size.x, top_h)),
			  Color(1.00, 0.55, 0.10, 0.9))
