@tool
extends StaticBody2D

## Базова платформа. Автоматично створює CollisonShape2D і PlaceholderVisual.

@export var platform_type: String = "stone" :
	set(v):
		platform_type = v
		_rebuild()

@export var size: Vector2 = Vector2(96, 16) :
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
