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

func test_existing_background_kept_visible_skips_sky_shader() -> void:
	# When the .tscn supplies a static Background TextureRect (the
	# Background_02.png hellscape art) MenuBackground must NOT fight
	# it — leave the static art visible AND skip building the
	# procedural sky shader on top.
	var root2 := Control.new()
	root2.size = Vector2(1080, 1920)
	add_child_autofree(root2)
	var legacy := TextureRect.new()
	legacy.name = "Background"
	root2.add_child(legacy)
	var bg2: Node = MenuBackgroundScript.new()
	root2.add_child(bg2)
	bg2.setup(root2)
	assert_true(legacy.visible,
			"static Background must stay visible when MenuBackground " +
			"detects it on init")
	assert_null(bg2._sky_mat,
			"sky shader must be skipped when static bg exists")


func test_no_existing_background_falls_back_to_sky_shader() -> void:
	# Without a static Background node, MenuBackground builds the
	# procedural FBM sky shader as a fallback so the menu always
	# has a backdrop.
	var root3 := Control.new()
	root3.size = Vector2(1080, 1920)
	add_child_autofree(root3)
	var bg3: Node = MenuBackgroundScript.new()
	root3.add_child(bg3)
	bg3.setup(root3)
	assert_not_null(bg3._sky_mat,
			"sky shader must build when no static Background is present")
	assert_true(root3.has_node("AnimatedSky"))


func test_static_bg_drifts_with_tilt() -> void:
	# The static Background TextureRect should also pick up the
	# parallax drift so it doesn't sit dead-still while the
	# silhouettes (when present) move on top.
	var root4 := Control.new()
	root4.size = Vector2(1080, 1920)
	add_child_autofree(root4)
	var legacy := TextureRect.new()
	legacy.name = "Background"
	root4.add_child(legacy)
	var bg4: Node = MenuBackgroundScript.new()
	root4.add_child(bg4)
	bg4.setup(root4)
	# Force a non-zero tilt and one process tick.
	bg4._tilt = Vector2(1.0, 0.0)
	bg4._update_parallax(0.016)
	assert_ne(legacy.position.x, 0.0,
			"static Background must drift when tilt is non-zero")
