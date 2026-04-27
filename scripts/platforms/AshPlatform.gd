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
	# Thin top-strip trigger — wrapping the whole body would crumble the
	# platform when the player's head clipped the underside on a jump-up.
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, 12.0)
	col.shape = rect
	_trigger.position = Vector2(0.0, -size.y * 0.5 - 4.0)
	_trigger.add_child(col)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _crumbling or not body.is_in_group("player"):
		return
	if "velocity" in body and body.velocity.y < 0.0:
		return
	_crumbling = true
	_play_warning_shake()
	await get_tree().create_timer(CRUMBLE_DELAY).timeout
	if not is_inside_tree():
		return
	_collapse()

## Quick jitter + warm tint during the very short CRUMBLE_DELAY so the
## player can see the platform reacting to their step before it falls.
func _play_warning_shake() -> void:
	if not _visual:
		return
	var base_pos: Vector2 = _visual.position
	var base_mod: Color   = _visual.modulate
	var tw := create_tween()
	# Ash is faster than Crumbling — single quick shake cycle.
	tw.tween_property(_visual, "position", base_pos + Vector2(2.0, 0.0),  0.03)
	tw.tween_property(_visual, "position", base_pos + Vector2(-2.0, 0.0), 0.03)
	tw.tween_property(_visual, "position", base_pos, 0.02)
	tw.parallel().tween_property(_visual, "modulate",
		Color(1.20, 0.80, 0.55, base_mod.a), CRUMBLE_DELAY)

func _collapse() -> void:
	var tw := create_tween()
	if _visual:
		tw.parallel().tween_property(_visual, "modulate:a", 0.0, FADE_DURATION)
		tw.parallel().tween_property(_visual, "scale", Vector2(1.2, 0.4), FADE_DURATION)
	tw.tween_callback(_disable_collision)

func _disable_collision() -> void:
	if _shape:
		_shape.set_deferred("disabled", true)
