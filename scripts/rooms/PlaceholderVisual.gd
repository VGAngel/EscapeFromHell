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
	var rect := Rect2(-_size / 2.0, _size)
	draw_rect(rect, _color)
	draw_rect(rect, Color(1, 1, 1, 0.25), false, 1.0)

	if show_label and _label != "":
		var font := ThemeDB.fallback_font
		var font_size := 9
		var text_size := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := Vector2(-text_size.x / 2.0, text_size.y / 2.0 - 2.0)
		draw_string(font, pos, _label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, 0.85))
