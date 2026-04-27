extends "res://scripts/levels/LevelBase.gd"

# VoidLevel — extends LevelBase for void-type levels.
#
# Key differences from a plain level:
#  • Camera zooms out to CAMERA_ZOOM (0.8) to reveal the wider exploration space.
#  • Exit is locked until ALL named souls are collected.
#    LevelBase already blocks entry via _on_exit_body_entered; VoidLevel adds a
#    visible "LockedIcon" child on the Exit node that shows/hides accordingly.
#  • When the last soul is collected the exit pulses to guide the player.
#  • Death limit is 5 — set in GameManager.DEATH_LIMITS["void"], no code needed here.
#
# Expected scene structure (same as LevelBase):
#   VoidLevel (Node2D) ← this script
#   ├── HUD
#   ├── RoomContainer
#   ├── SpawnPoint
#   └── Exit (Area2D)
#       └── LockedIcon (Node2D / Sprite2D / Label)  ← optional visual indicator

## Camera zoom applied to void levels — kept as a const for tests / scripts
## that read it directly. Runtime zoom is driven by the "void_levels" preset
## in camera_config.json (see _setup_camera_zoom); both should stay in sync.
const CAMERA_ZOOM := Vector2(0.8, 0.8)

## Scale overshoot used in the exit pulse tween.
const EXIT_PULSE_SCALE := Vector2(1.25, 1.25)

## Duration (seconds) of one pulse half-cycle.
const EXIT_PULSE_DURATION := 0.22

## Number of full pulse cycles when the exit unlocks.
const EXIT_PULSE_LOOPS := 3

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	_setup_camera_zoom()
	_update_exit_indicator()

# ── Camera ────────────────────────────────────────────────────────────────────

## Pull the "void_levels" zoom preset from camera_config.json. Tries
## synchronously first so callers (and tests) see the change immediately;
## only waits a frame if no camera is in the tree yet (e.g. LevelCamera
## still being attached after player spawn).
func _setup_camera_zoom() -> void:
	var cam: Camera2D = _find_camera()
	if not cam:
		await get_tree().process_frame
		cam = _find_camera()
	if not cam:
		return
	if cam.has_method("apply_zoom_preset"):
		cam.apply_zoom_preset("void_levels")
	else:
		# Fallback for non-LevelCamera Camera2D nodes (e.g. scene templates
		# without the custom script): apply the constant zoom directly.
		cam.zoom = CAMERA_ZOOM

## Resolve the active 2D camera, preferring an explicit child Camera2D when
## one exists (matches LevelBase scene layout) and falling back to whatever
## the viewport reports as current.
func _find_camera() -> Camera2D:
	for child in get_children():
		if child is Camera2D:
			return child
	return get_viewport().get_camera_2d() if get_viewport() else null

# ── Soul pickup override ──────────────────────────────────────────────────────

## Void levels have no altar — pickup IS collection. Increment _souls_found
## here so the exit-unlock check (_souls_found >= _souls_required in
## LevelBase._on_exit_body_entered) actually advances, then auto-drop the
## carried soul so the player's slot frees up for the next pickup.
##
## Tests still call _on_soul_collected for backwards compatibility; the alias
## below routes them through this same method.
func _on_soul_pickup_started(soul: Node) -> void:
	super(soul)
	_souls_found += 1
	if _player and _player.has_method("_drop_soul"):
		_player._drop_soul()
	_update_exit_indicator()
	if _souls_found >= _souls_required and _souls_required > 0:
		_pulse_exit()

## Backwards-compatible name used by older tests / hand-written calls.
func _on_soul_collected(soul: Node) -> void:
	_on_soul_pickup_started(soul)

# ── Exit indicator ────────────────────────────────────────────────────────────

## Show/hide the LockedIcon child on the Exit node.
## Called on ready (before any soul is collected) and after each collection.
func _update_exit_indicator() -> void:
	if not is_instance_valid(_exit_area):
		return
	var locked: bool = _souls_found < _souls_required
	var icon: Node = _exit_area.get_node_or_null("LockedIcon")
	if icon:
		icon.visible = locked

## Three-cycle scale pulse on the Exit to attract the player's attention.
func _pulse_exit() -> void:
	if not is_instance_valid(_exit_area):
		return
	var tw := create_tween()
	tw.set_loops(EXIT_PULSE_LOOPS)
	tw.tween_property(_exit_area, "scale", EXIT_PULSE_SCALE, EXIT_PULSE_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_exit_area, "scale", Vector2.ONE, EXIT_PULSE_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
