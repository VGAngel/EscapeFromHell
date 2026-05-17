@tool
extends Node2D

## Малює кольоровий прямокутник як placeholder для будь-якого об'єкта.
## Використовується поки немає реальних asset'ів.

@export var platform_type: String = "stone"
@export var custom_color: Color = Color.TRANSPARENT
@export var custom_size: Vector2 = Vector2.ZERO
@export var show_label: bool = true
@export var opacity: float = 1.0

const CONFIG_PATH := "res://placeholder_assets_config.json"

# Textured variants per platform type. When the array isn't empty, the visual
# picks one variant (seeded by position so each platform looks consistent
# across re-renders) and draws it scaled to the platform width while keeping
# the source aspect ratio — the visual extends below the 30 px collision so
# platforms read as solid blocks with rocky undersides.
const PLATFORM_TEXTURES: Dictionary = {
	"stone": [
		"res://Assets/OurAssets/platforms/circle1/island_01.png",
		"res://Assets/OurAssets/platforms/circle1/island_01a.png",
		"res://Assets/OurAssets/platforms/circle1/island_02.png",
		"res://Assets/OurAssets/platforms/circle1/island_02a.png",
	],
	"crumbling": [
		"res://Assets/OurAssets/platforms/circle1/crumbling_a.png",
	],
}

# Lazy texture cache shared across instances (script-level).
static var _tex_cache: Dictionary = {}

var _color: Color
var _size: Vector2
var _label: String = ""
var _config: Dictionary = {}

func _ready() -> void:
	_load_config()
	_apply_type()
	queue_redraw()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK:
		_config = json.get_data()

func _apply_type() -> void:
	var all_types: Dictionary = {}
	for category: String in ["platforms", "souls", "enemies", "traps", "bonuses"]:
		if _config.has(category):
			all_types.merge(_config[category])

	if all_types.has(platform_type):
		var data: Dictionary = all_types[platform_type]
		_color = Color(data.get("color", "#FF00FF"))
		_color.a = data.get("opacity", opacity)
		_label = data.get("label", platform_type)
		if data.has("size"):
			var s: Array = data["size"]
			_size = Vector2(s[0], s[1])
	else:
		_color = Color("#FF00FF")
		_label = platform_type

	if custom_color != Color.TRANSPARENT:
		_color = custom_color
	if custom_size != Vector2.ZERO:
		_size = custom_size

func _draw() -> void:
	if _size == Vector2.ZERO:
		return

	if _draw_textured():
		return

	var rect := Rect2(-_size / 2.0, _size)
	draw_rect(rect, _color)
	draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0)

	if show_label and _label != "":
		var font := ThemeDB.fallback_font
		var font_size := 9
		var text_size := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := Vector2(-text_size.x / 2.0, text_size.y / 2.0 - 2.0)
		draw_string(font, pos, _label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.85))

## Tries to draw the platform from a stored texture variant. Returns true if
## a texture was drawn (caller skips the colored fallback). Width is taken
## from _size.x; height is derived from the source aspect ratio so the rocky
## underside scales naturally. The visual top edge lines up with the collision
## top (y = -_size.y / 2) and the rest hangs downward.
func _draw_textured() -> bool:
	var paths: Array = PLATFORM_TEXTURES.get(platform_type, [])
	if paths.is_empty():
		return false
	var loaded: Array = _ensure_textures(paths)
	if loaded.is_empty():
		return false

	# Deterministic per-platform pick — same level always renders the same
	# variant in the same spot, but different platforms differ.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var tex: Texture2D = loaded[rng.randi() % loaded.size()]

	var tex_w: float = float(tex.get_width())
	var tex_h: float = float(tex.get_height())
	if tex_w <= 0.0 or tex_h <= 0.0:
		return false

	var visual_w: float = _size.x
	var visual_h: float = visual_w * (tex_h / tex_w)
	var rect := Rect2(-visual_w / 2.0, -_size.y / 2.0, visual_w, visual_h)
	draw_texture_rect(tex, rect, false)
	_draw_top_rim_light(rect)
	return true

# Pale cream rim light along the upper edge — reads as the GDD's "cold
# sourceless light from above" catching the platform top, and gives the
# silhouette enough contrast to pop off the dimmed backdrop. Two thin lines
# of decreasing alpha imitate a soft painted highlight without breaking the
# bold-outline cartoon style.
const RIM_COLOR_HARD: Color = Color(0.95, 0.92, 0.85, 0.55)
const RIM_COLOR_SOFT: Color = Color(0.95, 0.92, 0.85, 0.22)

func _draw_top_rim_light(rect: Rect2) -> void:
	# Inset 4 px from the chipped corners so the highlight reads as light on
	# the stone surface, not as a glowing border around the whole sprite.
	var inset_x: float = 4.0
	var x0: float = rect.position.x + inset_x
	var x1: float = rect.position.x + rect.size.x - inset_x
	var y_top: float = rect.position.y
	# 1 px hard line at the very top + 2 px soft line just below = soft glow.
	draw_line(Vector2(x0, y_top + 0.5), Vector2(x1, y_top + 0.5), RIM_COLOR_HARD, 1.0)
	draw_line(Vector2(x0, y_top + 2.0), Vector2(x1, y_top + 2.0), RIM_COLOR_SOFT, 2.0)

func _ensure_textures(paths: Array) -> Array:
	var loaded: Array = []
	for p in paths:
		var key: String = String(p)
		if _tex_cache.has(key):
			var cached: Texture2D = _tex_cache[key]
			if cached:
				loaded.append(cached)
			continue
		if not ResourceLoader.exists(key):
			_tex_cache[key] = null
			continue
		var tex: Texture2D = load(key)
		_tex_cache[key] = tex
		if tex:
			loaded.append(tex)
	return loaded
