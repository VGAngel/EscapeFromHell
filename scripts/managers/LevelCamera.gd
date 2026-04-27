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
##
## Implementation note: the camera runs in `top_level = true` mode, so its
## transform is independent of the player. Each idle frame we lerp
## global_position toward the player's actual position with an exponential
## decay. This produces buttery follow that does NOT fight Godot's physics
## interpolation, regardless of physics tick vs render rate mismatch.

const CONFIG_PATH := "res://camera_config.json"

## How much vertical space (in design pixels at zoom 1) the on-screen
## controls occupy at the bottom of the viewport. Player camera offsets up
## by half of this so the player rests in the visible upper portion.
const HUD_BOTTOM_RESERVE := 260.0

## Look-down peek — hold the "look_down" action for LOOK_DOWN_HOLD_DELAY
## seconds (without pressing it as a buffer for jump-cancel etc.) → camera
## smoothly pans LOOK_DOWN_OFFSET pixels down so the player can scout what's
## below before committing to a jump. Release → returns to normal.
const LOOK_DOWN_OFFSET     := 220.0
const LOOK_DOWN_HOLD_DELAY := 0.30

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
var _look_down_offset_y:      float = 0.0
var _look_down_hold_t:        float = 0.0   # how long ↓ has been held this press

# How fast the camera chases the player position each second (exponential
# decay rate). Higher = snappier, lower = floatier. 8.0 settles in ~0.3 s.
const _POSITION_FOLLOW_SPEED := 8.0

# How fast offset.x (lookahead) and offset.y (fall-look) chase their
# target each second. Lower than position so flips feel deliberate —
# 1.4 settles in ~1.5 s, gentle enough that the 240 px swing on a
# direction flip glides instead of whipping.
const _OFFSET_FOLLOW_SPEED := 1.4

# Stay-up offset from player origin. Equivalent to the old Camera2D
# position = (0, -80) in Player.tscn — keeps the player's torso/head
# visible above the camera centre rather than its feet.
const _PLAYER_VERTICAL_OFFSET := -80.0

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Decouple from the player transform so we control follow ourselves.
	# This is the key to jitter-free follow on devices where physics tick
	# rate (60 Hz) differs from screen refresh rate (90 / 120 / 144 Hz).
	top_level = true

	_load_config()
	_apply_camera_settings()
	_apply_default_zoom()
	_apply_hud_offset()

	# Snap to the player on the first frame so we don't lerp in from origin.
	var parent: Node2D = get_parent() as Node2D
	if parent:
		global_position = parent.global_position + Vector2(0, _PLAYER_VERTICAL_OFFSET)

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

func _apply_camera_settings() -> void:
	# Built-in smoothing and drag margins are bypassed: with top_level=true
	# we follow the player ourselves via a clean exponential lerp in
	# _process. That removes every source of double-smoothing.
	position_smoothing_enabled = false
	drag_horizontal_enabled    = false
	drag_vertical_enabled      = false

	# Limit clamp smoothing still helps — the camera glides into a wall
	# clamp rather than snapping when the player runs at the level edge.
	limit_smoothed = true

	# Don't touch process_callback: with physics_interpolation enabled at
	# the project level, Godot forces Camera2D to physics process and warns
	# if we override that. Our follow logic lives in _process (render rate)
	# anyway — the Camera2D's own process callback is irrelevant since we
	# disabled its built-in smoothing.

func _apply_default_zoom() -> void:
	zoom = Vector2(_zoom_default, _zoom_default)

func _apply_hud_offset() -> void:
	# Stored as a Y bias that gets baked into global_position each frame
	# in _process. Pushes the camera centre up by half the reserved HUD
	# height so the player rests in the visible upper portion.
	_hud_offset_y = -HUD_BOTTOM_RESERVE * 0.5

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

# ── Per-frame: smooth follow + lookahead + look-up-when-falling ──────────────
func _process(delta: float) -> void:
	var parent: Node2D = get_parent() as Node2D
	if parent == null:
		return

	# Latch facing with a delay so the camera doesn't whip around on
	# every tiny direction tap.
	if _lookahead_enabled and "_facing_right" in parent:
		_pending_facing = bool(parent.get("_facing_right"))
		if _pending_facing != _facing_right:
			_facing_change_t += delta
			if _facing_change_t >= _lookahead_change_delay:
				_facing_right     = _pending_facing
				_facing_change_t  = 0.0
		else:
			_facing_change_t = 0.0

	# Resolve target offsets (lookahead + fall-look).
	var target_lookahead: float = 0.0
	if _lookahead_enabled:
		target_lookahead = _lookahead_distance if _facing_right else -_lookahead_distance

	var target_fall_y: float = 0.0
	if _look_up_when_falling and parent is CharacterBody2D:
		var body: CharacterBody2D = parent
		if body.velocity.y > 200.0:
			target_fall_y = _look_up_distance

	# Look-down peek: gated by hold-delay so a brief tap of ↓ doesn't twitch
	# the camera. Only runs while grounded so the offset doesn't fight the
	# fall-look path during big drops.
	var target_look_down: float = _resolve_look_down_target(delta, parent)

	# Exponential decay toward the target offsets — frame-rate independent.
	var t_off: float = 1.0 - exp(-_OFFSET_FOLLOW_SPEED * delta)
	_lookahead_offset_x  = lerpf(_lookahead_offset_x,  target_lookahead,  t_off)
	_fall_offset_y       = lerpf(_fall_offset_y,       target_fall_y,     t_off)
	_look_down_offset_y  = lerpf(_look_down_offset_y,  target_look_down,  t_off)

	# Compose the desired camera world position and lerp toward it. With
	# top_level=true this is the actual follow — no parent transform is
	# applied implicitly.
	var target_pos: Vector2 = parent.global_position + Vector2(
		_lookahead_offset_x,
		_PLAYER_VERTICAL_OFFSET + _hud_offset_y + _fall_offset_y + _look_down_offset_y
	)
	var t_pos: float = 1.0 - exp(-_POSITION_FOLLOW_SPEED * delta)
	global_position = global_position.lerp(target_pos, t_pos)

	# All deliberate offsets (HUD reserve, lookahead, fall-look) are baked
	# into global_position above — the Camera2D.offset channel is left
	# untouched so CameraShake can tween it independently.

## Track ↓ hold time and return the camera Y target. Requires:
##   * "look_down" action exists in the InputMap (added in project.godot)
##   * Player grounded — peeking mid-air feels like loss of control
##   * No horizontal input — so ↓ used as fast-fall / movement modifier
##     (planned later) doesn't double-trigger the peek
## Releasing ↓ resets the hold timer immediately so the camera glides back.
func _resolve_look_down_target(delta: float, parent: Node2D) -> float:
	if not InputMap.has_action(&"look_down"):
		return 0.0
	if not Input.is_action_pressed(&"look_down"):
		_look_down_hold_t = 0.0
		return 0.0
	# Skip when player is moving horizontally — they're trying to walk, not peek.
	if Input.is_action_pressed(&"move_left") or Input.is_action_pressed(&"move_right"):
		_look_down_hold_t = 0.0
		return 0.0
	# Skip while airborne so this doesn't fight fall-look.
	var grounded: bool = true
	if parent is CharacterBody2D:
		grounded = (parent as CharacterBody2D).is_on_floor()
	if not grounded:
		_look_down_hold_t = 0.0
		return 0.0
	_look_down_hold_t += delta
	if _look_down_hold_t < LOOK_DOWN_HOLD_DELAY:
		return 0.0
	return LOOK_DOWN_OFFSET

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
