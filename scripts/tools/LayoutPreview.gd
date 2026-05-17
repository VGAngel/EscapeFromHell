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
# Pure per-tier tiles only; transition art used at the boundary (mirrors
# PlaceholderRoom._C1_WALL_TIERS / _C1_WALL_TRANSITION).
const _C1_WALL_TIERS := {
	"white": [
		"res://Assets/OurAssets/walls/circle1/wall_white_00.png",
	],
	"grey": [
		"res://Assets/OurAssets/walls/circle1/wall_greyGreen_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_grey_00.png",
	],
	"dark": [
		"res://Assets/OurAssets/walls/circle1/wall_dark_00.png",
		"res://Assets/OurAssets/walls/circle1/wall_dark_01.png",
		"res://Assets/OurAssets/walls/circle1/wall_dark_02.png",
	],
}
const _C1_WALL_TRANSITION := {
	"grey": "res://Assets/OurAssets/walls/circle1/wall_white_greyGreen.png",
	"dark": "res://Assets/OurAssets/walls/circle1/wall_grey_dark.png",
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
const _CLOUDS_PATH := _DECOR_ROOT + "clouds_no_sky.png"
const _FACADE_TOP_OPEN: float = 1632.0   # mirrors PlaceholderRoom
const _FACADE_START_PATH := "res://Assets/OurAssets/walls/circle1/wall_white_Start.png"
const _FACADE_START_OVERLAP: float = 140.0   # mirrors PlaceholderRoom
var _facade_start_tex: Texture2D = null
var _facade_start_tried: bool = false
var _clouds_tex: Texture2D = null
var _clouds_tried: bool = false
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
	"web": {
		"grey": ["web_01", "web_02"],
		"dark": ["web_01", "web_02"],
	},
}
const _BUSH_TARGET_H:   float = 130.0
const _BUSH_CHANCE:     float = 0.22
const _VINE_TARGET_H:   float = 240.0
const _VINE_CHANCE:     float = 0.22
const _WINDOW_TARGET_H: float = 360.0
const _WINDOW_STEP:     float = 1000.0
const _WINDOW_INSET:    float = 620.0
const _WINDOW_EDGE_FRAC: float = 0.24
const _WINDOW_SKY_INSET_X: float = 0.16
const _WINDOW_SKY_INSET_Y: float = 0.14
const _ARCH_WIDTH_FRAC: float = 0.78
const _WEB_TARGET_H:    float = 230.0
const _WEB_STEP:        float = 1500.0
const _WEB_INSET:       float = 520.0
const _CANDLE_FRAMES:   int   = 5
const _CANDLE_TARGET_H: float = 70.0
const _CANDLE_CHANCE:   float = 0.14


