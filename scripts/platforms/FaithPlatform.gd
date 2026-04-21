@tool
extends "res://scripts/platforms/BasePlatform.gd"

# Circle 6 platform — faith. Solid while the player's sin is below
# `sin_threshold`; fades and disables collision once sin crosses the
# threshold. Used for "redemption run" lanes where a high-sin player
# literally cannot cross.
#
# Re-solidifies if sin drops back below the threshold (cleansing,
# reduce_sin) so the state is reversible mid-level.

@export var sin_threshold: float = 60.0

const CHECK_INTERVAL: float = 0.25
const FADE_DURATION:  float = 0.4

var _tick:       float = 0.0
var _solid:      bool  = true

func _ready() -> void:
	platform_type = "faith"
	super._ready()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = CHECK_INTERVAL
	var sin_val: float = SaveManager.get_sin() if SaveManager else 0.0
	var should_be_solid: bool = sin_val < sin_threshold
	if should_be_solid == _solid:
		return
	if should_be_solid:
		_solidify()
	else:
		_dissolve()

func _dissolve() -> void:
	_solid = false
	var tw := create_tween()
	if _visual:
		tw.tween_property(_visual, "modulate:a", 0.15, FADE_DURATION)
	tw.tween_callback(func() -> void:
		if _shape:
			_shape.set_deferred("disabled", true))

func _solidify() -> void:
	_solid = true
	if _shape:
		_shape.set_deferred("disabled", false)
	if _visual:
		var tw := create_tween()
		tw.tween_property(_visual, "modulate:a", 1.0, FADE_DURATION)
