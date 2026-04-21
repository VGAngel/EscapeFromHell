@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Bounce platform — flings the player upward on contact. Works with any
# CharacterBody2D exposing a `velocity` property (Player does).

@export var bounce_force: float = 700.0
const BOUNCE_COOLDOWN: float = 0.15

var _trigger:  Area2D = null
var _cooldown: float  = 0.0

func _ready() -> void:
	platform_type = "bounce"
	super._ready()
	if Engine.is_editor_hint():
		return
	_build_trigger()

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta

func _build_trigger() -> void:
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, 10.0)
	col.shape = rect
	# Place trigger just above the top surface.
	_trigger.position = Vector2(0.0, -size.y * 0.5 - 2.0)
	_trigger.add_child(col)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _cooldown > 0.0:
		return
	if not body.is_in_group("player"):
		return
	if not body is CharacterBody2D:
		return
	_cooldown = BOUNCE_COOLDOWN
	var cb := body as CharacterBody2D
	cb.velocity.y = -bounce_force
	_play_bounce_tween()

func _play_bounce_tween() -> void:
	if not _visual:
		return
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector2(1.15, 0.7), 0.08)
	tw.tween_property(_visual, "scale", Vector2.ONE, 0.14)
