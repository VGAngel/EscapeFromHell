@tool
extends Node2D

# Editor-only preview helper for vertical layout scenes.
#
# Draws the shaft silhouette (walls, altar zone, safe spawn area) so the
# designer can see where platforms sit relative to the shaft when editing
# scenes/rooms/vertical_layouts/level_NNN/layout_K.tscn.
#
# Skipped at runtime entirely — PlaceholderRoom._populate_vert_layout_from_scene
# only reads StaticBody2D / AnimatableBody2D children, so a plain Node2D with
# this script is invisible to the spawn pipeline.
#
# Generator (scripts/tools/gen_level_scenes.py) seeds shaft_height per level
# from ROOM_COUNT_BY_IDX. Designer can also tweak the value directly in the
# inspector to preview different shaft sizes.

const ROOM_WIDTH:        float = 1080.0
const WALL_T:            float = 30.0
const SIDE_WALL_W:       float = 60.0
const ALTAR_TARGET_H:    float = 220.0
const ALTAR_CLEARANCE:   float = 60.0   # buffer below altar top before ceiling

@export var shaft_height: float = 3840.0 :
	set(v):
		shaft_height = v
		queue_redraw()

# Visual style — translucent so platforms underneath stay visible.
const COLOR_WALL:       Color = Color(0.18, 0.18, 0.22, 0.55)
const COLOR_BACKDROP:   Color = Color(0.10, 0.10, 0.13, 0.30)
const COLOR_ALTAR_ZONE: Color = Color(1.00, 0.85, 0.30, 0.18)
const COLOR_EXIT_ZONE:  Color = Color(0.30, 0.85, 1.00, 0.18)
const COLOR_OUTLINE:    Color = Color(0.85, 0.85, 0.85, 0.90)


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
	# Topmost platform must sit at y >= WALL_T + ALTAR_TARGET_H + ALTAR_CLEARANCE
	# (= 310 px) for the 220 px altar sprite to render without clipping the
	# ceiling. Anything inside this banner is the "no platforms here" zone.
	var altar_zone_h: float = ALTAR_TARGET_H + ALTAR_CLEARANCE
	draw_rect(Rect2(SIDE_WALL_W, WALL_T,
		ROOM_WIDTH - SIDE_WALL_W * 2.0, altar_zone_h),
		COLOR_ALTAR_ZONE, true)

	# Exit zone — banner at the bottom marking where the portal will spawn.
	var exit_zone_h: float = 200.0
	draw_rect(Rect2(SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h,
		ROOM_WIDTH - SIDE_WALL_W * 2.0, exit_zone_h),
		COLOR_EXIT_ZONE, true)

	# Outlines so zones read clearly even on top of dark platform sprites.
	draw_rect(Rect2(0, 0, ROOM_WIDTH, shaft_height), COLOR_OUTLINE, false, 2.0)
	draw_line(Vector2(SIDE_WALL_W, WALL_T + altar_zone_h),
		Vector2(ROOM_WIDTH - SIDE_WALL_W, WALL_T + altar_zone_h),
		Color(1.0, 0.85, 0.30, 0.6), 1.5)
	draw_line(Vector2(SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h),
		Vector2(ROOM_WIDTH - SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h),
		Color(0.30, 0.85, 1.00, 0.6), 1.5)
