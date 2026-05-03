extends Node

# Autoload: ParticleEffects
# One-shot particle bursts by preset name. Each call spawns a self-cleaning
# CPUParticles2D (no .tres resources required — everything configured in
# code) and attaches it to the current scene tree root so the burst
# survives the caller queue_free-ing (e.g. Soul on pickup).
#
#   ParticleEffects.spawn("soul_pickup", world_pos)
#   ParticleEffects.spawn("death",       world_pos)
#   ParticleEffects.spawn("staff_swing", world_pos, facing_right)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## Spawn a one-shot particle burst at `world_pos`. `flip` is used by
## directional presets (staff_swing) to face left when false.
func spawn(preset: String, world_pos: Vector2, flip: bool = true) -> void:
	var parent: Node = _scene_root()
	if not parent:
		return
	var p: CPUParticles2D = _make(preset, flip)
	if not p:
		return
	p.position = world_pos
	p.emitting = true
	p.one_shot = true
	parent.add_child(p)
	# Auto-free after the longest particle lifetime + a small buffer.
	var tree := get_tree()
	if tree:
		var timer := tree.create_timer(p.lifetime + 0.3)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.queue_free())

# ── Presets ───────────────────────────────────────────────────────────────────

func _make(preset: String, flip: bool) -> CPUParticles2D:
	match preset:
		"soul_pickup":  return _preset_soul_pickup()
		"death":        return _preset_death()
		"staff_swing":  return _preset_staff_swing(flip)
		"staff_impact": return _preset_staff_impact()
		"respawn":      return _preset_respawn()
		"crumble":      return _preset_crumble()
		"enemy_kill":   return _preset_enemy_kill()
		"enemy_stun":   return _preset_enemy_stun()
	return null

func _preset_soul_pickup() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 24
	p.lifetime       = 0.8
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction      = Vector2.UP
	p.spread         = 180.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 110.0
	p.gravity        = Vector2(0.0, -40.0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.4
	p.color          = Color("#FFE7A3")
	return p

func _preset_death() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 28
	p.lifetime       = 1.1
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 10.0
	p.direction      = Vector2.UP
	p.spread         = 60.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 180.0
	p.gravity        = Vector2(0.0, 220.0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color           = Color(0.55, 0.0, 0.0)
	return p

func _preset_staff_swing(facing_right: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 14
	p.lifetime       = 0.35
	p.explosiveness  = 0.9
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(30.0, 4.0)
	var dir := Vector2.RIGHT if facing_right else Vector2.LEFT
	p.direction      = dir
	p.spread         = 12.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 220.0
	p.gravity        = Vector2.ZERO
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.0
	p.color          = Color("#DDE1FF")
	return p

## Quick burst of bright sparks at the impact point — used when the staff
## connects with an enemy. Short lifetime + high explosiveness so it reads
## as a single "pop" without trailing across the screen.
func _preset_staff_impact() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 18
	p.lifetime       = 0.32
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.direction      = Vector2.UP
	p.spread         = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 220.0
	p.gravity        = Vector2(0.0, 280.0)
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.6
	p.color          = Color("#FFE066")
	return p

func _preset_respawn() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 20
	p.lifetime       = 0.9
	p.explosiveness  = 0.8
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	p.direction      = Vector2.UP
	p.spread         = 35.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 140.0
	p.gravity        = Vector2(0.0, -80.0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color          = Color("#F2F2FF")
	return p

## Heavy red splash for the moment a player stomps a stompable enemy.
## Larger amount + dark crimson + downward gravity so it reads as a
## visceral splat that settles, distinct from the smaller `death` burst
## used elsewhere.
func _preset_enemy_kill() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 36
	p.lifetime       = 1.0
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 12.0
	p.direction      = Vector2.UP
	p.spread         = 80.0
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 280.0
	p.gravity        = Vector2(0.0, 480.0)
	p.scale_amount_min = 1.6
	p.scale_amount_max = 3.4
	p.color          = Color("#9A1320")
	return p


## Cartoon "stunned stars" — yellow specks that float UP slowly in a
## ring above the enemy's head. Uses negative gravity so they hang
## briefly before fading, matching the duration of the stun knockback.
func _preset_enemy_stun() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 14
	p.lifetime       = 0.9
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 18.0
	p.direction      = Vector2.UP
	p.spread         = 30.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 60.0
	p.gravity        = Vector2(0.0, -40.0)
	p.scale_amount_min = 1.8
	p.scale_amount_max = 2.6
	p.color          = Color("#FFEE55")
	return p


func _preset_crumble() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount         = 16
	p.lifetime       = 0.7
	p.explosiveness  = 1.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(40.0, 6.0)
	p.direction      = Vector2.DOWN
	p.spread         = 60.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.gravity        = Vector2(0.0, 300.0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.color          = Color(0.5, 0.44, 0.38)
	return p

# ── Helpers ───────────────────────────────────────────────────────────────────

func _scene_root() -> Node:
	var tree := get_tree()
	if not tree:
		return null
	return tree.current_scene
