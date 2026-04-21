extends Node

# Autoload: CameraShake
# Call CameraShake.shake(duration, intensity) from anywhere. Finds the
# active Camera2D via the viewport and tweens its offset through a
# random walk, then zeroes it.
#
# Safely no-ops if there's no active camera (e.g. in unit tests) or the
# tree isn't ready yet. Stacking shakes just starts a new tween — the
# tail zero-out still runs, so offset always returns to (0,0).

const STEP_DURATION: float = 0.05

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Shake the active Camera2D for `duration` seconds at ±`intensity` px.
func shake(duration: float, intensity: float) -> void:
	var tree := get_tree()
	if not tree:
		return
	var vp: Viewport = tree.root
	if not vp:
		return
	var cam: Camera2D = vp.get_camera_2d()
	if not cam:
		return
	var tw := create_tween()
	var steps: int = max(int(duration / STEP_DURATION), 1)
	for _i in steps:
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		tw.tween_property(cam, "offset", offset, STEP_DURATION)
	tw.tween_property(cam, "offset", Vector2.ZERO, STEP_DURATION)
