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

# ── Dimensions ────────────────────────────────────────────────────────────────
# Must match CollisionShape2D in Player.tscn. Used by LevelGenerator for
# spacing rules and by systems that need to know the character's footprint.
const PLAYER_WIDTH:  float = 60.0
const PLAYER_HEIGHT: float = 90.0

var state: State = State.IDLE

# ── Stats (base values, modified by upgrades at runtime) ──────────────────────
var walk_speed:       float = 180.0
var jump_force:       float = 600.0
var min_jump_force:   float = 240.0
var gravity:          float = 900.0
var max_fall_speed:   float = 600.0
var acceleration:     float = 800.0
var deceleration:     float = 1200.0
var air_acceleration: float = 500.0

var staff_range:    float = 80.0
var staff_cooldown: float = 4.5
var staff_sin_cost: int   = 1

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
# Highest point (smallest Y in Godot 2D) reached during the current airtime.
# Sentinel -INF means "not tracking yet" — set on the first off-floor frame
# or on landing so the next walk-off-ledge starts from the right baseline.
var _fall_start_y: float = -INF
# Tiered fall damage in multiples of MAX_JUMP_HEIGHT (200 px).
#   < 1.5 jumps  (300 px) → no damage   (a missed jump shouldn't punish)
#   1.5–2.5      (300–500) → 1 hp       (clearly overshot a row)
#   2.5–4        (500–800) → 2 hp       (multi-row fall, hurts hard)
#   > 4 jumps    (>800)    → death       (effectively jumped off the level)
# soft_landing upgrade scales every threshold by SOFT_LANDING_FACTOR.
const FALL_DAMAGE_TIERS := [
	{ "min_jumps": 1.5, "damage": 1 },
	{ "min_jumps": 2.5, "damage": 2 },
	{ "min_jumps": 4.0, "damage": 99 },  # 99 = instant kill via _take_damage
]
const SOFT_LANDING_FACTOR: float = 1.5

# ── Upgrade flags (populated in _ready) ───────────────────────────────────────
var _upgrade_quick_pickup:     bool  = false
var _upgrade_double_jump:      bool  = false
var _upgrade_soft_landing:     bool  = false
var _upgrade_staff_purity:     bool  = false
var _upgrade_soul_shield:      bool  = false
var _upgrade_temptation_resist: bool = false
var _soul_shield_timer:        float = 0.0
var _temp_double_jump_timer:   float = 0.0

# ── Sin visuals ───────────────────────────────────────────────────────────────
const SIN_SHADER_PATH := "res://shaders/player_sin.gdshader"
const SIN_TEXTURES := [
	"res://Assets/OurAssets/player_clean.png",
	"res://Assets/OurAssets/player_tainted.png",
	"res://Assets/OurAssets/player_fallen.png",
	"res://Assets/OurAssets/player_demon.png",
]
# ── Dark_Elves animation pack ─────────────────────────────────────────────────
const PLAYER_SPRITE_BASE := "res://Assets/rpg-platformer-game-assets/1_Main_character/Dark_Elves/PNG/PNG Sequences/"
# Maps Player state → anim-name we play on AnimatedSprite2D → Dark_Elves folder.
const PLAYER_ANIM_FOLDERS := {
	"player_idle":          "Idle",
	"player_walk":          "Walking",
	"player_jump":          "Jump Loop",
	"player_fall":          "Falling Down",
	"player_staff_swing":   "Slashing",
	"player_pickup":        "Idle",
	"player_carry_idle":    "Idle",
	"player_carry_walk":    "Walking",
	"player_hurt":          "Hurt",
	"player_death":         "Dying",
	"player_respawn_breath":"Idle",
}
const PLAYER_SPRITE_SCALE  := 0.15   # Dark_Elves ship on ~900×900 canvases
const PLAYER_SPRITE_FPS    := 12.0
const NON_LOOPING_ANIMS    := [
	"player_death", "player_staff_swing",
	"player_pickup", "player_hurt",
	"player_respawn_breath",
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
@onready var _anim: AnimationPlayer         = $AnimationPlayer
@onready var _staff_area: Area2D            = $StaffArea
@onready var _soul_visual: Node2D           = $SoulCarryVisual
@onready var _sprite: Sprite2D              = $Sprite2D
@onready var _anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")

func _ready() -> void:
	add_to_group("player")
	_apply_upgrades()
	_soul_visual.visible = false
	_staff_area.monitoring = false
	_setup_sin_shader()
	_load_player_frames()
	# LevelCamera (attached to the Camera2D child) calls make_current() in
	# its own _ready, so no manual takeover needed here.

func _setup_sin_shader() -> void:
	for path in SIN_TEXTURES:
		var tex = load(path) if ResourceLoader.exists(path) else null
		_sin_textures.append(tex)

	# Dark_Elves frames drive the visuals via AnimatedSprite2D
	# (_load_player_frames). The Sprite2D + shader path below is kept for
	# when the four sin-state PNGs ship; until then it no-ops and the
	# sin-modulate tint still applies to AnimatedSprite2D each frame.
	if not _sin_textures[0]:
		_sin_modulate = SIN_MODULATES[0]
		if _anim_sprite:
			_anim_sprite.modulate = _sin_modulate
		return

	_sprite.texture = _sin_textures[0]

	var shader := load(SIN_SHADER_PATH) as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var next_tex = _sin_textures[1] if _sin_textures[1] else _sin_textures[0]
		mat.set_shader_parameter("texture_next", next_tex)
		mat.set_shader_parameter("blend_t", 0.0)
		_sprite.material = mat
	_sprite.modulate = SIN_MODULATES[0]

## Build SpriteFrames from the Dark_Elves PNG sequences and play idle.
## Each anim points at a folder under PLAYER_SPRITE_BASE. Missing folders
## skip quietly — state falls back to existing AnimationPlayer path.
func _load_player_frames() -> void:
	if not _anim_sprite:
		return
	var sf := SpriteFrames.new()
	var any_loaded := false
	for anim_name in PLAYER_ANIM_FOLDERS.keys():
		var folder: String = PLAYER_ANIM_FOLDERS[anim_name]
		var dir_path: String = "%s%s/" % [PLAYER_SPRITE_BASE, folder]
		var frames: Array = _collect_pngs(dir_path)
		if frames.is_empty():
			continue
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, not (anim_name in NON_LOOPING_ANIMS))
		sf.set_animation_speed(anim_name, PLAYER_SPRITE_FPS)
		for tex in frames:
			sf.add_frame(anim_name, tex)
		any_loaded = true
	if not any_loaded:
		if is_inside_tree():
			var d: Node = get_node_or_null("/root/DebugOverlay")
			if d and d.has_method("warn"):
				d.warn("Player: Dark_Elves frames not found under " + PLAYER_SPRITE_BASE)
		return
	_anim_sprite.sprite_frames = sf
	_anim_sprite.scale = Vector2(PLAYER_SPRITE_SCALE, PLAYER_SPRITE_SCALE)
	if sf.has_animation("player_idle"):
		_anim_sprite.play("player_idle")

