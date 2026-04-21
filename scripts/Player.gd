extends CharacterBody2D

# ── Signals ───────────────────────────────────────────────────────────────────
signal soul_picked_up(soul_id: String)
signal soul_dropped(soul_id: String, position: Vector2)
signal soul_delivered(soul_id: String)
signal staff_used
signal player_died
signal hp_changed(current: int, maximum: int)

# ── State ─────────────────────────────────────────────────────────────────────
enum State { IDLE, WALK, JUMP, FALL, STAFF_SWING, PICKUP, CARRYING, DEAD }

var state: State = State.IDLE

# ── Stats (base values, modified by upgrades at runtime) ──────────────────────
var walk_speed:       float = 180.0
var jump_force:       float = 420.0
var min_jump_force:   float = 200.0
var gravity:          float = 900.0
var max_fall_speed:   float = 600.0
var acceleration:     float = 800.0
var deceleration:     float = 1200.0
var air_acceleration: float = 500.0

var staff_range:    float = 80.0
var staff_cooldown: float = 4.5
var staff_sin_cost: int   = 2

var max_hp: int = 3
var current_hp: int = 3

# ── Runtime state ─────────────────────────────────────────────────────────────
var _coyote_timer:      float = 0.0
var _jump_buffer_timer: float = 0.0
var _jump_held:         bool  = false
var _jump_hold_timer:   float = 0.0
var _staff_timer:       float = 0.0
var _pickup_timer:      float = 0.0
var _invincibility_timer: float = 0.0
var _jumps_done:        int   = 0
var _was_on_floor:      bool  = false
var _landing_decel_timer: float = 0.0

var carried_soul_id: String = ""
var _facing_right:   bool   = true

# ── Fall damage ───────────────────────────────────────────────────────────────
var _fall_start_y: float = 0.0
const FALL_SAFE_HEIGHT:   float = 320.0
const FALL_DAMAGE_HEIGHT: float = 480.0

# ── Upgrade flags (populated in _ready) ───────────────────────────────────────
var _upgrade_quick_pickup:     bool  = false
var _upgrade_double_jump:      bool  = false
var _upgrade_soft_landing:     bool  = false
var _upgrade_staff_purity:     bool  = false
var _upgrade_soul_shield:      bool  = false
var _upgrade_temptation_resist: bool = false
var _soul_shield_timer:        float = 0.0

# ── Sin visuals ───────────────────────────────────────────────────────────────
const SIN_SHADER_PATH := "res://shaders/player_sin.gdshader"
const SIN_TEXTURES := [
	"res://Assets/OurAssets/player_clean.png",
	"res://Assets/OurAssets/player_tainted.png",
	"res://Assets/OurAssets/player_fallen.png",
	"res://Assets/OurAssets/player_demon.png",
]
const SIN_THRESHOLDS := [0, 30, 60, 85]
# modulate per state: clean → tainted → fallen → demon
const SIN_MODULATES := [
	Color(1.05, 1.00, 0.88, 1.0),
	Color(0.95, 0.88, 0.88, 1.0),
	Color(0.80, 0.70, 0.90, 1.0),
	Color(0.75, 0.60, 0.65, 1.0),
]
const SIN_BLEND_SPEED := 2.5

var _sin_textures: Array = []
var _sin_state_idx: int  = 0
var _sin_blend_t: float  = 0.0
var _sin_modulate: Color = Color.WHITE

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _anim: AnimationPlayer    = $AnimationPlayer
@onready var _staff_area: Area2D       = $StaffArea
@onready var _soul_visual: Node2D      = $SoulCarryVisual
@onready var _sprite: Sprite2D         = $Sprite2D

func _ready() -> void:
	add_to_group("player")
	_apply_upgrades()
	_soul_visual.visible = false
	_staff_area.monitoring = false
	_setup_sin_shader()

func _setup_sin_shader() -> void:
	for path in SIN_TEXTURES:
		var tex = load(path) if ResourceLoader.exists(path) else null
		_sin_textures.append(tex)
	var shader := load(SIN_SHADER_PATH) as Shader
	if not shader:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if _sin_textures[0]:
		_sprite.texture = _sin_textures[0]
	var next_tex = _sin_textures[1] if _sin_textures[1] else _sin_textures[0]
	mat.set_shader_parameter("texture_next", next_tex)
	mat.set_shader_parameter("blend_t", 0.0)
	_sprite.material = mat
	_sprite.modulate = SIN_MODULATES[0]

