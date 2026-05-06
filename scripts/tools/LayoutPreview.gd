@tool
extends Node2D

# Editor-only preview helper for vertical layout decoration scenes.
#
# Renders the same backdrop + wall textures the runtime PlaceholderRoom uses,
# the altar sprite on the topmost platform, and platform footprints loaded
# from vertical_layouts.json — so opening a level_NNN.tscn shows the same
# picture the player sees, minus runtime-only effects (atmospheric particles,
# dynamic lighting, enemies). Lets the designer place decorations against
# real visual context instead of placeholder rectangles.
#
# Skipped at runtime entirely (returns from _draw on Engine.is_editor_hint).

const ROOM_WIDTH:        float = 1080.0
const WALL_T:            float = 30.0
const SIDE_WALL_W:       float = 60.0
const PLATFORM_T:        float = 30.0
const ALTAR_TARGET_H:    float = 220.0
const ALTAR_CLEARANCE:   float = 60.0
const VERT_LAYOUTS_JSON: String = "res://vertical_layouts.json"

# Mirrors PlaceholderRoom.WALL/BACKDROP_TEXTURES_BY_TILESET. tileset1 is the
# only one shipping art today; designer can extend by adding entries there
# and matching them here when new circles are themed.
const WALL_TEXTURES_BY_TILESET := {
	"tileset1": [
		"res://Assets/OurAssets/walls/circle1/base_a.png",
		"res://Assets/OurAssets/walls/circle1/base_b.png",
		"res://Assets/OurAssets/walls/circle1/base_c.png",
		"res://Assets/OurAssets/walls/circle1/base_d.png",
	],
}
const BACKDROP_TEXTURES_BY_TILESET := {
	"tileset1": [
		"res://Assets/OurAssets/walls/circle1/backdrop_a.png",
		"res://Assets/OurAssets/walls/circle1/backdrop_b.png",
		"res://Assets/OurAssets/walls/circle1/backdrop_c.png",
	],
}
const ALTAR_TEXTURE_PATH: String = "res://Assets/OurAssets/altar_main.png"
const BACKDROP_DIM: Color = Color(0.75, 0.75, 0.75, 1.0)

@export var shaft_height: float = 3840.0 :
	set(v):
		shaft_height = v
		queue_redraw()

@export var level_id: int = 0 :
	set(v):
		level_id = v
		queue_redraw()

## Tileset id — drives which wall + backdrop textures get drawn. Defaults to
## "tileset1" because that's what every shipped circle currently uses.
@export var tileset: String = "tileset1" :
	set(v):
		tileset = v
		queue_redraw()

## Show the altar / exit safe-zone overlays on top of the textured render.
## Helpful while placing decorations; can be turned off for a cleaner look.
@export var show_zones: bool = true :
	set(v):
		show_zones = v
		queue_redraw()

# Per-type fill colours for platform rectangles (mirrors
# placeholder_assets_config.json). Alpha kept around 0.85 so designer's
# overlaid sprites remain visible underneath.
const PLATFORM_COLORS: Dictionary = {
	"stone":             Color(0.40, 0.40, 0.40, 0.85),
	"one_way":           Color(0.53, 0.53, 0.53, 0.70),
	"moving_horizontal": Color(0.27, 0.53, 1.00, 0.85),
	"moving_vertical":   Color(0.13, 0.40, 0.87, 0.85),
	"crumbling":         Color(0.67, 0.40, 0.20, 0.85),
	"falling":           Color(0.80, 0.33, 0.00, 0.85),
	"ash":               Color(0.73, 0.67, 0.60, 0.85),
	"ice":               Color(0.67, 0.87, 1.00, 0.85),
	"mud":               Color(0.40, 0.27, 0.13, 0.90),
	"lava_edge":         Color(1.00, 0.27, 0.00, 0.90),
	"sin_platform":      Color(0.53, 0.00, 0.20, 0.90),
	"conveyor":          Color(1.00, 0.80, 0.00, 0.85),
	"bounce":            Color(0.27, 0.80, 0.27, 0.85),
	"chain":             Color(0.67, 0.67, 0.27, 0.85),
	"pressure_plate":    Color(0.00, 0.80, 0.80, 0.85),
	"illusory":          Color(0.67, 0.40, 1.00, 0.55),
	"faith":             Color(1.00, 1.00, 0.67, 0.85),
	"soul_bridge":       Color(0.40, 0.67, 1.00, 0.55),
}
const PLATFORM_COLOR_FALLBACK: Color = Color(0.55, 0.55, 0.60, 0.85)
const COLOR_PLAT_EDGE:  Color = Color(1.00, 1.00, 1.00, 0.50)
const COLOR_FLOOR_FILL: Color = Color(0.10, 0.07, 0.08, 1.00)
const COLOR_OUTLINE:    Color = Color(0.85, 0.85, 0.85, 0.30)
const COLOR_ALTAR_ZONE: Color = Color(1.00, 0.85, 0.30, 0.10)
const COLOR_EXIT_ZONE:  Color = Color(0.30, 0.85, 1.00, 0.10)

