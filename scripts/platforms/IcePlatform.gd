@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Circle 9 platform — ice. Solid, but an Area2D above it amplifies the
# player's horizontal velocity each frame so they keep sliding after
# releasing the move key. Cleaner than fiddling with PhysicsMaterial
# friction which Player.gd's custom deceleration wouldn't respect.

const SLIDE_MULT: float = 1.04   # slight amplification each physics tick

var _top_trigger: Area2D = null
var _player_on:   bool   = false

func _ready() -> void:
	platform_type = "ice"
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

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _player_on:
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if not player or not "velocity" in player:
		return
	# Amplify existing motion, capped so ice doesn't hurl the player.
	var vx: float = player.velocity.x
	if absf(vx) > 1.0:
		player.velocity.x = clampf(vx * SLIDE_MULT, -340.0, 340.0)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_on = false
