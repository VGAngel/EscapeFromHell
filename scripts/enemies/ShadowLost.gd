extends "res://scripts/enemies/BaseEnemy.gd"

# Circle 1 enemy — slow basic patroller. Stats come from enemies_config.json.
# Sprite is a solid-color placeholder (from placeholder_color in config) until
# animated sprites are wired up.

const CONFIG_PATH := "res://enemies_config.json"
const ENEMY_ID    := "shadow_lost"

var _placeholder_color: Color  = Color("#444466")
var _placeholder_size:  Vector2 = Vector2(20, 32)

func _ready() -> void:
	_apply_config()
	_make_placeholder_sprite()
	super._ready()

func _apply_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("ShadowLost: cannot open " + CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	for entry in parsed.get("enemies", []):
		if entry.get("id", "") != ENEMY_ID:
			continue
		move_speed      = float(entry.get("move_speed",      move_speed))
		detection_range = float(entry.get("detection_range", detection_range))
		patrol_distance = float(entry.get("patrol_distance", patrol_distance))
		alert_duration  = float(entry.get("alert_duration",  alert_duration))
		if entry.has("placeholder_color"):
			_placeholder_color = Color(entry["placeholder_color"])
		if entry.has("size"):
			var s: Array = entry["size"]
			if s.size() == 2:
				_placeholder_size = Vector2(s[0], s[1])
		return

func _make_placeholder_sprite() -> void:
	if not _sprite:
		return
	var w := int(max(_placeholder_size.x, 1.0))
	var h := int(max(_placeholder_size.y, 1.0))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(_placeholder_color)
	_sprite.texture = ImageTexture.create_from_image(img)
