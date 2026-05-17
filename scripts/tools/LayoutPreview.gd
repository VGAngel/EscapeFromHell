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

# Mirrors PlaceholderRoom._C1_WALL_TIERS / _C1_BACKDROP_TIERS and its
# depth-tier picker so the editor preview matches the runtime render
# byte-for-byte. Keep both files in sync when the tiered art changes.
const SCREEN_PX: float = 1920.0
const _DEPTH_TIERS: Array[String] = ["white", "grey", "dark"]
const _C1_WALL_TIERS := {
	"white": [
		"res://Assets/OurAssets/walls/circle1/wall_white_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_white_Start.png",
		"res://Assets/OurAssets/walls/circle1/wall_white_greyGreen.png",
	],
	"grey": [
		"res://Assets/OurAssets/walls/circle1/wall_grey_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_grey_dark.png",
		"res://Assets/OurAssets/walls/circle1/wall_greyGreen_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_greyGreen_grey.png",
	],
	"dark": [
		"res://Assets/OurAssets/walls/circle1/wall_dark_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_dark_01.png",
		"res://Assets/OurAssets/walls/circle1/wall_dark_02.png",
	],
}
const _C1_BACKDROP_TIERS := {
	"white": ["res://Assets/OurAssets/walls/circle1/background_white.png"],
	"grey":  ["res://Assets/OurAssets/walls/circle1/background_grey.png"],
	"dark":  ["res://Assets/OurAssets/walls/circle1/background_dark.png"],
}
const WALL_TEXTURES_BY_TILESET := {
	"tileset1":  _C1_WALL_TIERS,
	"tileset12": _C1_WALL_TIERS,
}
const BACKDROP_TEXTURES_BY_TILESET := {
	"tileset1":  _C1_BACKDROP_TIERS,
	"tileset12": _C1_BACKDROP_TIERS,
}
const ALTAR_TEXTURE_PATH: String = "res://Assets/OurAssets/altar_main.png"
const BACKDROP_DIM: Color = Color(0.75, 0.75, 0.75, 1.0)

# Mirrors PlaceholderRoom._C1_DECOR / _spawn_decorations so the editor
# preview shows the same bushes/windows/arch the runtime spawns. Keep the
# RNG sequence identical (seed, per-platform draw order) when changing.
const _DECOR_ROOT := "res://Assets/OurAssets/decor/circle1/"
const _C1_DECOR := {
	"bush": {
		"white": [
			"bush_green_01", "bush_green_02", "bush_green_03",
			"bush_greenFlower_01", "bush_greenFlower_02", "bush_greenFlower_03",
			"bush_orange_01", "bush_orange_02", "bush_orange_03",
		],
		"grey": [
			"bush_orange_01", "bush_orange_02", "bush_orange_03",
			"bush_dark_01", "bush_dark_02", "bush_dark_03",
		],
		"dark": ["bush_dark_01", "bush_dark_02", "bush_dark_03"],
	},
	"window": {
		"white": ["window_white"],
		"grey":  ["window_grey"],
		"dark":  ["window_dark", "window_dark_broken"],
	},
	"arch": {
		"white": ["arch_entr"],
		"grey":  ["arch_entr_grey"],
		"dark":  ["arch_entr_dark"],
	},
}
const _BUSH_TARGET_H:   float = 130.0
const _BUSH_CHANCE:     float = 0.45
const _WINDOW_TARGET_H: float = 360.0
const _WINDOW_STEP:     float = 1000.0
const _WINDOW_INSET:    float = 620.0
const _ARCH_WIDTH_FRAC: float = 0.78

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
# tier (white/grey/dark) → Array[Texture2D].
var _backdrop_textures: Dictionary = {}
var _wall_textures:     Dictionary = {}
var _altar_texture:     Texture2D = null
var _decor_tex_cache:   Dictionary = {}   # texture name → Texture2D | null
var _textures_loaded_for: String = ""


# Mirrors PlaceholderRoom._decor_tex — same fallback + RNG consumption so
# the preview's bush/window/arch pick matches the runtime.
func _decor_tex(kind: String, tier: String, rng: RandomNumberGenerator) -> Texture2D:
	var tiers: Dictionary = _C1_DECOR.get(kind, {})
	var names: Array = tiers.get(tier, [])
	if names.is_empty():
		for t: String in _DEPTH_TIERS:
			names = tiers.get(t, [])
			if not names.is_empty():
				break
	if names.is_empty():
		return null
	var nm: String = String(names[rng.randi() % names.size()])
	if _decor_tex_cache.has(nm):
		return _decor_tex_cache[nm]
	var path: String = _DECOR_ROOT + nm + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_decor_tex_cache[nm] = tex
	return tex


# Screen index (1-based) from the top → depth tier. Mirrors
# PlaceholderRoom._depth_tier (absolute depth: 1-3 white, 4-6 grey, 7+ dark).
func _depth_tier(y: float) -> String:
	var screen_idx: int = int(y / SCREEN_PX) + 1
	if screen_idx <= 3:
		return "white"
	if screen_idx <= 6:
		return "grey"
	return "dark"


