@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Dark-red platform — solid, but while the player is standing on it
# SaveManager.add_sin(SIN_PER_SEC * delta) ticks every frame. The visual
# stays saturated so the player can't miss the drawback.

const SIN_PER_SEC: float = 2.0

var _top_trigger: Area2D = null
var _player_on:   bool   = false

func _ready() -> void:
	platform_type = "sin_platform"
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
	_top_trigger.position = Vector2(0.0, -size.y * 0.5 - 4.0)
	_top_trigger.add_child(col)
	add_child(_top_trigger)
	_top_trigger.body_entered.connect(_on_body_entered)
	_top_trigger.body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not _player_on:
		return
	# Route through GameManager (when available) so the HUD source-toast
	# fires; the toast itself throttles per-cause so per-frame ticks here
	# don't spam the screen.
	if GameManager and GameManager.has_method("add_sin"):
		GameManager.add_sin(SIN_PER_SEC * delta, "sin_platform")
	elif SaveManager:
		SaveManager.add_sin(SIN_PER_SEC * delta)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = false
