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
	# Thin strip just ABOVE the platform top — same pattern as Sin/Mud/Ice
	# platforms. A wide trigger that wrapped the whole body fired when the
	# player's head clipped the underside on a jump-up, crumbling the platform
	# before they ever landed on it.
	_trigger = Area2D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask  = 1   # player layer
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, 12.0)
	col.shape = rect
	_trigger.position = Vector2(0.0, -size.y * 0.5 - 4.0)
	_trigger.add_child(col)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if _crumbling:
		return
	if not body.is_in_group("player"):
		return
	# Extra safety: only crumble when the player is descending or grounded.
	# Catches the rare case where a passing one-way collision still triggers
	# the top-strip during a fast upward jump.
	if "velocity" in body and body.velocity.y < 0.0:
		return
	_crumbling = true
	_play_warning_shake()
	await get_tree().create_timer(CRUMBLE_DELAY).timeout
	if not is_inside_tree():
		return
	_fade_out_and_disable()

## Visual heads-up that this platform is about to collapse — small jitter +
## warm tint while the CRUMBLE_DELAY timer runs. Lets the player see "jump
## NOW" instead of being surprised by a silent disappearance.
func _play_warning_shake() -> void:
	if not _visual:
		return
	var base_pos: Vector2 = _visual.position
	var base_mod: Color   = _visual.modulate
	var tw := create_tween()
	tw.set_loops(int(CRUMBLE_DELAY / 0.06))
	tw.tween_property(_visual, "position", base_pos + Vector2(2.0, 0.0),  0.03)
	tw.tween_property(_visual, "position", base_pos + Vector2(-2.0, 0.0), 0.03)
	tw.parallel().tween_property(_visual, "modulate",
		Color(1.15, 0.85, 0.6, base_mod.a), CRUMBLE_DELAY * 0.5)
	tw.chain().tween_property(_visual, "position", base_pos, 0.0)

func _fade_out_and_disable() -> void:
	var fx: Node = get_node_or_null("/root/ParticleEffects")
	if fx and fx.has_method("spawn"):
		fx.spawn("crumble", global_position)
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