# JSON cache invalidates by file mtime so platform rectangles refresh as the
# designer saves vertical_layouts.json — no scene reopen needed.
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


# Texture caches — load once per node; cheap because Godot dedupes loads.
var _backdrop_textures: Array = []
var _wall_textures:     Array = []
var _altar_texture:     Texture2D = null
var _textures_loaded_for: String = ""


func _ensure_textures_loaded() -> void:
	if _textures_loaded_for == tileset:
		return
	_textures_loaded_for = tileset
	_backdrop_textures.clear()
	_wall_textures.clear()
	for path: String in BACKDROP_TEXTURES_BY_TILESET.get(tileset, []):
		if ResourceLoader.exists(path):
			var t := load(path) as Texture2D
			if t: _backdrop_textures.append(t)
	for path: String in WALL_TEXTURES_BY_TILESET.get(tileset, []):
		if ResourceLoader.exists(path):
			var t := load(path) as Texture2D
			if t: _wall_textures.append(t)
	if _altar_texture == null and ResourceLoader.exists(ALTAR_TEXTURE_PATH):
		_altar_texture = load(ALTAR_TEXTURE_PATH) as Texture2D


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_textures_loaded()

	# 1. Backdrop — textured if available, flat dark fill otherwise.
	if not _backdrop_textures.is_empty():
		_draw_textured_backdrop(SIDE_WALL_W, ROOM_WIDTH - SIDE_WALL_W * 2.0)
	else:
		draw_rect(Rect2(SIDE_WALL_W, WALL_T,
			ROOM_WIDTH - SIDE_WALL_W * 2.0,
			shaft_height - WALL_T * 2.0),
			Color(0.10, 0.10, 0.13, 1.0), true)

	# 2. Side walls — textured if available, flat dark otherwise.
	if not _wall_textures.is_empty():
		_draw_textured_side_wall(0.0, SIDE_WALL_W, "L")
		_draw_textured_side_wall(ROOM_WIDTH - SIDE_WALL_W, SIDE_WALL_W, "R")
	else:
		draw_rect(Rect2(0, 0, SIDE_WALL_W, shaft_height),
			Color(0.18, 0.18, 0.22, 1.0), true)
		draw_rect(Rect2(ROOM_WIDTH - SIDE_WALL_W, 0, SIDE_WALL_W, shaft_height),
			Color(0.18, 0.18, 0.22, 1.0), true)

	# 3. Top + bottom walls — flat dark fills (runtime doesn't texture these).
	draw_rect(Rect2(0, 0, ROOM_WIDTH, WALL_T), COLOR_FLOOR_FILL, true)
	draw_rect(Rect2(0, shaft_height - WALL_T, ROOM_WIDTH, WALL_T),
		COLOR_FLOOR_FILL, true)

	# 4. Optional safe-zone overlays so designer sees where altar/exit land.
	if show_zones:
		var altar_zone_h: float = ALTAR_TARGET_H + ALTAR_CLEARANCE
		draw_rect(Rect2(SIDE_WALL_W, WALL_T,
			ROOM_WIDTH - SIDE_WALL_W * 2.0, altar_zone_h),
			COLOR_ALTAR_ZONE, true)
		var exit_zone_h: float = 200.0
		draw_rect(Rect2(SIDE_WALL_W, shaft_height - WALL_T - exit_zone_h,
			ROOM_WIDTH - SIDE_WALL_W * 2.0, exit_zone_h),
			COLOR_EXIT_ZONE, true)

	# 5. Outline so the shaft bounds stay readable.
	draw_rect(Rect2(0, 0, ROOM_WIDTH, shaft_height), COLOR_OUTLINE, false, 2.0)

	# 6. Platforms from JSON.
	if level_id <= 0:
		return
	var layouts: Dictionary = _get_layouts()
	var key: String = str(level_id)
	if not layouts.has(key):
		return
	var plats: Variant = layouts[key]
	if not (plats is Array):
		return
	# Find topmost platform (smallest y) so we can put the altar there.
	var top_x: float = ROOM_WIDTH * 0.5
	var top_y: float = -1.0
	for p_v: Variant in plats:
		if not (p_v is Dictionary):
			continue
		var p: Dictionary = p_v
		var x: float = float(p.get("x", 0.0))
		var y: float = float(p.get("y", 0.0))
		var w: float = float(p.get("w", 220.0))
		var t: String = String(p.get("t", "stone"))
		var rect := Rect2(x - w * 0.5, y - PLATFORM_T * 0.5, w, PLATFORM_T)
		var fill: Color = PLATFORM_COLORS.get(t, PLATFORM_COLOR_FALLBACK)
		draw_rect(rect, fill, true)
		draw_rect(rect, COLOR_PLAT_EDGE, false, 1.5)
		if top_y < 0.0 or y < top_y:
			top_y = y
			top_x = x

	# 7. Altar sprite on the topmost platform — same anchor maths the runtime
	# PlaceholderRoom._spawn_altar uses: position is bottom-center, sprite
	# offset is (-tex_w/2, -tex_h) and scale = ALTAR_TARGET_H / tex_h.
	if _altar_texture and top_y >= 0.0:
		var tex_w: float = float(_altar_texture.get_width())
		var tex_h: float = float(_altar_texture.get_height())
		if tex_h > 0.0:
			var s: float = ALTAR_TARGET_H / tex_h
			var anchor_y: float = top_y - PLATFORM_T * 0.5
			var dst := Rect2(
				top_x - tex_w * 0.5 * s,
				anchor_y - tex_h * s,
				tex_w * s, tex_h * s)
			draw_texture_rect(_altar_texture, dst, false)