func _collect_pngs(path: String) -> Array:
	var frames: Array = []
	var dir := DirAccess.open(path)
	if not dir:
		return frames
	# In exported builds DirAccess lists imported markers (.png.import or
	# .png.remap) instead of the raw .png. Accept both, strip the suffix, and
	# dedupe — load() resolves the canonical .png path to the .ctex anyway.
	var seen := {}
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and not fname.begins_with("."):
			var canonical: String = ""
			if fname.ends_with(".png"):
				canonical = fname
			elif fname.ends_with(".png.import"):
				canonical = fname.substr(0, fname.length() - 7)
			elif fname.ends_with(".png.remap"):
				canonical = fname.substr(0, fname.length() - 6)
			if canonical != "" and not seen.has(canonical):
				seen[canonical] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var files: Array = seen.keys()
	files.sort()
	for f in files:
		var tex: Texture2D = load(path + f) as Texture2D
		if tex:
			frames.append(tex)
	return frames


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
		staff_range += 40.0 * SaveManager.get_upgrade_level("staff_reach")
	if SaveManager.get_upgrade_level("staff_cooldown") > 0:
		staff_cooldown = maxf(0.5, staff_cooldown - 1.5 * SaveManager.get_upgrade_level("staff_cooldown"))
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
	_staff_timer             = maxf(_staff_timer - delta, 0.0)
	_invincibility_timer     = maxf(_invincibility_timer - delta, 0.0)
	_soul_shield_timer       = maxf(_soul_shield_timer - delta, 0.0)
	_temp_double_jump_timer  = maxf(_temp_double_jump_timer - delta, 0.0)
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta

# ── Gravity ───────────────────────────────────────────────────────────────────
func _handle_gravity(delta: float) -> void:
	if is_on_floor():
		if not _was_on_floor:
			# Just touched the floor this frame — pick the right thud based on
			# how fast we were falling. The pre-zeroed velocity.y still holds
			# the impact speed because we haven't reset it yet.
			if SoundManager:
				var land_key: String = "land_hard" if velocity.y > 500.0 else "land_soft"
				SoundManager.play_sfx("player", land_key)
			if absf(velocity.x) > 50.0:
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
		if _anim_sprite:
			_anim_sprite.flip_h = not _facing_right
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
	elif _jump_buffer_timer > 0.0 and (_upgrade_double_jump or _temp_double_jump_timer > 0.0) \
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

	# Flip the staff hitbox to the side the player is facing. Without this
	# the shape sits at its scene position (right side only) and swings to
	# the left silently miss every enemy.
	_orient_staff_area()
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
				body.receive_knockback(direction * 280.0, 4.0)
			hit = true
	return hit

# Mirror the StaffArea's collision shape to the player's facing side. The
# scene-time position is hard-coded to the right (+x); without flipping,
# left-facing swings can never overlap an enemy.
func _orient_staff_area() -> void:
	if not _staff_area:
		return
	var shape: CollisionShape2D = _staff_area.get_node_or_null("CollisionShape2D")
	if not shape:
		return
	var x: float = absf(shape.position.x)
	shape.position.x = x if _facing_right else -x

