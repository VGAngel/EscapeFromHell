extends GutTest

# Tests for AmbientLighting + Torch + the lighting hooks in LevelBase /
# Player. The lighting rig is purely decorative, so the suite focuses on
# structural invariants (right node types created, parented correctly,
# colours consistent per circle) — not on visual fidelity.

const AmbientLightingScript := preload("res://scripts/world/AmbientLighting.gd")
const TorchScript := preload("res://scripts/world/Torch.gd")


# ── apply_to_level ───────────────────────────────────────────────────────────

func test_apply_to_level_adds_canvas_modulate() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var cm: CanvasModulate = AmbientLightingScript.apply_to_level(root)
	assert_not_null(cm)
	assert_true(cm is CanvasModulate)
	assert_eq(cm.get_parent(), root)


func test_apply_to_level_idempotent() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	AmbientLightingScript.apply_to_level(root)
	AmbientLightingScript.apply_to_level(root)
	# Second call must not stack a duplicate CanvasModulate.
	var count := 0
	for c in root.get_children():
		if c is CanvasModulate:
			count += 1
	assert_eq(count, 1)


func test_apply_to_level_uses_dimmed_tint() -> void:
	var root := Node2D.new()
	add_child_autofree(root)
	var cm: CanvasModulate = AmbientLightingScript.apply_to_level(root)
	# Each channel must be < 1 — otherwise we're not actually dimming and
	# Light2D would have nothing to push back against.
	assert_lt(cm.color.r, 1.0)
	assert_lt(cm.color.g, 1.0)
	assert_lt(cm.color.b, 1.0)


func test_apply_to_level_null_root_returns_null() -> void:
	# Defensive: a missing root mustn't crash the whole level boot.
	assert_null(AmbientLightingScript.apply_to_level(null))


# ── make_player_light ────────────────────────────────────────────────────────

func test_make_player_light_returns_point_light() -> void:
	var lt: PointLight2D = AmbientLightingScript.make_player_light()
	assert_not_null(lt)
	assert_true(lt is PointLight2D)
	assert_not_null(lt.texture, "Light needs a radial texture or it renders as 0×0")


func test_player_light_color_is_warm() -> void:
	var lt: PointLight2D = AmbientLightingScript.make_player_light()
	# Red >= green >= blue → warm/amber rather than cold/blue.
	assert_gt(lt.color.r, lt.color.g)
	assert_gt(lt.color.g, lt.color.b)


# ── tint_for_circle ──────────────────────────────────────────────────────────

func test_tint_for_circle_returns_distinct_colours() -> void:
	# Spot-check that circles 1, 4, 7 don't accidentally collide on the same
	# colour (which would mean the dictionary lookup silently fell through).
	var c1: Color = AmbientLightingScript.tint_for_circle(1)
	var c4: Color = AmbientLightingScript.tint_for_circle(4)
	var c7: Color = AmbientLightingScript.tint_for_circle(7)
	assert_ne(c1, c4)
	assert_ne(c4, c7)
	assert_ne(c1, c7)


func test_tint_for_circle_unknown_falls_back_to_orange() -> void:
	var c: Color = AmbientLightingScript.tint_for_circle(99)
	# Fallback should be the warm fire tone (red-dominant, low blue).
	assert_gt(c.r, 0.5)
	assert_lt(c.b, 0.5)


# ── get_radial_texture ───────────────────────────────────────────────────────

func test_radial_texture_is_cached() -> void:
	# Subsequent calls return the same instance — important because PointLight2D
	# instances all share the texture and we don't want N copies on the GPU.
	var a: Texture2D = AmbientLightingScript.get_radial_texture()
	var b: Texture2D = AmbientLightingScript.get_radial_texture()
	assert_eq(a, b)


# ── Torch ────────────────────────────────────────────────────────────────────

func test_torch_builds_light_and_flame() -> void:
	var torch: Node2D = TorchScript.new()
	torch.circle = 3
	add_child_autofree(torch)
	# _ready runs synchronously when add_child triggers tree entry, so the
	# child nodes must exist by the time we get here.
	assert_not_null(torch.get_node_or_null("Light"),
			"Torch must have a child PointLight2D named 'Light'")
	assert_not_null(torch.get_node_or_null("Flame"),
			"Torch must have a child Polygon2D named 'Flame'")


func test_torch_light_uses_circle_tint() -> void:
	var torch: Node2D = TorchScript.new()
	torch.circle = 3   # charred red — fire orange
	add_child_autofree(torch)
	var light: PointLight2D = torch.get_node("Light")
	var expected: Color = AmbientLightingScript.tint_for_circle(3)
	assert_eq(light.color, expected)


func test_torch_circles_produce_different_colors() -> void:
	# Two torches on different circles must end up with visibly different
	# light colours — guards against a regression where set("circle", N)
	# silently no-ops or _ready() reads circle before it's assigned.
	var t1: Node2D = TorchScript.new()
	t1.circle = 1
	add_child_autofree(t1)
	var t2: Node2D = TorchScript.new()
	t2.circle = 4
	add_child_autofree(t2)
	var c1: Color = (t1.get_node("Light") as PointLight2D).color
	var c2: Color = (t2.get_node("Light") as PointLight2D).color
	assert_ne(c1, c2)


func test_torch_light_has_no_shadows() -> void:
	# Shadows require LightOccluder2D on every wall/platform; the project
	# doesn't ship occluders yet, so torches must keep shadow_enabled=false
	# to avoid the renderer logging a warning per torch on level load.
	var torch: Node2D = TorchScript.new()
	torch.circle = 1
	add_child_autofree(torch)
	var light: PointLight2D = torch.get_node("Light")
	assert_false(light.shadow_enabled)