func _apply_upgrades() -> void:
	if not SaveManager:
		return
	if SaveManager.get_upgrade_level("vitality") > 0:
		max_hp = 3 + SaveManager.get_upgrade_level("vitality")
		current_hp = max_hp
	if SaveManager.get_upgrade_level("speed") > 0:
		walk_speed *= 1.0 + 0.15 * SaveManager.get_upgrade_level("speed")
	if SaveManager.get_upgrade_level("jump") > 0:
		jump_force *= 1.0 + 0.20 * SaveManager.get_upgrade_level("jump")
	if SaveManager.get_upgrade_level("staff_reach") > 0:
		staff_range += 40.0
	if SaveManager.get_upgrade_level("staff_cooldown") > 0:
		staff_cooldown -= 1.5
	_upgrade_quick_pickup      = SaveManager.get_upgrade_level("quick_pickup") > 0
	_upgrade_double_jump       = SaveManager.get_upgrade_level("double_jump") > 0
	_upgrade_soft_landing      = SaveManager.get_upgrade_level("soft_landing") > 0
	_upgrade_staff_purity      = SaveManager.get_upgrade_level("staff_purity") > 0
	_upgrade_soul_shield       = SaveManager.get_upgrade_level("soul_shield") > 0
	_upgrade_temptation_resist = SaveManager.get_upgrade_level("temptation_resist") > 0

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	_tick_timers(delta)
	_handle_coyote(delta)
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_jump(delta)
	_handle_staff()
	_check_fall_damage()
	move_and_slide()
	_update_state()
	_update_animation()
	_update_sin_shader(delta)

# ── Timers ────────────────────────────────────────────────────────────────────
func _tick_timers(delta: float) -> void:
	_staff_timer       = maxf(_staff_timer - delta, 0.0)
	_invincibility_timer = maxf(_invincibility_timer - delta, 0.0)
	_soul_shield_timer = maxf(_soul_shield_timer - delta, 0.0)
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta

# ── Gravity ───────────────────────────────────────────────────────────────────
func _handle_gravity(delta: float) -> void:
	if is_on_floor():
		if not _was_on_floor and absf(velocity.x) > 50.0:
			_landing_decel_timer = 0.05
		velocity.y = 0.0
		return
	if _jump_held and velocity.y < 0.0:
		velocity.y += gravity * 0.6 * delta
	else:
		velocity.y += gravity * delta
	velocity.y = minf(velocity.y, max_fall_speed)

# ── Horizontal movement ───────────────────────────────────────────────────────
func _handle_movement(delta: float) -> void:
	if state in [State.STAFF_SWING, State.PICKUP, State.DEAD]:
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		return

	var dir: float = Input.get_axis("move_left", "move_right")
	var accel: float = acceleration if is_on_floor() else air_acceleration
	var effective_decel: float = deceleration
	if _landing_decel_timer > 0.0:
		effective_decel = deceleration * 2.2
		_landing_decel_timer -= delta

	if dir != 0.0:
		_facing_right = dir > 0.0
		_sprite.flip_h = not _facing_right
		velocity.x = move_toward(velocity.x, dir * walk_speed, accel * delta)
		_tutorial_hint("move")
	else:
		velocity.x = move_toward(velocity.x, 0.0, effective_decel * delta)

# ── Coyote time ───────────────────────────────────────────────────────────────
func _handle_coyote(delta: float) -> void:
	if _was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		_coyote_timer = 0.12
	elif is_on_floor():
		_coyote_timer = 0.0
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_was_on_floor = is_on_floor()

func _can_jump() -> bool:
	return is_on_floor() or _coyote_timer > 0.0

# ── Jump ──────────────────────────────────────────────────────────────────────
func _handle_jump(delta: float) -> void:
	if state in [State.DEAD, State.PICKUP]:
		return

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = 0.1

	if _jump_buffer_timer > 0.0 and _can_jump():
		velocity.y = -jump_force
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_held = true
		_jump_hold_timer = 0.0
		_tutorial_hint("jump")
	elif _jump_buffer_timer > 0.0 and _upgrade_double_jump \
			and not is_on_floor() and _coyote_timer <= 0.0 and _jumps_done < 1:
		velocity.y = -jump_force
		_jump_buffer_timer = 0.0
		_jump_held = true
		_jump_hold_timer = 0.0
		_jumps_done += 1

	if Input.is_action_pressed("jump") and _jump_held:
		_jump_hold_timer += delta
		if _jump_hold_timer >= 0.25:
			_jump_held = false
	else:
		if _jump_held and velocity.y < 0.0:
			velocity.y = maxf(velocity.y, -min_jump_force)
		_jump_held = false

	if is_on_floor():
		_jump_held = false
		_jump_hold_timer = 0.0
		_jumps_done = 0

