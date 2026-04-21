extends Node

# Autoload: SceneTransition
# Fullscreen fade-to-black overlay for scene changes.
# Usage:
#   SceneTransition.change_scene_to("res://scenes/Hub.tscn")
#   SceneTransition.change_scene_to("res://scenes/Hub.tscn", 0.6)
#
# The overlay sits on its own CanvasLayer (layer = 100) above HUD and any
# screen UI. The fade always uses process_mode = ALWAYS so it still tweens
# even when the tree is paused.

const DEFAULT_DURATION := 0.4

var _layer:   CanvasLayer = null
var _overlay: ColorRect   = null
var _busy:    bool        = false

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_overlay = ColorRect.new()
	_overlay.color = Color.BLACK
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.modulate.a = 0.0
	_overlay.visible = false
	_layer.add_child(_overlay)

# ── Public API ────────────────────────────────────────────────────────────────

## Fade to black, swap scene, fade back in. `duration` is the full round-trip.
func change_scene_to(scene_path: String, duration: float = DEFAULT_DURATION) -> void:
	if _busy:
		return
	_busy = true
	var half: float = duration * 0.5

	await fade_out(half)
	get_tree().change_scene_to_file(scene_path)
	# One frame so the new scene is in the tree before fading back in.
	await get_tree().process_frame
	await fade_in(half)

	_busy = false

## Fade the overlay from transparent to opaque. Awaits the tween.
func fade_out(duration: float = DEFAULT_DURATION) -> void:
	_overlay.visible = true
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.tween_property(_overlay, "modulate:a", 1.0, duration)
	await tw.finished

## Fade the overlay from opaque to transparent. Awaits the tween.
func fade_in(duration: float = DEFAULT_DURATION) -> void:
	var tw := create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.tween_property(_overlay, "modulate:a", 0.0, duration)
	await tw.finished
	_overlay.visible = false

func is_busy() -> bool:
	return _busy