func _load_tiered(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tier: String in _DEPTH_TIERS:
		var arr: Array = []
		for path: String in src.get(tier, []):
			if ResourceLoader.exists(path):
				var t := load(path) as Texture2D
				if t: arr.append(t)
		out[tier] = arr
	return out


func _tier_pool(cache: Dictionary, tier: String) -> Array:
	var pool: Array = cache.get(tier, [])
	if not pool.is_empty():
		return pool
	for t: String in _DEPTH_TIERS:
		var alt: Array = cache.get(t, [])
		if not alt.is_empty():
			return alt
	return []


func _has_tiered(cache: Dictionary) -> bool:
	for t: String in _DEPTH_TIERS:
		if not (cache.get(t, []) as Array).is_empty():
			return true
	return false


func _ensure_textures_loaded() -> void:
	if _textures_loaded_for == tileset:
		return
	_textures_loaded_for = tileset
	_backdrop_textures = _load_tiered(BACKDROP_TEXTURES_BY_TILESET.get(tileset, {}))
	_wall_textures = _load_tiered(WALL_TEXTURES_BY_TILESET.get(tileset, {}))
	if _altar_texture == null and ResourceLoader.exists(ALTAR_TEXTURE_PATH):
		_altar_texture = load(ALTAR_TEXTURE_PATH) as Texture2D


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	_ensure_textures_loaded()

	# 1. Backdrop — textured if available, flat dark fill otherwise.
	if _has_tiered(_backdrop_textures):
		_draw_textured_backdrop(SIDE_WALL_W, ROOM_WIDTH - SIDE_WALL_W * 2.0)
	else:
		draw_rect(Rect2(SIDE_WALL_W, WALL_T,
			ROOM_WIDTH - SIDE_WALL_W * 2.0,
			shaft_height - WALL_T * 2.0),
			Color(0.10, 0.10, 0.13, 1.0), true)

	# 2. Side walls — textured if available, flat dark otherwise.
	if _has_tiered(_wall_textures):
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

	# 8. Decorations — mirrors PlaceholderRoom._spawn_decorations (same
	#    seed + per-platform RNG order so the preview matches the runtime).
	var decor_plats: Array = []
	for p_v2: Variant in plats:
		if p_v2 is Dictionary:
			var pd: Dictionary = p_v2
			decor_plats.append({
				"x": float(pd.get("x", 0.0)),
				"y": float(pd.get("y", 0.0)),
				"w": float(pd.get("w", 220.0)),
			})
	if decor_plats.is_empty():
		return
	# Match runtime _vert_layout ordering (descending Y, bottom first).
	decor_plats.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.y) > float(b.y))
	var d_rng := RandomNumberGenerator.new()
	d_rng.seed = hash("decor_%d" % level_id)
	var altar_idx: int = 0
	for i in decor_plats.size():
		if float(decor_plats[i].y) < float(decor_plats[altar_idx].y):
			altar_idx = i

	# Bushes on platform tops.
	for i in decor_plats.size():
		if i == altar_idx or d_rng.randf() > _BUSH_CHANCE:
			continue
		var e: Dictionary = decor_plats[i]
		var pw: float = float(e.w)
		var px: float = float(e.x) + (d_rng.randf() - 0.5) * maxf(0.0, pw - 60.0)
		var py: float = float(e.y) - PLATFORM_T * 0.5
		var bt: Texture2D = _decor_tex("bush", _depth_tier(py), d_rng)
		if bt and bt.get_height() > 0:
			var bw: float = float(bt.get_width())
			var bh: float = float(bt.get_height())
			var bs: float = _BUSH_TARGET_H / bh
			draw_texture_rect(bt, Rect2(
				px - bw * 0.5 * bs, py - bh * bs, bw * bs, bh * bs), false)

	# Windows down both side walls.
	var wl: float = SIDE_WALL_W + 30.0
	var wr: float = ROOM_WIDTH - SIDE_WALL_W - 30.0
	var wy: float = _WINDOW_INSET
	var on_left := true
	while wy < shaft_height - _WINDOW_INSET:
		if wy > WALL_T:
			var wt: Texture2D = _decor_tex("window", _depth_tier(wy), d_rng)
			if wt and wt.get_height() > 0:
				var ww: float = float(wt.get_width())
				var wh: float = float(wt.get_height())
				var ws: float = _WINDOW_TARGET_H / wh
				var wx: float = wl if on_left else wr
				draw_texture_rect(wt, Rect2(
					wx - ww * 0.5 * ws, wy - wh * 0.5 * ws,
					ww * ws, wh * ws), false)
		on_left = not on_left
		wy += _WINDOW_STEP

	# Single entrance arch at the top.
	var arch_y: float = WALL_T + 12.0
	var at: Texture2D = _decor_tex("arch", _depth_tier(arch_y), d_rng)
	if at and at.get_width() > 0:
		var aw: float = float(at.get_width())
		var ah: float = float(at.get_height())
		var asf: float = (ROOM_WIDTH * _ARCH_WIDTH_FRAC) / aw
		draw_texture_rect(at, Rect2(
			ROOM_WIDTH * 0.5 - aw * 0.5 * asf, arch_y,
			aw * asf, ah * asf), false)


# ── Texture drawing — copied from PlaceholderRoom so the editor render matches
# the runtime byte-for-byte (same seeds, same loop, same modulate).

func _draw_textured_backdrop(x: float, width: float) -> void:
	if not _has_tiered(_backdrop_textures):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("backdrop_%d" % level_id)
	var y: float = 0.0
	while y < shaft_height:
		var pool: Array = _tier_pool(_backdrop_textures, _depth_tier(y))
		if pool.is_empty():
			break
		var tex: Texture2D = pool[rng.randi() % pool.size()]
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
	if not _has_tiered(_wall_textures):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("wall_%d_%s" % [level_id, seed_tag])
	var y: float = 0.0
	while y < shaft_height:
		var pool: Array = _tier_pool(_wall_textures, _depth_tier(y))
		if pool.is_empty():
			break
		var tex: Texture2D = pool[rng.randi() % pool.size()]
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
