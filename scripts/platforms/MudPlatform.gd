@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Circle 4 platform type — mud. Solid to stand on, but while the player
# is standing on it their horizontal velocity gets damped each frame,
# so running feels sluggish. A thin Area2D above the platform detects
# occupancy; the mud itself stays a normal StaticBody2D.

@export var slow_factor: float = 0.55

var _top_trigger: Area2D = null
var _player_on:   bool   = false

func _ready() -> void:
	platform_type = "mud"
	super._ready()
	if Engine.is_editor_hint():
		return
	_build_top_trigger()

func _build_top_trigger() -> void:
	_top_trigger = Area2D.new()
	_top_trigger.collision_layer = 0
	_top_trigger.collision_mask  = 1
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, 12.0)
	col.shape = rect
	# Sit a thin strip just above the platform top so a body standing on
	# it overlaps — avoids false positives from bodies brushing the sides.
	_top_trigger.position = Vector2(0.0, -size.y * 0.5 - 4.0)
	_top_trigger.add_child(col)
	add_child(_top_trigger)
	_top_trigger.body_entered.connect(_on_body_entered)
	_top_trigger.body_exited.connect(_on_body_exited)

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _player_on:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player and "velocity" in player:
		player.velocity.x *= slow_factor

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = false