# ── Texture drawing — copied from PlaceholderRoom so the editor render matches
# the runtime byte-for-byte (same seeds, same loop, same modulate).

func _draw_textured_backdrop(x: float, width: float) -> void:
	if _backdrop_textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("backdrop_%d" % level_id)
	var n: int = _backdrop_textures.size()
	var y: float = 0.0
	while y < shaft_height:
		var tex: Texture2D = _backdrop_textures[rng.randi() % n]
		var tex_w: float = float(tex.get_width())
		var tex_h: float = float(tex.get_height())
		var section_h: float = minf(tex_h, shaft_height - y)
		draw_texture_rect_region(
			tex,
			Rect2(x, y, width, section_h),
			Rect2(0.0, 0.0, tex_w, section_h),
			BACKDROP_DIM)
		y += tex_h


func _draw_textured_side_wall(x: float, width: float, seed_tag: String) -> void:
	if _wall_textures.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("wall_%d_%s" % [level_id, seed_tag])
	var n: int = _wall_textures.size()
	var y: float = 0.0
	while y < shaft_height:
		var tex: Texture2D = _wall_textures[rng.randi() % n]
		var tex_w: float = float(tex.get_width())
		var tex_h: float = float(tex.get_height())
		var slice_w: float = minf(width, tex_w)
		var x_off: float = rng.randf() * maxf(0.0, tex_w - slice_w)
		var section_h: float = minf(tex_h, shaft_height - y)
		draw_texture_rect_region(
			tex,
			Rect2(x, y, width, section_h),
			Rect2(x_off, 0.0, slice_w, section_h))
		y += tex_h