# Static frame load for the preview — runtime animates these as an
# AnimatedSprite2D; here we draw the same start frame the RNG picked.
func _candle_frame_tex(frame_idx: int) -> Texture2D:
	var nm: String = "fire_candle_%02d" % (frame_idx + 1)
	if _decor_tex_cache.has(nm):
		return _decor_tex_cache[nm]
	var path: String = _DECOR_ROOT + nm + ".png"
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_decor_tex_cache[nm] = tex
	return tex

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

	# 1. Sky/parallax behind everything (bright). Mirrors PlaceholderRoom.
	if _has_tiered(_backdrop_textures):
		_draw_textured_backdrop(0.0, ROOM_WIDTH, Color(1, 1, 1, 1))
	else:
		draw_rect(Rect2(0.0, 0.0, ROOM_WIDTH, shaft_height),
			Color(0.10, 0.10, 0.13, 1.0), true)

	# 2. Clouds band at the entrance (over the sky, under the facade).
	if not _clouds_tried:
		_clouds_tried = true
		if ResourceLoader.exists(_CLOUDS_PATH):
			_clouds_tex = load(_CLOUDS_PATH) as Texture2D
	if _clouds_tex and _clouds_tex.get_width() > 0:
		var ctw: float = float(_clouds_tex.get_width())
		var cth: float = float(_clouds_tex.get_height())
		draw_texture_rect(_clouds_tex,
			Rect2(0.0, 0.0, ROOM_WIDTH, ROOM_WIDTH * (cth / ctw)), false)

	# 3. wall_white_Start pinned at top, tiled facade, then window cutouts.
	if _has_tiered(_wall_textures):
		var facade_y: float = _draw_facade_start()
		_draw_textured_facade(facade_y)
		_draw_windows(facade_y)

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

	# Ivy draping off the ledge front (bush art hanging below the slab).
	for i in decor_plats.size():
		if i == altar_idx or d_rng.randf() > _VINE_CHANCE:
			continue
		var ve: Dictionary = decor_plats[i]
		var vpw: float = float(ve.w)
		var vpx: float = float(ve.x) + (d_rng.randf() - 0.5) * maxf(0.0, vpw - 60.0)
		var vpy: float = float(ve.y) + PLATFORM_T * 0.5
		var vt: Texture2D = _decor_tex("bush", _depth_tier(vpy), d_rng)
		if vt and vt.get_height() > 0:
			var vw: float = float(vt.get_width())
			var vh: float = float(vt.get_height())
			var vs: float = _VINE_TARGET_H / vh
			draw_texture_rect(vt, Rect2(
				vpx - vw * 0.5 * vs, vpy, vw * vs, vh * vs), false)

	# Animated ledge candles — runtime is an AnimatedSprite2D; draw the
	# RNG-picked start frame statically so the preview shows placement.
	var c_f0: Texture2D = _candle_frame_tex(0)
	var c_rw: float = float(c_f0.get_width())  if c_f0 else 1.0
	var c_rh: float = float(c_f0.get_height()) if c_f0 else 1.0
	for ci in decor_plats.size():
		if ci == altar_idx or d_rng.randf() > _CANDLE_CHANCE:
			continue
		var ce: Dictionary = decor_plats[ci]
		var cpw: float = float(ce.w)
		var cpx: float = float(ce.x) + (d_rng.randf() - 0.5) * maxf(0.0, cpw - 60.0)
		var cpy: float = float(ce.y) - PLATFORM_T * 0.5
		var cstart: int = d_rng.randi() % _CANDLE_FRAMES
		var ct: Texture2D = _candle_frame_tex(cstart)
		if ct and c_rh > 0.0:
			var cs: float = _CANDLE_TARGET_H / c_rh
			draw_texture_rect(ct, Rect2(
				cpx - c_rw * 0.5 * cs, cpy - c_rh * cs,
				c_rw * cs, c_rh * cs), false)

	# Windows are facade cutouts now — see _draw_windows() (after the
	# facade), not part of the decoration RNG stream.

	# Cobwebs in the wall corners — grey/dark tiers only, sparse.
	var wbl: float = SIDE_WALL_W
	var wbr: float = ROOM_WIDTH - SIDE_WALL_W
	var web_y: float = _WEB_INSET
	var web_left := true
	while web_y < shaft_height - _WEB_INSET:
		var wtier: String = _depth_tier(web_y)
		if wtier != "white" and web_y > WALL_T:
			var et: Texture2D = _decor_tex("web", wtier, d_rng)
			if et and et.get_height() > 0:
				var ew: float = float(et.get_width())
				var eh: float = float(et.get_height())
				var es: float = _WEB_TARGET_H / eh
				var ex: float = wbl if web_left else wbr - ew * es
				draw_texture_rect(et, Rect2(ex, web_y, ew * es, eh * es), false)
		web_left = not web_left
		web_y += _WEB_STEP

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

func _draw_textured_backdrop(x: float, width: float,
		modulate: Color = BACKDROP_DIM) -> void:
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
			modulate)
		y += tex_h