# ── Staff ─────────────────────────────────────────────────────────────────────
func _handle_staff() -> void:
	if state in [State.DEAD, State.PICKUP, State.CARRYING]:
		return
	if _staff_timer > 0.0:
		return
	if not Input.is_action_just_pressed("action"):
		return

	state = State.STAFF_SWING
	_staff_timer = staff_cooldown
	_anim.play("player_staff_swing")
	_tutorial_hint("staff")

	var fx_origin: Vector2 = global_position + Vector2(40.0 if _facing_right else -40.0, -10.0)
	_spawn_fx("staff_swing", fx_origin, _facing_right)

	_staff_area.monitoring = true
	await get_tree().create_timer(0.15).timeout
	var hit := _apply_staff_hit()
	_staff_area.monitoring = false

	if hit:
		Engine.time_scale = 0.0
		await get_tree().create_timer(0.08, true, false, true).timeout
		Engine.time_scale = 1.0

	await _anim.animation_finished
	if state == State.STAFF_SWING:
		state = State.IDLE

	if not _upgrade_staff_purity:
		SaveManager.add_sin(staff_sin_cost)
	staff_used.emit()

func _apply_staff_hit() -> bool:
	var hit := false
	for body in _staff_area.get_overlapping_bodies():
		if body.is_in_group("enemy"):
			var direction: Vector2 = Vector2.RIGHT if _facing_right else Vector2.LEFT
			if body.has_method("receive_knockback"):
				body.receive_knockback(direction * 280.0, 3.5)
			hit = true
	return hit

# ── Fall damage ───────────────────────────────────────────────────────────────
func _check_fall_damage() -> void:
	if velocity.y < 0.0 and not is_on_floor():
		_fall_start_y = global_position.y

	if is_on_floor() and _fall_start_y > 0.0:
		var fallen: float = global_position.y - _fall_start_y
		var threshold: float = FALL_DAMAGE_HEIGHT
		if _upgrade_soft_landing:
			threshold *= 1.5
		if fallen > threshold:
			_take_damage(1)
		_fall_start_y = 0.0

# ── Damage & death ────────────────────────────────────────────────────────────

## Called by external hazards (Pursuer, traps, etc.).
## Applies damage and, if the hit landed, adds an instant velocity impulse.
func receive_hit(amount: int, knockback: Vector2) -> void:
	var was_blocked := _invincibility_timer > 0.0 or _soul_shield_timer > 0.0
	_take_damage(amount)
	if not was_blocked:
		velocity += knockback

func _take_damage(amount: int) -> void:
	if _invincibility_timer > 0.0:
		return
	if _soul_shield_timer > 0.0:
		return
	current_hp -= amount
	_invincibility_timer = 1.2
	hp_changed.emit(current_hp, max_hp)
	if current_hp <= 0:
		_die()
	else:
		_shake_camera(0.15, 8.0)
		if _anim:
			_anim.play("player_hurt")

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	if _anim:
		_anim.play("player_death")
	_shake_camera(0.3, 12.0)
	_spawn_fx("death", global_position)
	if carried_soul_id != "":
		soul_dropped.emit(carried_soul_id, global_position)
		_drop_soul()
	player_died.emit()

# ── Soul interaction ──────────────────────────────────────────────────────────
func pick_up_soul(soul_id: String) -> void:
	if carried_soul_id != "":
		return
	carried_soul_id = soul_id
	if _upgrade_quick_pickup:
		_finish_pickup()
	else:
		state = State.PICKUP
		_anim.play("player_pickup")
		_pickup_timer = 0.6
		await get_tree().create_timer(0.6).timeout
		_finish_pickup()

func _finish_pickup() -> void:
	state = State.CARRYING
	_soul_visual.visible = true
	soul_picked_up.emit(carried_soul_id)
	if _upgrade_soul_shield:
		_soul_shield_timer = 3.0

func deliver_soul() -> void:
	if carried_soul_id == "":
		return
	soul_delivered.emit(carried_soul_id)
	_drop_soul()

func _drop_soul() -> void:
	carried_soul_id = ""
	_soul_visual.visible = false
	if state == State.CARRYING:
		state = State.IDLE