# ── Fall damage ───────────────────────────────────────────────────────────────
func _check_fall_damage() -> void:
	# Per-frame entry point: dispatches to a pure helper using current physics
	# state. The helper is split out so unit tests can drive it directly
	# without faking CharacterBody2D's native is_on_floor().
	_update_fall_tracking(is_on_floor(), global_position.y)

# Pure, testable: updates _fall_start_y and applies tiered damage on landing.
#   on_floor   — physics floor state for this frame
#   current_y  — global Y (Godot 2D: smaller = higher on screen)
# Sentinel _fall_start_y == -INF means "not tracking yet" (set on the very
# first off-floor frame or right after a landing).
func _update_fall_tracking(on_floor: bool, current_y: float) -> void:
	if on_floor:
		if _fall_start_y != -INF:
			var fallen: float = current_y - _fall_start_y
			_apply_fall_damage_for(fallen)
		# Re-baseline at the current floor Y so a walk-off-ledge next frame
		# correctly measures fall distance from this point.
		_fall_start_y = current_y
		return
	# In air: track the highest point reached (smallest Y).
	if _fall_start_y == -INF or current_y < _fall_start_y:
		_fall_start_y = current_y

# Pure, testable: maps a fallen distance to the worst applicable tier and
# calls _take_damage. Skips when fallen ≤ 0 (no real fall).
func _apply_fall_damage_for(fallen: float) -> void:
	if fallen <= 0.0:
		return
	var threshold_scale: float = SOFT_LANDING_FACTOR if _upgrade_soft_landing else 1.0
	# Walk the tier table from highest to lowest so the worst applicable
	# tier wins. Tiers are in jump-heights (200 px each).
	for j in range(FALL_DAMAGE_TIERS.size() - 1, -1, -1):
		var tier: Dictionary = FALL_DAMAGE_TIERS[j]
		var threshold: float = LevelGenerator.MAX_JUMP_HEIGHT \
				* float(tier.min_jumps) * threshold_scale
		if fallen > threshold:
			_take_damage(int(tier.damage))
			return

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
		if SoundManager:
			SoundManager.play_sfx("player", "hurt")

func _die() -> void:
	state = State.DEAD
	velocity = Vector2.ZERO
	# Awaited staff swings won't reach their cleanup line if we die mid-swing.
	if _staff_area:
		_staff_area.monitoring = false
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
	if SoundManager:
		SoundManager.play_sfx("souls", "pickup_resonance")
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
	if SoundManager:
		SoundManager.play_sfx("souls", "delivered")
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
	# Prefer AnimatedSprite2D (Dark_Elves frames) when present.
	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(anim_name):
		if _anim_sprite.animation != anim_name:
			_anim_sprite.play(anim_name)
	# Fall back to AnimationPlayer driven Sprite2D.
	if _anim and _anim.has_animation(anim_name) and _anim.current_animation != anim_name:
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
	# Modulate-tint even without the shader so Dark_Elves frames still
	# colour-shift with sin. Shader-blend path still runs if present.
	if not _sprite:
		return
	var sin_pct: int = int(SaveManager.get_sin()) if SaveManager else 0

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
	if mat:
		var next_tex = _sin_textures[next_idx] if _sin_textures[next_idx] else _sin_textures[target_idx]
		mat.set_shader_parameter("texture_next", next_tex)
		mat.set_shader_parameter("blend_t", _sin_blend_t)

	# modulate — плавний перехід між кольорами станів.
	# Зберігаємо існуючу alpha, щоб не перебивати fade-in після respawn.
	var target_mod: Color = SIN_MODULATES[target_idx].lerp(SIN_MODULATES[next_idx], local_t)
	_sin_modulate = _sin_modulate.lerp(target_mod, delta * SIN_BLEND_SPEED)
	var tinted := _sin_modulate
	tinted.a = _sprite.modulate.a
	_sprite.modulate = tinted
	if _anim_sprite:
		var tinted_anim := _sin_modulate
		tinted_anim.a = _anim_sprite.modulate.a
		_anim_sprite.modulate = tinted_anim

# ── Public helpers ────────────────────────────────────────────────────────────
func _shake_camera(duration: float, intensity: float) -> void:
	if not is_inside_tree():
		return
	var shaker: Node = get_node_or_null("/root/CameraShake")
	if shaker and shaker.has_method("shake"):
		shaker.shake(duration, intensity)

func heal(amount: int) -> void:
	current_hp = mini(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)

func apply_invincibility(duration: float) -> void:
	_invincibility_timer = maxf(_invincibility_timer, duration)

func apply_temp_double_jump(duration: float) -> void:
	_temp_double_jump_timer = maxf(_temp_double_jump_timer, duration)

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
	if _anim_sprite:
		_anim_sprite.modulate.a = 0.0
		tw.parallel().tween_property(_anim_sprite, "modulate:a", 1.0, 0.4)
	hp_changed.emit(current_hp, max_hp)
	if _anim and _anim.has_animation("player_respawn_breath"):
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
