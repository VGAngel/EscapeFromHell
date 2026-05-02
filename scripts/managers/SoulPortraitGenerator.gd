extends Node

# Procedural pixel-art portrait generator for collected souls.
#
# One unique 96x96 RGBA portrait per soul, deterministically derived from
# soul_id, so the same soul always renders the same face. Output is an
# ImageTexture intended to be displayed at 2x-3x scale with nearest-
# neighbour filtering (handled by the consuming TextureRect).
#
# Result is cached per soul_id; CollectionScreen calls clear_cache() when
# it closes so a long session doesn't pin all 356 portraits in memory.
#
# Style:
#   - Soft circular vignette background, tinted by circle (Лімб=cool grey,
#     Гнів=red, Трон=near black, etc).
#   - Pixel-art silhouette: shoulders + neck + round head.
#   - Hair: 5 styles (short, long, bald, hood, parted) × 8 colours,
#     greying with age.
#   - Skin: 4 tones.
#   - Eyes: open dots for innocent/broken, horizontal lashes for sleeping.
#   - Mouth: subtle smile (innocent), frown (broken), straight (sleeping).
#
# Variation comes from seeding RandomNumberGenerator with soul_id, so
# every visual choice is reproducible from JSON alone.

const PORTRAIT_SIZE := 96
const HEAD_CY := 38
const HEAD_R  := 18

# Per-circle background tint. Index 0 unused so circles map 1..10 directly.
const CIRCLE_BG: Array[Color] = [
	Color("#8a8a90"),  # 0 unused
	Color("#6e7080"),  # 1 Лімб
	Color("#a85870"),  # 2 Хіть
	Color("#c87038"),  # 3 Жага
	Color("#b89640"),  # 4 Жадібність
	Color("#a83838"),  # 5 Гнів
	Color("#7050a0"),  # 6 Єресь
	Color("#702828"),  # 7 Насилля
	Color("#387870"),  # 8 Шахрайство
	Color("#384878"),  # 9 Зрада
	Color("#181820"),  # 10 Трон Люцифера
]

const SKIN_TONES: Array[Color] = [
	Color("#f0c8a0"),  # pale
	Color("#d0a878"),  # medium
	Color("#a87850"),  # tan
	Color("#785840"),  # dark
]

const HAIR_COLORS: Array[Color] = [
	Color("#1a1a1a"),  # black
	Color("#5a3018"),  # dark brown
	Color("#9a6830"),  # brown
	Color("#c89858"),  # blonde
	Color("#603830"),  # auburn
	Color("#a04030"),  # red
	Color("#888888"),  # grey
	Color("#e0e0e8"),  # white
]

# Cache: soul_id (int) -> ImageTexture. Cleared on close().
var _cache: Dictionary = {}


# Returns a cached or freshly generated ImageTexture for the soul.
# Soul dict shape: {id: int, circle: int (1..10), type: String, age: int|"?"}.
func get_portrait(soul: Dictionary) -> ImageTexture:
	var sid: int = int(soul.get("id", 0))
	if _cache.has(sid):
		return _cache[sid]
	var tex := _generate(soul)
	_cache[sid] = tex
	return tex


# Free all cached textures. Call on CollectionScreen close so a long
# session doesn't pin 356 × ~36KB ≈ 13MB of textures in memory.
func clear_cache() -> void:
	_cache.clear()


func _generate(soul: Dictionary) -> ImageTexture:
	var sid: int    = int(soul.get("id", 0))
	var circle: int = clampi(int(soul.get("circle", 1)), 1, 10)
	var soul_type: String = String(soul.get("type", "innocent"))

	var age: int = 30
	var age_v: Variant = soul.get("age", 30)
	if typeof(age_v) == TYPE_INT or typeof(age_v) == TYPE_FLOAT:
		age = int(age_v)

	var rng := RandomNumberGenerator.new()
	rng.seed = max(1, sid)

	var img: Image = Image.create(PORTRAIT_SIZE, PORTRAIT_SIZE, false, Image.FORMAT_RGBA8)

	_draw_background(img, CIRCLE_BG[circle])

	var skin: Color = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	var clothing: Color = _clothing_color(circle, rng)
	_draw_body(img, clothing)
	_draw_head(img, skin)

	var hair: Color = HAIR_COLORS[rng.randi() % HAIR_COLORS.size()]
	# Greying with age: above 55 lerps toward grey, above 75 toward white.
	if age >= 75:
		hair = hair.lerp(Color("#e8e8ec"), 0.7)
	elif age >= 55:
		hair = hair.lerp(Color("#a0a0a8"), 0.5)
	var hair_style: int = rng.randi() % 5
	_draw_hair(img, hair, hair_style)

	_draw_eyes(img, soul_type)
	_draw_mouth(img, soul_type)

	return ImageTexture.create_from_image(img)


# Soft radial vignette: base colour at centre, darkening toward edges.
# Matches the existing collection screen palette without imposing a
# hard frame on the portrait.
func _draw_background(img: Image, base: Color) -> void:
	var center: Vector2 = Vector2(PORTRAIT_SIZE * 0.5, PORTRAIT_SIZE * 0.5)
	var max_r: float = float(PORTRAIT_SIZE) * 0.55
	for y in PORTRAIT_SIZE:
		for x in PORTRAIT_SIZE:
			var d: float = Vector2(x, y).distance_to(center)
			var t: float = clamp(d / max_r, 0.0, 1.0)
			img.set_pixel(x, y, base.darkened(t * 0.55))