# ── State update ──────────────────────────────────────────────────────────────
func _update_state() -> void:
	if state in [State.DEAD, State.STAFF_SWING, State.PICKUP]:
		return
	var on_floor: bool = is_on_floor()
	var moving: bool = absf(velocity.x) > 10.0
	if on_floor:
		state = State.CARRYING if carried_soul_id != "" else (State.WALK if moving else State.IDLE)
	else:
		state = State.JUMP if velocity.y < 0.0 else State.FALL

# ── Animation ─────────────────────────────────────────────────────────────────
func _update_animation() -> void:
	var anim_name: String = _state_to_anim()
	if _anim.current_animation != anim_name:
		_anim.play(anim_name)

func _state_to_anim() -> String:
	match state:
		State.IDLE:        return "player_carry_idle" if carried_soul_id != "" else "player_idle"
		State.WALK:        return "player_carry_walk" if carried_soul_id != "" else "player_walk"
		State.JUMP:        return "player_jump"
		State.FALL:        return "player_fall"
		State.STAFF_SWING: return "player_staff_swing"
		State.PICKUP:      return "player_pickup"
		State.CARRYING:    return "player_carry_idle"
		State.DEAD:        return "player_death"
	return "player_idle"

# ── Sin visuals ───────────────────────────────────────────────────────────────
func _update_sin_shader(delta: float) -> void:
	if not _sprite or not _sprite.material:
		return
	var sin_pct: int = SaveManager.get_sin() if SaveManager else 0

	# Визначаємо поточний та наступний стан
	var target_idx: int = 0
	for i in range(SIN_THRESHOLDS.size() - 1, -1, -1):
		if sin_pct >= SIN_THRESHOLDS[i]:
			target_idx = i
			break

	var next_idx: int = mini(target_idx + 1, SIN_TEXTURES.size() - 1)

	# Частка всередині поточного діапазону (0..1)
	var lo: int = SIN_THRESHOLDS[target_idx]
	var hi: int = SIN_THRESHOLDS[next_idx] if next_idx != target_idx else 100
	var local_t: float = clamp(float(sin_pct - lo) / float(hi - lo), 0.0, 1.0)

	# Якщо перейшли в новий стан — свапаємо текстури
	if target_idx != _sin_state_idx:
		_sin_state_idx = target_idx
		if _sin_textures[target_idx]:
			_sprite.texture = _sin_textures[target_idx]
		_sin_blend_t = 0.0

	# Плавно змішуємо до наступного стану
	var target_blend: float = local_t
	_sin_blend_t = move_toward(_sin_blend_t, target_blend, SIN_BLEND_SPEED * delta)

	var mat := _sprite.material as ShaderMaterial
	var next_tex = _sin_textures[next_idx] if _sin_textures[next_idx] else _sin_textures[target_idx]
	mat.set_shader_parameter("texture_next", next_tex)
	mat.set_shader_parameter("blend_t", _sin_blend_t)

	# modulate — плавний перехід між кольорами станів
	var target_mod: Color = SIN_MODULATES[target_idx].lerp(SIN_MODULATES[next_idx], local_t)
	_sin_modulate = _sin_modulate.lerp(target_mod, delta * SIN_BLEND_SPEED)
	_sprite.modulate = _sin_modulate

# ── Public helpers ────────────────────────────────────────────────────────────
func _shake_camera(duration: float, intensity: float) -> void:
	if not is_inside_tree():
		return
	var shaker: Node = get_node_or_null("/root/CameraShake")
	if shaker and shaker.has_method("shake"):
		shaker.shake(duration, intensity)

func get_staff_cooldown_ratio() -> float:
	return 1.0 - (_staff_timer / staff_cooldown)

func is_carrying() -> bool:
	return carried_soul_id != ""

func respawn(spawn_position: Vector2) -> void:
	global_position = spawn_position
	velocity = Vector2.ZERO
	current_hp = max_hp
	state = State.IDLE
	_invincibility_timer = 1.2
	_sprite.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_sprite, "modulate:a", 1.0, 0.4)
	hp_changed.emit(current_hp, max_hp)
	_anim.play("player_respawn_breath")
	_spawn_fx("respawn", global_position)

func _spawn_fx(preset: String, at: Vector2, facing_right: bool = true) -> void:
	if not is_inside_tree():
		return
	var fx: Node = get_node_or_null("/root/ParticleEffects")
	if fx and fx.has_method("spawn"):
		fx.spawn(preset, at, facing_right)

func _tutorial_hint(hint_id: String) -> void:
	if not is_inside_tree():
		return
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("show_hint"):
		tm.show_hint(hint_id)
