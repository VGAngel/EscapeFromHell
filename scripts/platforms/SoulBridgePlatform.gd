@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Blue translucent platform — only solid while the player is carrying a
# soul. Disappears (visually + collision) the moment they drop or deliver
# it. Polled at CHECK_INTERVAL so there's no per-frame SaveManager query.

const CHECK_INTERVAL: float = 0.1
const FADE_DURATION:  float = 0.25

var _tick:         float = 0.0
var _solid:        bool  = false   # starts invisible

func _ready() -> void:
	platform_type = "soul_bridge"
	super._ready()
	if _shape:
		_shape.disabled = true
	if _visual:
		_visual.modulate.a = 0.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = CHECK_INTERVAL
	var carrying: bool = _player_is_carrying()
	if carrying == _solid:
		return
	if carrying:
		_appear()
	else:
		_vanish()

func _player_is_carrying() -> bool:
	var p: Node = get_tree().get_first_node_in_group("player")
	if not p:
		return false
	if p.has_method("is_carrying"):
		return p.is_carrying()
	# Legacy property fallbacks for older Player schemas.
	if "carried_soul_ids" in p:
		var ids = p.carried_soul_ids
		return ids is Array and (ids as Array).size() > 0
	return "carried_soul_id" in p and String(p.carried_soul_id) != ""

func _appear() -> void:
	_solid = true
	if _shape:
		_shape.set_deferred("disabled", false)
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "modulate:a", 0.65, FADE_DURATION)

func _vanish() -> void:
	_solid = false
	var tw := create_tween()
	if _visual:
		tw.tween_property(_visual, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		if _shape:
			_shape.set_deferred("disabled", true))
