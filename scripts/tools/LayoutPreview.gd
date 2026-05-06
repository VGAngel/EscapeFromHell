@tool
extends Node2D

# Editor-only preview helper for vertical layout decoration scenes.
#
# Draws the shaft silhouette (walls, altar zone, safe spawn area) AND the
# platforms loaded from vertical_layouts.json so the designer sees exactly
# what the runtime will spawn — both the shaft context and the platform
# positions — while editing scenes/rooms/vertical_layouts/level_NNN.tscn.
#
# Skipped at runtime entirely (returns from _draw on Engine.is_editor_hint).
# PlaceholderRoom adds this Node2D as a child of the shaft room but the
# platform-spawn pipeline never reads from it — platforms come from the JSON
# directly via _populate_vert_layout_from_data.

const ROOM_WIDTH:        float = 1080.0
const WALL_T:            float = 30.0
const SIDE_WALL_W:       float = 60.0
const PLATFORM_T:        float = 30.0
const ALTAR_TARGET_H:    float = 220.0
const ALTAR_CLEARANCE:   float = 60.0
const VERT_LAYOUTS_JSON: String = "res://vertical_layouts.json"

@export var shaft_height: float = 3840.0 :
	set(v):
		shaft_height = v
		queue_redraw()

## Set by the generator per level — drives which platform list is drawn from
## vertical_layouts.json. Leave at 0 to preview shaft outline only.
@export var level_id: int = 0 :
	set(v):
		level_id = v
		queue_redraw()

# Visual style — translucent so designer's own decoration sprites stay visible.
const COLOR_WALL:       Color = Color(0.18, 0.18, 0.22, 0.55)
const COLOR_BACKDROP:   Color = Color(0.10, 0.10, 0.13, 0.30)
const COLOR_ALTAR_ZONE: Color = Color(1.00, 0.85, 0.30, 0.18)
const COLOR_EXIT_ZONE:  Color = Color(0.30, 0.85, 1.00, 0.18)
const COLOR_OUTLINE:    Color = Color(0.85, 0.85, 0.85, 0.90)
const COLOR_PLATFORM:   Color = Color(0.55, 0.55, 0.60, 0.85)
const COLOR_PLAT_EDGE:  Color = Color(1.00, 1.00, 1.00, 0.50)
const COLOR_PLAT_LABEL: Color = Color(1.00, 1.00, 1.00, 0.65)

# Cached parse so opening a deep scene tree doesn't re-read the JSON for
# every LayoutPreview redraw. Keyed by file modify time so the cache busts
# when the designer edits vertical_layouts.json.
static var _json_cache:        Dictionary = {}
static var _json_cache_mtime:  int        = -1


static func _get_layouts() -> Dictionary:
	var mtime: int = -1
	if FileAccess.file_exists(VERT_LAYOUTS_JSON):
		mtime = FileAccess.get_modified_time(VERT_LAYOUTS_JSON)
	if mtime == _json_cache_mtime:
		return _json_cache
	_json_cache_mtime = mtime
	_json_cache = {}
	if not FileAccess.file_exists(VERT_LAYOUTS_JSON):
		return _json_cache
	var f := FileAccess.open(VERT_LAYOUTS_JSON, FileAccess.READ)
	if not f:
		return _json_cache
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		var lvls: Variant = (parsed as Dictionary).get("levels", null)
		if lvls is Dictionary:
			_json_cache = lvls
	return _json_cache


func _draw() -> void:
	if not Engine.is_editor_hint():
		return

	# Backdrop fill — entire interior of the shaft.
	draw_rect(Rect2(SIDE_WALL_W, WALL_T,
		ROOM_WIDTH - SIDE_WALL_W * 2.0,
		shaft_height - WALL_T * 2.0), COLOR_BACKDROP, true)

	# Walls — top, bottom, left, right.
	draw_rect(Rect2(0, 0, ROOM_WIDTH, WALL_T), COLOR_WALL, true)
	draw_rect(Rect2(0, shaft_height - WALL_T, ROOM_WIDTH, WALL_T), COLOR_WALL, true)
	draw_rect(Rect2(0, 0, SIDE_WALL_W, shaft_height), COLOR_WALL, true)
	draw_rect(Rect2(ROOM_WIDTH - SIDE_WALL_W, 0, SIDE_WALL_W, shaft_height),
		COLOR_WALL, true)

	# Altar zone — banner across the top showing the safe altar area.
	var altar_zone_h: float = ALTAR_TARGET_H + ALTAR_CLEARANCE
	draw_rect(Rect2(SIDE_WALL_W, WALL_T,
		ROOM_WIDTH - SIDE_WALL_W * 2.0, altar_zone_h),
		COLOR_ALTAR_ZONE, true)

	# Exit zone — banner at the bottom marking where the portal will spawn.
	var exit_zone_h: float = 200.0
	draw_rect(Rect2(SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h,
		ROOM_WIDTH - SIDE_WALL_W * 2.0, exit_zone_h),
		COLOR_EXIT_ZONE, true)

	# Outlines so zones read clearly.
	draw_rect(Rect2(0, 0, ROOM_WIDTH, shaft_height), COLOR_OUTLINE, false, 2.0)
	draw_line(Vector2(SIDE_WALL_W, WALL_T + altar_zone_h),
		Vector2(ROOM_WIDTH - SIDE_WALL_W, WALL_T + altar_zone_h),
		Color(1.0, 0.85, 0.30, 0.6), 1.5)
	draw_line(Vector2(SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h),
		Vector2(ROOM_WIDTH - SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h),
		Color(0.30, 0.85, 1.00, 0.6), 1.5)

	# Platforms — read from JSON for this level_id and draw their footprints
	# so the designer can place decorations relative to them.
	if level_id <= 0:
		return
	var layouts: Dictionary = _get_layouts()
	var key: String = str(level_id)
	if not layouts.has(key):
		return
	var plats: Variant = layouts[key]
	if not (plats is Array):
		return
	for p_v: Variant in plats:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v
		var x: float = float(p.get("x", 0.0))
		var y: float = float(p.get("y", 0.0))
		var w: float = float(p.get("w", 220.0))
		# In runtime, position is the platform CENTER. Mirror that so the
		# preview rectangles align with what the player sees.
		var rect := Rect2(x - w * 0.5, y - PLATFORM_T * 0.5, w, PLATFORM_T)
		draw_rect(rect, COLOR_PLATFORM, true)
		draw_rect(rect, COLOR_PLAT_EDGE, false, 1.5)
