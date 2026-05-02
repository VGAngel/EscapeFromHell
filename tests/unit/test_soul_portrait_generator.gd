extends GutTest

# Tests for SoulPortraitGenerator. Verifies the basic contract: a
# portrait is returned, dimensions match PORTRAIT_SIZE, and that the
# same soul produces the same texture twice (deterministic + cached).

var generator: Node


func before_each() -> void:
	generator = preload("res://scripts/managers/SoulPortraitGenerator.gd").new()
	add_child_autofree(generator)


func _make_soul(id: int, circle: int = 1, type_str: String = "innocent",
		age: Variant = 30) -> Dictionary:
	return {
		"id": id, "circle": circle, "type": type_str, "age": age,
		"name": "Test", "epitaph": "x",
	}


func test_get_portrait_returns_image_texture() -> void:
	var tex: Variant = generator.get_portrait(_make_soul(1))
	assert_true(tex is ImageTexture, "expected ImageTexture")


func test_portrait_dimensions_match_constant() -> void:
	var tex: ImageTexture = generator.get_portrait(_make_soul(1))
	assert_eq(tex.get_width(),  generator.PORTRAIT_SIZE)
	assert_eq(tex.get_height(), generator.PORTRAIT_SIZE)


func test_same_soul_returns_cached_texture() -> void:
	# Identity check — the cache should hand back the SAME instance
	# rather than regenerating the image on every call.
	var tex1: ImageTexture = generator.get_portrait(_make_soul(42))
	var tex2: ImageTexture = generator.get_portrait(_make_soul(42))
	assert_eq(tex1.get_instance_id(), tex2.get_instance_id())


func test_different_souls_produce_different_textures() -> void:
	# Different IDs should produce visually distinct portraits. We compare
	# raw image bytes (cheap with 96×96) rather than pixel-by-pixel.
	var t1: ImageTexture = generator.get_portrait(_make_soul(1))
	var t2: ImageTexture = generator.get_portrait(_make_soul(2))
	assert_ne(t1.get_image().get_data(), t2.get_image().get_data())


func test_clear_cache_releases_textures() -> void:
	generator.get_portrait(_make_soul(1))
	generator.get_portrait(_make_soul(2))
	assert_eq(generator._cache.size(), 2)
	generator.clear_cache()
	assert_eq(generator._cache.size(), 0)


func test_handles_string_age_question_mark() -> void:
	# Soul id 100 ("Безіменний") stores age as "?" rather than int.
	# Generator must not crash on the type juggle.
	var tex: ImageTexture = generator.get_portrait(_make_soul(100, 10, "sleeping", "?"))
	assert_not_null(tex)


func test_handles_all_soul_types() -> void:
	# Each type drives a different mouth/eye render. None should crash.
	for type_str in ["innocent", "broken", "sleeping"]:
		var tex: ImageTexture = generator.get_portrait(_make_soul(7, 5, type_str))
		assert_not_null(tex, "type=%s should produce a texture" % type_str)


func test_handles_all_circles() -> void:
	# Circles 1..10 each pick a different background palette entry.
	for c in range(1, 11):
		var tex: ImageTexture = generator.get_portrait(_make_soul(c * 10, c))
		assert_not_null(tex, "circle=%d should produce a texture" % c)


func test_circle_out_of_range_clamped() -> void:
	# Defensive: a malformed JSON entry with circle=0 or circle=99 must
	# not index past CIRCLE_BG. Generator clamps to 1..10.
	var tex_low:  ImageTexture = generator.get_portrait(_make_soul(1, 0))
	var tex_high: ImageTexture = generator.get_portrait(_make_soul(2, 99))
	assert_not_null(tex_low)
	assert_not_null(tex_high)
