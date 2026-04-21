@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Circle 5 platform type — ash. Crumbles much faster than the standard
# crumbling platform and does not regenerate within the level. Leaves a
# small dust puff (scale tween) on collapse.

const CRUMBLE_DELAY: float = 0.2
const FADE_DURATION: float = 0.25

var _trigger:   Area2D = null
var _crumbling: bool   = false

func _ready() -> void:
	platform_type = "ash"
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
	if _crumbling or not body.is_in_group("player"):
		return
	_crumbling = true
	await get_tree().create_timer(CRUMBLE_DELAY).timeout
	if not is_inside_tree():
		return
	_collapse()

func _collapse() -> void:
	var tw := create_tween()
	if _visual:
		tw.parallel().tween_property(_visual, "modulate:a", 0.0, FADE_DURATION)
		tw.parallel().tween_property(_visual, "scale", Vector2(1.2, 0.4), FADE_DURATION)
	tw.tween_callback(_disable_collision)

func _disable_collision() -> void:
	if _shape:
		_shape.set_deferred("disabled", true)
