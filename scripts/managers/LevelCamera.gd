extends Camera2D
class_name LevelCamera

## Single source of truth for the in-game camera.
##
## Responsibilities:
##  • Reads camera_config.json and applies smoothing, deadzone, lookahead,
##    look-up-when-falling, default zoom.
##  • Computes hard limits from the union of all rooms in
##    /root/.../RoomContainer (rooms expose room_width / room_height meta).
##  • Reserves space at the bottom of the viewport for the on-screen mobile
##    HUD (movement / jump buttons), so the player never sits under them.
##  • Public apply_zoom_preset("void_levels") so per-level scripts can pull
##    a preset by name from the config instead of hard-coding numbers.
##
## Attach this script to the Camera2D node inside Player.tscn — that way it
## spawns with the player and there is no Level-vs-Player camera race.

const CONFIG_PATH := "res://camera_config.json"

## How much vertical space (in design pixels at zoom 1) the on-screen
## controls occupy at the bottom of the viewport. Player camera offsets up
## by half of this so the player rests in the visible upper portion.
const HUD_BOTTOM_RESERVE := 260.0

# ── Cached config ─────────────────────────────────────────────────────────────
var _lookahead_enabled:       bool  = true
var _lookahead_distance:      float = 120.0
var _lookahead_change_delay:  float = 0.3
var _smoothing_enabled:       bool  = true
var _smoothing_speed:         float = 5.0
var _deadzone_w:              float = 40.0
var _deadzone_h:              float = 80.0
var _look_up_when_falling:    bool  = true
var _look_up_distance:        float = 60.0
var _zoom_default:            float = 1.0
var _zoom_presets:            Dictionary = {}

# ── Runtime state ─────────────────────────────────────────────────────────────
var _facing_right:            bool  = true
var _pending_facing:          bool  = true
var _facing_change_t:         float = 0.0
var _lookahead_offset_x:      float = 0.0
var _hud_offset_y:            float = 0.0
var _fall_offset_y:           float = 0.0

# How fast offset.x (lookahead) and offset.y (fall-look) chase their
# target each second. Lower = smoother. Tuned to feel like the same
# "weight" as the position smoothing.
const _OFFSET_FOLLOW_SPEED := 1.8

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	_apply_smoothing_and_deadzone()
	_apply_default_zoom()
	_apply_hud_offset()
	_apply_room_limits_deferred()
	make_current()

func _load_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not f:
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (v is Dictionary):
		return
	var cam: Dictionary = v.get("camera", {})

	var la: Dictionary = cam.get("lookahead", {})
	_lookahead_enabled       = bool(la.get("enabled", true))
	_lookahead_distance      = float(la.get("distance_horizontal", 120.0))
	_lookahead_change_delay  = float(la.get("direction_change_delay", 0.3))

	var sm: Dictionary = cam.get("smoothing", {})
	_smoothing_enabled       = bool(sm.get("enabled", true))
	_smoothing_speed         = float(sm.get("speed", 5.0))

	var dz: Dictionary = cam.get("deadzone", {})
	_deadzone_w              = float(dz.get("width", 40.0))
	_deadzone_h              = float(dz.get("height", 80.0))

	var vt: Dictionary = cam.get("vertical", {})
	_look_up_when_falling    = bool(vt.get("look_up_when_falling", true))
	_look_up_distance        = float(vt.get("look_up_distance", 60.0))

	var z: Dictionary = cam.get("zoom", {})
	_zoom_default            = float(z.get("default", 1.0))
	for k in z.keys():
		if k == "default" or k == "note":
			continue
		var val: Variant = z[k]
		if val is float or val is int:
			_zoom_presets[String(k)] = float(val)

func _apply_smoothing_and_deadzone() -> void:
	# The project has physics_interpolation=true, so Godot already smooths the
	# render position of the player (and thus this child camera) between
	# physics ticks. Enabling Camera2D.position_smoothing on top fights that
	# interpolation and produces visible jitter — leave it OFF.
	position_smoothing_enabled = false

	# Drag margins still help: they create a deadzone where the camera doesn't
	# chase tiny motions, killing jitter from sub-pixel velocity noise.
	var vp_size: Vector2 = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1080),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1920)
	)
	var hx: float = clampf(_deadzone_w * 0.5 / vp_size.x, 0.0, 0.4)
	var hy: float = clampf(_deadzone_h * 0.5 / vp_size.y, 0.0, 0.4)
	drag_horizontal_enabled = true
	drag_vertical_enabled   = true
	drag_left_margin        = hx
	drag_right_margin       = hx
	drag_top_margin         = hy
	drag_bottom_margin      = hy

	# Smoothing the limit clamp makes it glide rather than snap when entering
	# a clamped edge — combined with no position_smoothing this is fine.
	limit_smoothed = true

	# Camera updates its own logic in idle process so offset transitions
	# happen at render rate (smooth) instead of physics rate (60 Hz steps).
	process_callback = Camera2D.CAMERA2D_PROCESS_IDLE

