extends Node2D

## Test scene harness: flips the platform's shape to one-way after
## BasePlatform._ready() has built it, matching PlaceholderRoom._add_platform().

func _ready() -> void:
	call_deferred("_configure_platform")

func _configure_platform() -> void:
	var platform: StaticBody2D = $Platform
	var shape: CollisionShape2D = platform.get("_shape")
	if shape:
		shape.one_way_collision = true
		shape.one_way_collision_margin = 2.0
