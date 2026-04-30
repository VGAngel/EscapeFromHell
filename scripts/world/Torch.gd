class_name Torch extends Node2D

# Self-contained themed torch — colored PointLight2D + small diamond flame
# visual + auto-flicker. PlaceholderRoom (and any other level decorator)
# spawns these alongside platforms; AmbientLighting picks the colour.
#
# Usage:
#   var t := preload("res://scripts/world/Torch.gd").new()
#   t.circle = self.circle
#   t.position = Vector2(x, y)
#   add_child(t)
#
# Each instance staggers its own flicker phase by a small random delay so
# clusters of torches don't pulse in lockstep.

const AmbientLightingRef := preload("res://scripts/world/AmbientLighting.gd")

@export var circle: int = 1

var _light: PointLight2D = null
var _flame: Polygon2D = null
var _tween: Tween = null


func _ready() -> void:
	var color: Color = AmbientLightingRef.tint_for_circle(circle)
	_build_light(color)
	_build_flame_visual(color)
	# Headless tests / editor previews skip the flicker — keeps suites
	# deterministic and avoids spawning Tweens we'd just have to clean up.
	if Engine.is_editor_hint():
		return
	_start_flicker_deferred()


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_light(color: Color) -> void:
	_light = PointLight2D.new()
	_light.name = "Light"
	_light.texture = AmbientLightingRef.get_radial_texture()
	_light.color = color
	_light.energy = AmbientLightingRef.TORCH_LIGHT_ENERGY
	_light.texture_scale = AmbientLightingRef.TORCH_LIGHT_SCALE
	_light.shadow_enabled = false
	add_child(_light)


# Small diamond flame so torches read as objects in the world even when
# the lighting is dim. We don't ship art for this — a 4-vertex polygon
# tinted bright reads fine for placeholder visuals.
func _build_flame_visual(color: Color) -> void:
	_flame = Polygon2D.new()
	_flame.name = "Flame"
	_flame.color = color.lightened(0.35)
	_flame.polygon = PackedVector2Array([
		Vector2( 0, -12),
		Vector2( 5,  -2),
		Vector2( 0,   6),
		Vector2(-5,  -2),
	])
	add_child(_flame)


# ── Flicker ───────────────────────────────────────────────────────────────────

# Stagger the start by a small random delay so a row of torches breathes
# out of phase. Anchored to a one-shot timer instead of `await` chained
# off get_tree() because Tween.create can't run before the node enters
# the scene tree, which is guaranteed only after _ready() returns.
func _start_flicker_deferred() -> void:
	if not is_inside_tree():
		return
	var t: SceneTreeTimer = get_tree().create_timer(randf() * 0.6)
	t.timeout.connect(_start_flicker)


func _start_flicker() -> void:
	if not is_inside_tree() or _light == null:
		return
	var base_e: float = AmbientLightingRef.TORCH_LIGHT_ENERGY
	_tween = create_tween().set_loops()
	_tween.tween_property(_light, "energy", base_e * 0.82, 0.25 + randf() * 0.15)
	_tween.tween_property(_light, "energy", base_e * 1.18, 0.30 + randf() * 0.15)
	_tween.tween_property(_light, "energy", base_e * 0.96, 0.20 + randf() * 0.10)