func _apply_default_zoom() -> void:
	zoom = Vector2(_zoom_default, _zoom_default)

func _apply_hud_offset() -> void:
	# Push the camera centre up by half the reserved HUD height so the
	# player ends up roughly mid-screen visually instead of behind the
	# buttons. Stored separately so apply_zoom_preset can rebuild offset.
	_hud_offset_y = -HUD_BOTTOM_RESERVE * 0.5
	offset = Vector2(_lookahead_offset_x, _hud_offset_y)

## Defer one frame so the level's procedural rooms are added to
## RoomContainer before we read their metadata.
func _apply_room_limits_deferred() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_apply_room_limits()

func _apply_room_limits() -> void:
	var rc: Node2D = _find_room_container()
	if rc == null:
		return
	var rect: Rect2 = _aggregate_room_rect(rc)
	if rect.size == Vector2.ZERO:
		return
	limit_left   = int(floorf(rect.position.x))
	limit_top    = int(floorf(rect.position.y))
	limit_right  = int(ceilf(rect.position.x + rect.size.x))
	limit_bottom = int(ceilf(rect.position.y + rect.size.y))

func _find_room_container() -> Node2D:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return null
	var rc: Node = scene.get_node_or_null("RoomContainer")
	return rc as Node2D

func _aggregate_room_rect(rc: Node2D) -> Rect2:
	var union: Rect2 = Rect2()
	var has_any: bool = false
	for child in rc.get_children():
		if not (child is Node2D):
			continue
		var r: Node2D = child
		var w: float = float(r.get_meta("room_width",  1080.0))
		var h: float = float(r.get_meta("room_height", 1920.0))
		var rect: Rect2 = Rect2(r.global_position, Vector2(w, h))
		if not has_any:
			union = rect
			has_any = true
		else:
			union = union.merge(rect)
	return union

# ── Per-frame: lookahead + look-up-when-falling ───────────────────────────────
func _process(delta: float) -> void:
	var parent: Node = get_parent()
	if parent == null:
		return

	if _lookahead_enabled and "_facing_right" in parent:
		_pending_facing = bool(parent.get("_facing_right"))
		if _pending_facing != _facing_right:
			_facing_change_t += delta
			if _facing_change_t >= _lookahead_change_delay:
				_facing_right     = _pending_facing
				_facing_change_t  = 0.0
		else:
			_facing_change_t = 0.0

	# Frame-rate independent exponential lerp toward the target offsets so
	# direction flips and fall-look glide in instead of snapping. Same
	# "weight" as position smoothing keeps the whole camera feel coherent.
	var target_x: float = 0.0
	if _lookahead_enabled:
		target_x = _lookahead_distance if _facing_right else -_lookahead_distance

	var target_fall_y: float = 0.0
	if _look_up_when_falling and parent is CharacterBody2D:
		var body: CharacterBody2D = parent
		if body.velocity.y > 200.0:
			target_fall_y = _look_up_distance

	var t: float = 1.0 - exp(-_OFFSET_FOLLOW_SPEED * delta)
	_lookahead_offset_x = lerpf(_lookahead_offset_x, target_x,      t)
	_fall_offset_y      = lerpf(_fall_offset_y,      target_fall_y, t)

	offset = Vector2(_lookahead_offset_x, _hud_offset_y + _fall_offset_y)

# ── Public ────────────────────────────────────────────────────────────────────
## Apply a zoom preset by name from camera_config.json (e.g. "void_levels").
## No-op if the preset is missing.
func apply_zoom_preset(preset_name: String) -> void:
	if not _zoom_presets.has(preset_name):
		return
	var z: float = _zoom_presets[preset_name]
	zoom = Vector2(z, z)

## Force a re-read of room bounds. Useful if rooms are spawned after
## the camera's initial deferred read.
func recompute_limits() -> void:
	_apply_room_limits()
