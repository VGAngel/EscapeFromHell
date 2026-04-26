@tool
extends StaticBody2D

## Базова платформа. Автоматично створює CollisonShape2D і PlaceholderVisual.

## Standard platform height used by all generated rooms.
const PLATFORM_HEIGHT: float = 30.0

@export var platform_type: String = "stone" :
	set(v):
		platform_type = v
		_rebuild()

@export var size: Vector2 = Vector2(96, PLATFORM_HEIGHT) :
	set(v):
		size = v
		_rebuild()

var _shape: CollisionShape2D
var _visual: Node2D

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	_rebuild_collision()
	_rebuild_visual()

func _rebuild_collision() -> void:
	# Skip rebuild when the node isn't in the tree yet — _ready() will call
	# _rebuild() again once the node is properly added, avoiding a transient
	# solid (non-one-way) CollisionShape2D that can interfere with physics.
	if not is_inside_tree():
		return
	if _shape and is_instance_valid(_shape):
		_shape.queue_free()
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	_shape.shape = rect
	# All raised platforms are jump-through-able from below. Walls/floors
	# are added via _add_wall in PlaceholderRoom and bypass this script,
	# so they stay solid as expected.
	_shape.one_way_collision = true
	_shape.one_way_collision_margin = 2.0
	add_child(_shape)

func _rebuild_visual() -> void:
	if not is_inside_tree():
		return
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