# Tapered shoulders/neck silhouette below the head.
func _draw_body(img: Image, color: Color) -> void:
	for y in range(62, PORTRAIT_SIZE):
		var prog: float = float(y - 62) / 34.0
		var half_w: int = int(lerp(18.0, 36.0, prog))
		var x0: int = PORTRAIT_SIZE / 2 - half_w
		var x1: int = PORTRAIT_SIZE / 2 + half_w
		for x in range(x0, x1):
			img.set_pixel(x, y, color)


func _draw_head(img: Image, skin: Color) -> void:
	var cx: int = PORTRAIT_SIZE / 2
	var r2: int = HEAD_R * HEAD_R
	for y in range(HEAD_CY - HEAD_R, HEAD_CY + HEAD_R + 1):
		for x in range(cx - HEAD_R, cx + HEAD_R + 1):
			var dx: int = x - cx
			var dy: int = y - HEAD_CY
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, skin)


# Five hair archetypes, all anchored to the head circle. Style 2 leaves
# the head bald; the rest add a layer of pixels in different shapes.
func _draw_hair(img: Image, color: Color, style: int) -> void:
	var cx: int = PORTRAIT_SIZE / 2
	var r2: int = HEAD_R * HEAD_R
	match style:
		0:  # Short cap
			for y in range(HEAD_CY - HEAD_R, HEAD_CY - 4):
				for x in range(cx - HEAD_R, cx + HEAD_R + 1):
					var dx: int = x - cx
					var dy: int = y - HEAD_CY
					if dx * dx + dy * dy <= r2:
						img.set_pixel(x, y, color)
		1:  # Long — sides drop past the head
			var r_outer: int = HEAD_R + 3
			var r_outer2: int = r_outer * r_outer
			for y in range(HEAD_CY - HEAD_R, HEAD_CY + HEAD_R + 4):
				for x in range(cx - r_outer, cx + r_outer + 1):
					var dx: int = x - cx
					var dy: int = y - HEAD_CY
					var d2: int = dx * dx + dy * dy
					if d2 > r2 and d2 <= r_outer2 and y >= HEAD_CY - HEAD_R:
						img.set_pixel(x, y, color)
			# Cap on top
			for y in range(HEAD_CY - HEAD_R - 1, HEAD_CY - 6):
				for x in range(cx - HEAD_R, cx + HEAD_R + 1):
					var dx2: int = x - cx
					var dy2: int = y - HEAD_CY
					if dx2 * dx2 + dy2 * dy2 <= r2:
						img.set_pixel(x, y, color)
		2:  # Bald — no hair pixels
			pass
		3:  # Hood — covers crown and falls onto shoulders
			var hood: Color = color.darkened(0.4)
			var r_outer3: int = HEAD_R + 4
			var r_outer3_2: int = r_outer3 * r_outer3
			for y in range(HEAD_CY - HEAD_R - 3, HEAD_CY + 6):
				for x in range(cx - r_outer3, cx + r_outer3 + 1):
					var dx: int = x - cx
					var dy: int = y - HEAD_CY
					var d2: int = dx * dx + dy * dy
					if d2 <= r_outer3_2 and d2 >= (HEAD_R - 6) * (HEAD_R - 6):
						img.set_pixel(x, y, hood)
		4:  # Centre-parted top
			for y in range(HEAD_CY - HEAD_R, HEAD_CY - 5):
				for x in range(cx - HEAD_R, cx + HEAD_R + 1):
					var dx: int = x - cx
					var dy: int = y - HEAD_CY
					if dx * dx + dy * dy <= r2 and abs(dx) > 1:
						img.set_pixel(x, y, color)


func _draw_eyes(img: Image, soul_type: String) -> void:
	var cx: int = PORTRAIT_SIZE / 2
	var eye_y: int = 40
	var eye_color: Color = Color("#1a1a1a")

	if soul_type == "sleeping":
		# Closed: horizontal slit
		for x in range(cx - 9, cx - 3):
			img.set_pixel(x, eye_y, eye_color)
		for x in range(cx + 3, cx + 9):
			img.set_pixel(x, eye_y, eye_color)
	else:
		# Open: 2×2 pupils
		for y in range(eye_y - 1, eye_y + 1):
			for x in range(cx - 8, cx - 6):
				img.set_pixel(x, y, eye_color)
			for x in range(cx + 6, cx + 8):
				img.set_pixel(x, y, eye_color)


func _draw_mouth(img: Image, soul_type: String) -> void:
	var cx: int = PORTRAIT_SIZE / 2
	var color: Color = Color("#1a1a1a")
	var my: int = 52

	match soul_type:
		"innocent":
			# Subtle smile (corners up)
			img.set_pixel(cx - 4, my, color)
			img.set_pixel(cx + 4, my, color)
			for x in range(cx - 3, cx + 4):
				img.set_pixel(x, my + 1, color)
		"broken":
			# Subtle frown (corners down)
			img.set_pixel(cx - 4, my + 1, color)
			img.set_pixel(cx + 4, my + 1, color)
			for x in range(cx - 3, cx + 4):
				img.set_pixel(x, my, color)
		"sleeping":
			# Straight neutral line
			for x in range(cx - 4, cx + 5):
				img.set_pixel(x, my, color)
		_:
			for x in range(cx - 3, cx + 4):
				img.set_pixel(x, my, color)


# Clothing slightly darker than the background tint so the silhouette
# reads against the vignette without clashing with the head shape.
func _clothing_color(circle: int, rng: RandomNumberGenerator) -> Color:
	var bg: Color = CIRCLE_BG[circle]
	return bg.darkened(0.35 + rng.randf() * 0.15)