# Entrance piece (wall_white_Start) pinned to the top, full width over
# the sky. Returns the Y where the tiled facade continues. Mirrors
# PlaceholderRoom._draw_facade_start.
func _draw_facade_start() -> float:
	if not _facade_start_tried:
		_facade_start_tried = true
		if ResourceLoader.exists(_FACADE_START_PATH):
			_facade_start_tex = load(_FACADE_START_PATH) as Texture2D
	if _facade_start_tex == null:
		return _FACADE_TOP_OPEN
	var tw: float = float(_facade_start_tex.get_width())
	var th: float = float(_facade_start_tex.get_height())
	if tw <= 0.0 or th <= 0.0:
		return _FACADE_TOP_OPEN
	draw_texture_rect_region(
		_facade_start_tex,
		Rect2(0.0, 0.0, ROOM_WIDTH, th),
		Rect2(0.0, 0.0, tw, th))
	return maxf(0.0, th - _FACADE_START_OVERLAP)


var _wall_transition_cache: Dictionary = {}

func _facade_transition_tex(tier: String) -> Texture2D:
	if _wall_transition_cache.has(tier):
		return _wall_transition_cache[tier]
	var path: String = String(_C1_WALL_TRANSITION.get(tier, ""))
	var tex: Texture2D = null
	if path != "" and ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_wall_transition_cache[tier] = tex
	return tex


# Full-width tiered stone facade from `start_y` to the floor. Mirrors
# PlaceholderRoom._draw_textured_facade (same seed/loop/transition).
func _draw_textured_facade(start_y: float) -> void:
	if not _has_tiered(_wall_textures):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("facade_%d" % level_id)
	var y: float = maxf(0.0, start_y)
	var prev_tier: String = ""
	while y < shaft_height:
		var tier: String = _depth_tier(y)
		var tex: Texture2D = null
		if prev_tier != "" and tier != prev_tier:
			tex = _facade_transition_tex(tier)
		if tex == null:
			var pool: Array = _tier_pool(_wall_textures, tier)
			if pool.is_empty():
				break
			tex = pool[rng.randi() % pool.size()]
		prev_tier = tier
		var tex_w: float = float(tex.get_width())
		var tex_h: float = float(tex.get_height())
		var section_h: float = minf(tex_h, shaft_height - y)
		var slice_w: float = minf(ROOM_WIDTH, tex_w)
		var x_off: float = rng.randf() * maxf(0.0, tex_w - slice_w)
		draw_texture_rect_region(
			tex,
			Rect2(0.0, y, ROOM_WIDTH, section_h),
			Rect2(x_off, 0.0, slice_w, section_h))
		y += tex_h


# Window cutouts in the facade. Mirrors PlaceholderRoom._draw_windows
# (same seed/loop). SafeArea is editor-irrelevant → sa_top = 0.
func _draw_windows(start_y: float) -> void:
	if not _has_tiered(_wall_textures):
		return
	var sa_top: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("window_%d" % level_id)
	var cx_l: float = ROOM_WIDTH * _WINDOW_EDGE_FRAC
	var cx_r: float = ROOM_WIDTH - ROOM_WIDTH * _WINDOW_EDGE_FRAC
	var y: float = maxf(start_y, _WINDOW_INSET) + _WINDOW_STEP * 0.5
	var on_left := true
	while y < shaft_height - _WINDOW_INSET:
		if y > start_y and y > WALL_T + sa_top:
			var tier: String = _depth_tier(y)
			var frame: Texture2D = _decor_tex("window", tier, rng)
			if frame and frame.get_height() > 0:
				var fw: float = float(frame.get_width())
				var fh: float = float(frame.get_height())
				var s: float = _WINDOW_TARGET_H / fh
				var w: float = fw * s
				var h: float = fh * s
				var rx: float = (cx_l if on_left else cx_r) - w * 0.5
				var ry: float = y - h * 0.5
				var sky_pool: Array = _tier_pool(_backdrop_textures, tier)
				if not sky_pool.is_empty():
					var sky: Texture2D = sky_pool[rng.randi() % sky_pool.size()]
					var ix: float = w * _WINDOW_SKY_INSET_X
					var iy: float = h * _WINDOW_SKY_INSET_Y
					draw_texture_rect(sky,
						Rect2(rx + ix, ry + iy, w - ix * 2.0, h - iy * 2.0), false)
				draw_texture_rect(frame, Rect2(rx, ry, w, h), false)
		on_left = not on_left
		y += _WINDOW_STEP
