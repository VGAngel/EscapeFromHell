class_name Torch extends Node2D

# Self-contained themed torch — colored PointLight2D + a wall torch
# sprite with a looping 4-frame flame on top + auto-flicker. The torch
# body is tiered by depth (white tier → torch_white, deeper → torch_grey,
# matching the wall tiers). Falls back to the old diamond polygon when
# the art isn't imported yet, so torches are never invisible.
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

const _DECOR_ROOT  := "res://Assets/OurAssets/decor/circle1/"
const _SCREEN_PX   := 1920.0     # depth tier boundary (matches wall tiers)
const _TORCH_BODY_H := 130.0
const _FLAME_H      := 70.0
const _FLAME_FRAMES := 4
const _FLAME_FPS    := 12.0
# Flame-cup position as a fraction of the torch sprite. This art leans
# diagonally — the lit tip is upper-right, not centred — so both the
# flame and its PointLight2D anchor here.
const _FLAME_CUP_FX := 0.85
const _FLAME_CUP_FY := 0.08

static var _flame_frames_cache: SpriteFrames = null

@export var circle: int = 1

var _light: PointLight2D = null
var _flame: Polygon2D = null      # legacy fallback only
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


func _build_flame_visual(color: Color) -> void:
	var body_tex: Texture2D = _torch_body_texture()
	if body_tex == null:
		_build_legacy_flame(color)   # art not imported yet
		return
	var bh: float = float(body_tex.get_height())
	var s: float = _TORCH_BODY_H / maxf(1.0, bh)
	var bw: float = float(body_tex.get_width()) * s
	var body := Sprite2D.new()
	body.name = "TorchBody"
	body.texture = body_tex
	body.scale = Vector2(s, s)      # centered by default — sits on the mount point
	add_child(body)

	# Cup point in node space (body is centred at the origin).
	var cup := Vector2(
		bw * (_FLAME_CUP_FX - 0.5),
		_TORCH_BODY_H * (_FLAME_CUP_FY - 0.5))
	# Glow + flicker emanate from the actual fire, not the torch centre.
	if _light:
		_light.position = cup

	var sf: SpriteFrames = _flame_sprite_frames()
	if sf == null:
		return
	var f0: Texture2D = sf.get_frame_texture(&"default", 0)
	var fw: float = float(f0.get_width())  if f0 else 1.0
	var fh: float = float(f0.get_height()) if f0 else 1.0
	var fs: float = _FLAME_H / maxf(1.0, fh)
	var anim := AnimatedSprite2D.new()
	anim.name = "Flame"
	anim.sprite_frames = sf
	anim.centered = false
	anim.scale = Vector2(fs, fs)
	anim.offset = Vector2(-fw * 0.5, -fh)   # bottom-center pivot at the cup
	anim.position = cup
	add_child(anim)
	if not Engine.is_editor_hint():
		anim.play(&"default")


# Depth tier from the torch's shaft Y (mirrors the wall tiers). No dark
# torch art — grey covers both the grey and dark bands.
func _torch_body_texture() -> Texture2D:
	var screen_idx: int = int(position.y / _SCREEN_PX) + 1
	var nm: String = "torch_white" if screen_idx <= 3 else "torch_grey"
	var path: String = _DECOR_ROOT + nm + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _flame_sprite_frames() -> SpriteFrames:
	if _flame_frames_cache != null:
		return _flame_frames_cache
	var sf := SpriteFrames.new()
	sf.set_animation_loop(&"default", true)
	sf.set_animation_speed(&"default", _FLAME_FPS)
	var got := false
	for i in range(1, _FLAME_FRAMES + 1):
		var path: String = "%sfire_torch_%02d.png" % [_DECOR_ROOT, i]
		if ResourceLoader.exists(path):
			var tex: Texture2D = load(path) as Texture2D
			if tex:
				sf.add_frame(&"default", tex)
				got = true
	if not got:
		return null
	_flame_frames_cache = sf
	return sf


# Old placeholder: a small bright diamond so torches still read as objects
# before the art is imported. Kept as a graceful fallback.
func _build_legacy_flame(color: Color) -> void:
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
