@tool
extends "res://scripts/platforms/BasePlatform.gd"

# One-way platform — collides only from above.
# The player can jump up through it and drop down freely.

func _ready() -> void:
	platform_type = "one_way"
	super._ready()
	if _shape:
		_shape.one_way_collision = true
		_shape.one_way_collision_margin = 2.0
