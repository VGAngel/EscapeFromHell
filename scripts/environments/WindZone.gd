@tool
extends Area2D

# Circle 2 environment hazard — a wind corridor that pushes bodies inside
# it along `wind_direction` at `wind_force` px/s². Can be rhythmic
# (_gust_interval > 0 → only blows in bursts) or steady.
#
# The zone reshapes its own CollisionShape2D + draws a subtle overlay in
# the editor so level designers see the affected area.

@export var wind_direction: Vector2 = Vector2.RIGHT :
	set(v):
		wind_direction = v.normalized() if v.length() > 0.01 else Vector2.RIGHT
		queue_redraw()
@export var wind_force:     float   = 320.0
@export var zone_size:      Vector2 = Vector2(320, 200) :
	set(v):
		zone_size = v
		_rebuild_shape()
		queue_redraw()
@export var gust_interval:  float   = 0.0   # 0 = steady wind
@export var gust_duration:  float   = 1.2
@export var player_only:    bool    = true

var _shape:        CollisionShape2D = null
var _bodies:       Array            = []
var _gust_timer:   float            = 0.0
var _gust_active:  bool             = true

func _ready() -> void:
	collision_layer = 0
	collision_mask  = 1   # player
	monitoring  = true
	monitorable = false
	_rebuild_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if gust_interval > 0.0:
		_gust_active = false
		_gust_timer  = gust_interval

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

	if gust_interval > 0.0:
		_gust_timer -= delta
		if _gust_timer <= 0.0:
			_gust_active = not _gust_active
			_gust_timer = gust_duration if _gust_active else gust_interval

	if not _gust_active:
		return

	for body in _bodies:
		if not is_instance_valid(body):
			continue
		if "velocity" not in body:
			continue
		body.velocity += wind_direction * wind_force * delta

func _on_body_entered(body: Node2D) -> void:
	if player_only and not body.is_in_group("player"):
		return
	if body in _bodies:
		return
	_bodies.append(body)

func _on_body_exited(body: Node2D) -> void:
	_bodies.erase(body)

func _draw() -> void:
	var col := Color(0.55, 0.75, 0.95, 0.12)
	draw_rect(Rect2(-zone_size * 0.5, zone_size), col)
	# Arrow hint along wind_direction
	var arrow_col := Color(0.80, 0.90, 1.00, 0.35)
	var a := Vector2.ZERO
	var b: Vector2 = a + wind_direction * minf(zone_size.x, zone_size.y) * 0.35
	draw_line(a, b, arrow_col, 2.0)
	var tip := wind_direction.rotated(PI * 0.85) * 8.0
	draw_line(b, b + tip, arrow_col, 2.0)
	draw_line(b, b + tip.rotated(-PI * 0.3), arrow_col, 2.0)
