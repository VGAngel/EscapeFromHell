@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Crumbling platform — collapses shortly after the player first touches it
# and regenerates after REGEN_DELAY so levels can be replayed.

const CRUMBLE_DELAY: float = 0.5
const FADE_DURATION: float = 0.35
const REGEN_DELAY:   float = 3.0

var _trigger:    Area2D = null
var _crumbling:  bool   = false

func _ready() -> void:
	platform_type = "crumbling"
	super._ready()
	if Engine.is_editor_hint():
		return
	_build_trigger()

func _build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1   # player layer
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Slightly taller than platform so a landing player definitely overlaps.
	rect.size = Vector2(size.x, size.y + 8.0)
	col.shape = rect
	_trigger.add_child(col)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _crumbling:
		return
	if not body.is_in_group("player"):
		return
	_crumbling = true
	await get_tree().create_timer(CRUMBLE_DELAY).timeout
	if not is_inside_tree():
		return
	_fade_out_and_disable()

func _fade_out_and_disable() -> void:
	var tw := create_tween()
	if _visual:
		tw.tween_property(_visual, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(_disable_collision)
	tw.tween_interval(REGEN_DELAY)
	tw.tween_callback(_regenerate)

func _disable_collision() -> void:
	if _shape:
		_shape.set_deferred("disabled", true)

func _regenerate() -> void:
	if not is_inside_tree():
		return
	if _shape:
		_shape.set_deferred("disabled", false)
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "modulate:a", 1.0, FADE_DURATION)
	_crumbling = false
