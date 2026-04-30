class_name AmbientLighting extends RefCounted

# Atmosphere-lighting helper for the dungeon levels.
#
# Levels were rendering as flat-bright canvases — every pixel fully lit,
# no mood, no focal points. This module gives other systems three small
# primitives that collectively turn a level into an atmospheric pool of
# warm light surrounded by dim ambient:
#
#   1. apply_to_level(root) — adds a CanvasModulate so PointLight2Ds have
#      something to push back against. Without dimmed ambient the scene
#      is fully lit and added lights have nothing to reveal.
#   2. make_player_light() — warm "soul flame" radial light to attach to
#      the player so their footprint is always visible regardless of how
#      sparsely the room is decorated with torches.
#   3. tint_for_circle(circle) — themed colour for circle-specific
#      decoration (used by Torch.gd to pick its flame colour).
#
# All callers are stateless; the radial gradient texture used by every
# PointLight2D is built once and cached statically.

# ── Tunables ─────────────────────────────────────────────────────────────────

# Global ambient — moody but readable. Lower values produce a darker
# world where lights stand out more. Tuned to leave platform silhouettes
# legible without flashlight playthroughs feeling necessary.
const AMBIENT_TINT: Color = Color(0.55, 0.50, 0.60)

# Player's warm flame — same warm amber on every circle so the player
# always reads as the "anchor of life" against the cold/hostile palette.
const PLAYER_LIGHT_COLOR: Color = Color(1.0, 0.78, 0.45)
const PLAYER_LIGHT_ENERGY: float = 1.4
const PLAYER_LIGHT_SCALE: float = 2.4

# Torch defaults (Torch.gd reads these so we can tune all torches in one place).
const TORCH_LIGHT_ENERGY: float = 1.1
const TORCH_LIGHT_SCALE: float = 1.6

# Per-circle torch tint. Colours roughly mirror the per-circle backdrop in
# PlaceholderRoom.CIRCLE_COLORS but pushed to higher saturation since they
# light flames, not floor tiles.
const TORCH_COLORS: Dictionary = {
	1:  Color(0.65, 0.45, 1.00),   # 1 — void purple
	2:  Color(0.45, 0.70, 1.00),   # 2 — deep blue
	3:  Color(1.00, 0.55, 0.20),   # 3 — charred red / fire
	4:  Color(0.55, 1.00, 0.45),   # 4 — swamp / sickly green
	5:  Color(1.00, 0.85, 0.35),   # 5 — gold dust
	6:  Color(0.55, 0.92, 1.00),   # 6 — icy teal
	7:  Color(1.00, 0.40, 0.55),   # 7 — crimson dusk
	8:  Color(1.00, 0.55, 0.25),   # 8 — iron rust
	9:  Color(0.85, 0.85, 0.90),   # 9 — ashen grey / pale
	10: Color(1.00, 0.20, 0.20),   # 10 — blood red (final)
}
const TORCH_FALLBACK: Color = Color(1.00, 0.55, 0.20)

# Lazy singleton — radial gradient driving every PointLight2D's shape.
static var _radial_tex: GradientTexture2D = null


# ── Public API ───────────────────────────────────────────────────────────────

## Add (or refresh) the level's CanvasModulate. Idempotent — calling twice
## just retunes the existing one. Returns the node so tests can inspect it.
static func apply_to_level(root: Node) -> CanvasModulate:
	if root == null:
		return null
	var existing: CanvasModulate = null
	for c in root.get_children():
		if c is CanvasModulate:
			existing = c
			break
	var node: CanvasModulate = existing if existing else CanvasModulate.new()
	node.color = AMBIENT_TINT
	if existing == null:
		node.name = "AmbientCanvasModulate"
		root.add_child(node)
	return node


## Build a warm point-light meant to attach to the Player. The caller is
## responsible for `add_child()`; positioned at (0,0) which lines up with
## the player's torso when added as a direct child of CharacterBody2D.
static func make_player_light() -> PointLight2D:
	var lt := PointLight2D.new()
	lt.name = "PlayerLight"
	lt.texture = get_radial_texture()
	lt.color = PLAYER_LIGHT_COLOR
	lt.energy = PLAYER_LIGHT_ENERGY
	lt.texture_scale = PLAYER_LIGHT_SCALE
	lt.shadow_enabled = false
	# Ensure the light renders on top of the canvas modulate (default Z=0
	# would still work, but explicit here makes light behaviour predictable
	# even if a future caller sets the player's z_as_relative).
	lt.z_as_relative = false
	return lt


## Tint colour for `circle` (1..10). Falls back to fire-orange when out
## of range — keeps level rendering safe even if circle config is missing.
static func tint_for_circle(circle: int) -> Color:
	return TORCH_COLORS.get(circle, TORCH_FALLBACK)


## Shared radial gradient used by every PointLight2D — the texture's white
## centre and transparent edge make the light pool falloff smooth. Cached
## so we don't allocate one per light.
static func get_radial_texture() -> GradientTexture2D:
	if _radial_tex != null:
		return _radial_tex
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	_radial_tex = tex
	return tex
