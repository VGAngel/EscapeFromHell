extends "res://scripts/enemies/BossAI.gd"

# Circle 1 boss — "Воротар" (Gatekeeper). Thin subclass that pins the
# boss_id to boss_01 and generates a solid-colour placeholder sprite
# from bosses_config.json (visual.placeholder_color + visual.size).

func _ready() -> void:
	boss_id = "boss_01"
	super._ready()
	_make_placeholder_sprite_from_config()

func _make_placeholder_sprite_from_config() -> void:
	if not _sprite:
		return
	var visual: Dictionary = _cfg.get("visual", {})
	var col := Color(visual.get("placeholder_color", "#AA3300")) as Color
	var size_arr: Variant = visual.get("size", [64, 96])
	var w: int = 64
	var h: int = 96
	if size_arr is Array and (size_arr as Array).size() == 2:
		w = int((size_arr as Array)[0])
		h = int((size_arr as Array)[1])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(col)
	_sprite.texture = ImageTexture.create_from_image(img)
