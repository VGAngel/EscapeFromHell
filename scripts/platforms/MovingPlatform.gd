@tool
extends AnimatableBody2D

# Moving platform — ping-pongs linearly between its start position and an
# offset along one axis. Uses AnimatableBody2D + sync_to_physics so that
# CharacterBody2D.move_and_slide() correctly carries standing bodies along.
#
# Configure via scene/inspector:
#   move_axis  = "horizontal" | "vertical"
#   distance   = signed offset from start (negative flips direction)
#   speed      = px / sec
#   size       = platform visual + collision size
#   pause_at_ends = brief pause at each endpoint (sec)

@export_enum("horizontal", "vertical") var move_axis: String = "horizontal"
@export var distance:      float   = 160.0
@export var speed:         float   = 80.0
@export var pause_at_ends: float   = 0.4
@export var size: Vector2 = Vector2(96, 16) :
	set(v):
		size = v
		_rebuild()

@export var platform_type: String = "moving_horizontal" :
	set(v):
		platform_type = v
		_rebuild_visual()

var _shape:            CollisionShape2D = null
var _visual:           Node2D           = null
var _start_pos:        Vector2          = Vector2.ZERO
var _end_pos:          Vector2          = Vector2.ZERO
var _heading_to_end:   bool             = true
var _pause_timer:      float            = 0.0

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	sync_to_physics = true
	collision_layer = 1
	_start_pos = position
	_end_pos   = _start_pos + _axis_vector() * distance
	_rebuild()
	# Keep platform_type in sync with move_axis when unset
	if platform_type == "moving_horizontal" and move_axis == "vertical":
		platform_type = "moving_vertical"
		_rebuild_visual()

# ── Movement ──────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return
	var goal: Vector2 = _end_pos if _heading_to_end else _start_pos
	position = position.move_toward(goal, speed * delta)
	if position.distance_to(goal) < 0.5:
		position = goal
		_heading_to_end = not _heading_to_end
		_pause_timer = pause_at_ends

func _axis_vector() -> Vector2:
	return Vector2.DOWN if move_axis == "vertical" else Vector2.RIGHT

# ── Build / rebuild ───────────────────────────────────────────────────────────

func _rebuild() -> void:
	_rebuild_collision()
	_rebuild_visual()

func _rebuild_collision() -> void:
	if _shape and is_instance_valid(_shape):
		_shape.queue_free()
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	add_child(_shape)

func _rebuild_visual() -> void:
	if _visual and is_instance_valid(_visual):
		_visual.queue_free()
	var script := load("res://scripts/rooms/PlaceholderVisual.gd")
	if not script:
		return
	_visual = Node2D.new()
	_visual.set_script(script)
	_visual.set("platform_type", platform_type)
	_visual.set("custom_size", size)
	add_child(_visual)
