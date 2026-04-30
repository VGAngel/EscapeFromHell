extends GutTest

# Tests for MenuBackground — the animated red-sky shader + optional
# silhouette parallax layers behind MainMenu.

const MenuBackgroundScript := preload("res://scripts/ui/MenuBackground.gd")

var root: Control
var bg: Node


func before_each() -> void:
	root = Control.new()
	root.size = Vector2(1080, 1920)
	add_child_autofree(root)
	bg = MenuBackgroundScript.new()
	root.add_child(bg)
	bg.setup(root)


# ── Sky shader ────────────────────────────────────────────────────────────────

func test_sky_layer_built_with_shader_material() -> void:
	assert_true(root.has_node("AnimatedSky"))
	var sky: ColorRect = root.get_node("AnimatedSky")
	assert_not_null(sky.material)
	assert_true(sky.material is ShaderMaterial)


func test_process_advances_time_uniform() -> void:
	var t0: float = bg._sky_mat.get_shader_parameter("time")
	bg._process(0.5)
	var t1: float = bg._sky_mat.get_shader_parameter("time")
	assert_gt(t1, t0,
			"sky shader's time uniform must increase each frame")


# ── Reduce-motion ─────────────────────────────────────────────────────────────

func test_reduce_motion_freezes_time_uniform() -> void:
	bg._reduce_motion = true
	var t0: float = bg._sky_mat.get_shader_parameter("time")
	bg._process(0.5)
	var t1: float = bg._sky_mat.get_shader_parameter("time")
	assert_eq(t1, t0,
			"with reduce_motion the time uniform must stay frozen")


# ── Silhouette graceful skip ──────────────────────────────────────────────────

func test_missing_silhouette_assets_skip_silently() -> void:
	# In the test fixture neither Assets/menu_bg_mid.png nor
	# Assets/menu_bg_near.png exist yet (waiting on the MJ pass).
	# The build path must not crash and must leave the layer fields
	# null so the parallax loop skips them.
	assert_null(bg._mid)
	assert_null(bg._near)


# ── Legacy Background hidden ──────────────────────────────────────────────────

func test_existing_background_node_is_hidden_when_present() -> void:
	# Re-stand up with a Background TextureRect already in tree to
	# verify MenuBackground hides it (so the static texture doesn't
	# fight the new shader).
	var root2 := Control.new()
	root2.size = Vector2(1080, 1920)
	add_child_autofree(root2)
	var legacy := TextureRect.new()
	legacy.name = "Background"
	root2.add_child(legacy)
	var bg2: Node = MenuBackgroundScript.new()
	root2.add_child(bg2)
	bg2.setup(root2)
	assert_false(legacy.visible,
			"legacy Background TextureRect must be hidden once " +
			"MenuBackground takes over")
