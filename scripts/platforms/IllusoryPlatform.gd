@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Purple translucent platform — vanishes the instant the player touches
# it and returns after REGEN_DELAY seconds. Unlike Crumbling (which
# has a crumble-delay), illusory is immediate — the punishment for
# trusting the wrong platform.

const FADE_OUT:      float = 0.08
const REGEN_DELAY:   float = 3.0
const FADE_IN:       float = 0.4

var _trigger:  Area2D = null
var _active:   bool   = true

func _ready() -> void:
	platform_type = "illusory"
	super._ready()
	if Engine.is_editor_hint():
		return
	_build_trigger()

func _build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, size.y + 8.0)
	col.shape = rect
	_trigger.add_child(col)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if not _active or not body.is_in_group("player"):
		return
	_vanish()

func _vanish() -> void:
	_active = false
	var tw := create_tween()
	if _visual:
		tw.tween_property(_visual, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(_disable_collision)
	tw.tween_interval(REGEN_DELAY)
	tw.tween_callback(_appear)

func _disable_collision() -> void:
	if _shape:
		_shape.set_deferred("disabled", true)

func _appear() -> void:
	if not is_inside_tree():
		return
	if _shape:
		_shape.set_deferred("disabled", false)
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "modulate:a", 1.0, FADE_IN)
	_active = true
