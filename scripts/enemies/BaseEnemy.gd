extends CharacterBody2D

# ── Signals ───────────────────────────────────────────────────────────────────
signal enemy_alerted(enemy: Node2D)
signal enemy_lost_target(enemy: Node2D)

# ── State ─────────────────────────────────────────────────────────────────────
enum State { PATROL, ALERT, CHASE, GIVE_UP, RETURN, STUNNED }

var state: State = State.PATROL

# ── Stats (override in subclass or set via configure()) ───────────────────────
@export var move_speed:        float = 80.0
@export var chase_speed_mult:  float = 1.2
@export var detection_range:   float = 200.0
@export var chase_duration:    float = 6.0
@export var alert_duration:    float = 1.0
@export var patrol_distance:   float = 120.0

# ── Contact damage ────────────────────────────────────────────────────────────
@export var contact_damage:    int   = 1
@export var contact_range:     float = 72.0
@export var contact_knockback: float = 280.0
const HIT_COOLDOWN_TIME: float = 1.0

# ── Config binding ────────────────────────────────────────────────────────────
## If set in the scene, BaseEnemy._ready() auto-loads stats from
## enemies_config.json entry with this id and pulls sprite frames from
## enemy_sprite_map.json. Subclasses (ShadowLost, PaleWanderer) that call
## _apply_enemy_config() themselves can leave this empty.
@export var enemy_id: String = ""

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player: CharacterBody2D = null
var _chase_timer:    float = 0.0
var _alert_timer:    float = 0.0
var _stun_timer:     float = 0.0
var _attack_timer:   float = 0.0
var _give_up_timer:  float = 2.5
var _last_known_pos: Vector2 = Vector2.ZERO
var _patrol_origin:  Vector2 = Vector2.ZERO
var _patrol_dir:     float   = 1.0
var _facing_right:   bool    = true
var _hit_cooldown:   float   = 0.0
var _config_applied: bool    = false

const GRAVITY: float       = 900.0
const JUMP_VELOCITY: float = -650.0   # clears ~235 px — enough for max platform spacing (200 px)

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _anim:           AnimationPlayer     = get_node_or_null("AnimationPlayer")
@onready var _sprite:         Sprite2D            = get_node_or_null("Sprite2D")
@onready var _anim_sprite:    AnimatedSprite2D    = get_node_or_null("AnimatedSprite2D")
@onready var _alert_icon:     Node2D              = get_node_or_null("AlertIcon")
@onready var _breath_player:  AudioStreamPlayer2D = get_node_or_null("BreathPlayer")

# Downward raycasts placed just ahead of each foot to detect platform edges.
var _ray_left:  RayCast2D = null
var _ray_right: RayCast2D = null

var _jump_cooldown: float = 0.0

func _ready() -> void:
	_patrol_origin = global_position
	_build_edge_rays()
	if _alert_icon:
		_alert_icon.visible = false
	# Auto-apply config when enemy_id is set via the scene and a subclass
	# hasn't already applied it from its own _ready().
	if enemy_id != "" and not _config_applied:
		_apply_enemy_config(enemy_id)
	add_to_group("enemy")
	_find_player()
	if _anim_sprite and _anim_sprite.sprite_frames:
		_anim_sprite.play("enemy_idle")

func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D
	# Enemies and the player must not physically block each other — contact
	# damage is handled via distance check, not physics collision. Without this
	# an enemy that falls on top of the player gets "stuck" on their head
	# because is_on_floor() returns true (player acts as a floor).
	if _player:
		add_collision_exception_with(_player)
		_player.add_collision_exception_with(self)

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not _player:
		_find_player()
	_apply_gravity(delta)
	_tick_timers(delta)
	_update_spatial_audio()

	match state:
		State.PATROL:   _do_patrol(delta)
		State.ALERT:    _do_alert(delta)
		State.CHASE:    _do_chase(delta)
		State.GIVE_UP:  _do_give_up(delta)
		State.RETURN:   _do_return(delta)
		State.STUNNED:  _do_stunned()

	move_and_slide()
	_update_facing()
	_update_animation()
	_check_player_contact(delta)

# ── Gravity ───────────────────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

# ── Timers ────────────────────────────────────────────────────────────────────
func _tick_timers(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer -= delta
		if _stun_timer <= 0.0 and state == State.STUNNED:
			_enter_patrol()
	if _attack_timer > 0.0:
		_attack_timer -= delta
	if _chase_timer > 0.0:
		_chase_timer -= delta
	if _alert_timer > 0.0:
		_alert_timer -= delta
	if _give_up_timer > 0.0 and state == State.GIVE_UP:
		_give_up_timer -= delta
	if _jump_cooldown > 0.0:
		_jump_cooldown -= delta

# ── Edge detection setup ─────────────────────────────────────────────────────
func _build_edge_rays() -> void:
	var col: CollisionShape2D = get_node_or_null("CollisionShape2D")
	var half_w: float = 8.0
	var half_h: float = 16.0
	if col and col.shape is RectangleShape2D:
		half_w = (col.shape as RectangleShape2D).size.x / 2.0
		half_h = (col.shape as RectangleShape2D).size.y / 2.0

	for side in [-1, 1]:
		var ray := RayCast2D.new()
		ray.position = Vector2(side * (half_w + 2.0), half_h)
		ray.target_position = Vector2(0.0, 12.0)  # short downward cast
		ray.collision_mask = 1
		ray.enabled = true
		add_child(ray)
		if side == -1:
			_ray_left = ray
		else:
			_ray_right = ray

# ── PATROL ────────────────────────────────────────────────────────────────────
func _do_patrol(_delta: float) -> void:
	# Collect all reversal triggers; apply at most one flip per frame so
	# simultaneous conditions (e.g. wall + boundary) don't cancel each other.
	var should_reverse := false

	var dist_from_origin: float = global_position.x - _patrol_origin.x
	if absf(dist_from_origin) >= patrol_distance:
		should_reverse = true

	if is_on_wall():
		should_reverse = true

	# Edge detection: only meaningful while standing (not while falling).
	if is_on_floor() and not should_reverse:
		var leading_ray: RayCast2D = _ray_right if _patrol_dir > 0.0 else _ray_left
		if leading_ray and not leading_ray.is_colliding():
			should_reverse = true

	if should_reverse:
		_patrol_dir *= -1.0

	velocity.x = move_speed * _patrol_dir

	if _can_see_player():
		_enter_alert()

func _can_see_player() -> bool:
	if not _player:
		return false
	if _player.get("_soul_shield_timer") and _player._soul_shield_timer > 0.0:
		return false
	return global_position.distance_to(_player.global_position) <= detection_range

# ── ALERT ─────────────────────────────────────────────────────────────────────
func _enter_alert() -> void:
	state = State.ALERT
	_alert_timer = alert_duration
	velocity.x = 0.0
	if _alert_icon:
		_alert_icon.visible = true
	_last_known_pos = _player.global_position
	enemy_alerted.emit(self)
	_play_sound("alert")
	_tutorial_hint("enemy_nearby")

func _do_alert(_delta: float) -> void:
	if _alert_timer <= 0.0:
		if _alert_icon:
			_alert_icon.visible = false
		_enter_chase()

# ── CHASE ─────────────────────────────────────────────────────────────────────
func _enter_chase() -> void:
	state = State.CHASE
	_chase_timer = chase_duration
	_play_sound("chase")
	_tutorial_hint("enemy_chasing")

func _do_chase(_delta: float) -> void:
	if not _player:
		_enter_give_up()
		return

	if _player.get("_soul_shield_timer") and _player._soul_shield_timer > 0.0:
		_enter_give_up()
		return

	if _chase_timer <= 0.0:
		_enter_give_up()
		return

	_last_known_pos = _player.global_position
	var dir: float = sign(_player.global_position.x - global_position.x)
	velocity.x = move_speed * chase_speed_mult * dir

	# Jump toward player only when they are stably on a higher platform AND
	# there is actually a solid surface above us to land on.
	if is_on_floor() and _jump_cooldown <= 0.0:
		var player_stable: bool = absf(_player.velocity.y) < 50.0
		if player_stable and _player.global_position.y < global_position.y - 60.0:
			if _platform_exists_above(_player.global_position.y):
				velocity.y = JUMP_VELOCITY
				_jump_cooldown = 1.5

	# Stop horizontal movement when hitting a wall — but only while grounded
	# (velocity.y >= 0). During a jump (velocity.y < 0) keep momentum so the
	# enemy actually clears the platform edge above.
	if is_on_wall() and velocity.y >= 0.0:
		velocity.x = 0.0

# ── GIVE UP ───────────────────────────────────────────────────────────────────
func _enter_give_up() -> void:
	state = State.GIVE_UP
	_give_up_timer = 2.5
	velocity.x = 0.0
	_show_question_mark()
	enemy_lost_target.emit(self)
	_play_sound("give_up")

func _do_give_up(_delta: float) -> void:
	var dir: float = sign(_last_known_pos.x - global_position.x)
	velocity.x = move_speed * 0.6 * dir

	var reached: bool = absf(global_position.x - _last_known_pos.x) < 16.0
	if reached or _give_up_timer <= 0.0:
		_hide_question_mark()
		_enter_patrol()

# ── RETURN ────────────────────────────────────────────────────────────────────
# RETURN більше не потрібен — ворог патрулює ту платформу де зупинився.
# Залишено у enum для сумісності; одразу переходимо в PATROL.
func _do_return(_delta: float) -> void:
	_enter_patrol()

# ── Jump helpers ──────────────────────────────────────────────────────────────

## Returns true if there is a solid platform between the enemy and target_y.
## Casts a ray straight up from the enemy's position to just above target_y.
## Without this check the enemy would jump into empty air when the player is
## on a platform that is off to the side but at a higher Y level.
func _platform_exists_above(target_y: float) -> bool:
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(
		global_position,
		Vector2(global_position.x, target_y - 4.0),
		collision_mask
	)
	params.exclude = [self]
	var result := space.intersect_ray(params)
	return not result.is_empty()

# ── PATROL entry ──────────────────────────────────────────────────────────────
func _enter_patrol() -> void:
	state = State.PATROL
	_patrol_origin = global_position  # anchor to wherever the enemy currently stands

# ── STUNNED ───────────────────────────────────────────────────────────────────
func _do_stunned() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * get_physics_process_delta_time())

## Teleport enemy back to patrol origin and resume patrol.
## Called on player respawn so enemies don't cluster at the spawn point.
func reset_to_patrol() -> void:
	global_position = _patrol_origin
	velocity        = Vector2.ZERO
	state           = State.PATROL
	_hit_cooldown   = 0.0

func stun(duration: float) -> void:
	state = State.STUNNED
	_stun_timer = maxf(_stun_timer, duration)
	_hit_cooldown = maxf(_hit_cooldown, duration)
	velocity.x = 0.0
	_play_sound("stun")

func receive_knockback(direction: Vector2, stun_duration: float) -> void:
	state = State.STUNNED
	_stun_timer = maxf(_stun_timer, stun_duration)
	_hit_cooldown = maxf(_hit_cooldown, stun_duration)
	velocity = direction
	_play_sound("stun")

# ── Soul pickup alert (called by level when player picks up soul) ──────────────
func on_soul_picked_up_nearby(pickup_position: Vector2, alert_radius: float) -> void:
	if state != State.PATROL:
		return
	if global_position.distance_to(pickup_position) <= alert_radius:
		if _player:
			_last_known_pos = pickup_position
			_enter_alert()

# ── Spatial audio ─────────────────────────────────────────────────────────────
func _update_spatial_audio() -> void:
	if not _player or not _breath_player or not _breath_player.stream:
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist < 300.0 and state in [State.PATROL, State.ALERT]:
		if not _breath_player.playing:
			_breath_player.play()
		_breath_player.volume_db = lerp(-20.0, -6.0, 1.0 - (dist / 300.0))
	else:
		_breath_player.stop()

# ── Config loading ────────────────────────────────────────────────────────────
## Load one entry from res://enemies_config.json by id and apply it to this
## instance. Populates stats (move_speed, detection_range, patrol_distance,
## alert_duration) and generates a solid-colour placeholder sprite from
## placeholder_color + size. Call from a subclass _ready() before super._ready().
func _apply_enemy_config(id: String, config_path: String = "res://enemies_config.json") -> void:
	if _config_applied:
		return
	_config_applied = true
	var file := FileAccess.open(config_path, FileAccess.READ)
	if not file:
		push_warning("BaseEnemy: cannot open " + config_path)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return
	for entry in parsed.get("enemies", []):
		if entry.get("id", "") != id:
			continue
		move_speed      = float(entry.get("move_speed",      move_speed))
		detection_range = float(entry.get("detection_range", detection_range))
		patrol_distance = float(entry.get("patrol_distance", patrol_distance))
		alert_duration  = float(entry.get("alert_duration",  alert_duration))

		# Try to load real animated sprites first; fall back to a solid-colour
		# placeholder if the sprite map or asset folder is unavailable.
		if not _load_sprite_frames_from_map(id):
			var col := Color(entry.get("placeholder_color", "#888888")) as Color
			var sz_raw: Variant = entry.get("size", [20, 32])
			var w: int = 20
			var h: int = 32
			if sz_raw is Array and (sz_raw as Array).size() == 2:
				w = int((sz_raw as Array)[0])
				h = int((sz_raw as Array)[1])
			_make_placeholder_sprite(col, Vector2(w, h))
		return

## Load animation PNG sequences for enemy_id from enemy_sprite_map.json
## into an AnimatedSprite2D child (if one is present). Returns true if at
## least one animation loaded successfully.
func _load_sprite_frames_from_map(id: String) -> bool:
	if not _anim_sprite:
		return false
	var map_file := FileAccess.open("res://enemy_sprite_map.json", FileAccess.READ)
	if not map_file:
		return false
	var map: Variant = JSON.parse_string(map_file.get_as_text())
	map_file.close()
	if not (map is Dictionary):
		return false

	var base_path:    String = map.get("base_path", "res://Assets/enemies/")
	var anim_subpath: String = map.get("anim_subpath", "PNG/PNG Sequences/")
	var entry: Dictionary = map.get("enemies", {}).get(id, {})
	if entry.is_empty():
		return false

	var pack:      String     = entry.get("pack", "")
	var character: String     = entry.get("character", "")
	var anims:     Dictionary = entry.get("animations", {})
	# Optional per-circle override: a single enemy id (e.g. "skeleton") can
	# upgrade to a fancier character folder as the player descends. Falls
	# through to the base `character` when the current circle isn't listed.
	var by_circle: Dictionary = entry.get("character_by_circle", {})
	if not by_circle.is_empty() and LevelConfig and GameManager:
		var circle_str: String = str(LevelConfig.get_circle(GameManager.current_level_id))
		var override: String = by_circle.get(circle_str, "")
		if override != "":
			character = override
	if pack == "" or character == "" or anims.is_empty():
		return false

	var sf := SpriteFrames.new()
	var any_loaded := false
	for anim_name in anims.keys():
		var folder: String = anims[anim_name]
		var full_path: String = "%s%s/%s/%s%s/" % [base_path, pack, character, anim_subpath, folder]
		var frames: Array = _collect_frames_in_dir(full_path)
		if frames.is_empty():
			continue
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, anim_name != "enemy_death")
		sf.set_animation_speed(anim_name, 12.0)
		for tex in frames:
			sf.add_frame(anim_name, tex)
		any_loaded = true

	if not any_loaded:
		return false
	_anim_sprite.sprite_frames = sf
	# Chibi sprites ship on a large (~900×900) canvas; scale down so the
	# figure reads at roughly the player/enemy silhouette size.
	_anim_sprite.scale = Vector2(0.15, 0.15)
	# All chibi canvases place the character's feet ~300 px below the canvas
	# center, which at scale 0.15 equals ~45 px below the node origin. The
	# collision shape is only half_h px tall, so without correction the sprite
	# visually sinks into platforms. Shift the sprite up so its feet align with
	# the collision box bottom.
	const SPRITE_FEET_PX: float = 45.0
	var col: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if col and col.shape is RectangleShape2D:
		var half_h: float = (col.shape as RectangleShape2D).size.y / 2.0
		_anim_sprite.position.y = half_h - SPRITE_FEET_PX
	return true

func _collect_frames_in_dir(path: String) -> Array:
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
				canonical = fname.substr(0, fname.length() - 7)   # strip ".import"
			elif fname.ends_with(".png.remap"):
				canonical = fname.substr(0, fname.length() - 6)   # strip ".remap"
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

func _make_placeholder_sprite(color: Color, sz: Vector2) -> void:
	if not _sprite:
		return
	var w := int(maxf(sz.x, 1.0))
	var h := int(maxf(sz.y, 1.0))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	_sprite.texture = ImageTexture.create_from_image(img)

# ── Player contact damage ─────────────────────────────────────────────────────
func _check_player_contact(delta: float) -> void:
	if not _player or state == State.STUNNED:
		return
	if _hit_cooldown > 0.0:
		_hit_cooldown -= delta
		return
	if contact_damage <= 0:
		return
	if global_position.distance_to(_player.global_position) > contact_range:
		return
	_hit_cooldown = HIT_COOLDOWN_TIME
	_attack_timer = 0.5
	if _player.has_method("receive_hit"):
		var dir: Vector2 = (_player.global_position - global_position).normalized()
		_player.receive_hit(contact_damage, dir * contact_knockback)

# ── Helpers ───────────────────────────────────────────────────────────────────
func _update_facing() -> void:
	if velocity.x > 10.0:
		_facing_right = true
	elif velocity.x < -10.0:
		_facing_right = false
	if _sprite:
		_sprite.flip_h = not _facing_right
	if _anim_sprite:
		_anim_sprite.flip_h = not _facing_right

func _show_question_mark() -> void:
	pass  # override or use AnimationPlayer

func _hide_question_mark() -> void:
	pass

func _play_sound(event: String) -> void:
	# Map BaseEnemy state events to the audio_config.json `enemies.*` keys.
	# Subclasses can still override for boss-specific cues.
	if not SoundManager:
		return
	var key: String = ""
	match event:
		"alert":     key = "alert"
		"chase":     key = "chase_start"
		"give_up":   key = "give_up"
		"step":      key = "patrol_step"
		"stun":      key = "alert"   # no dedicated stun sfx yet — alert reads as "ouch"
	if key != "":
		SoundManager.play_sfx("enemies", key)

func _tutorial_hint(hint_id: String) -> void:
	if not is_inside_tree():
		return
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("show_hint"):
		tm.show_hint(hint_id)

func _update_animation() -> void:
	var anim: String = _get_anim_name()

	# Prefer AnimatedSprite2D with loaded SpriteFrames (real sprites path).
	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(anim):
		if _anim_sprite.animation != anim:
			_anim_sprite.play(anim)
		return

	# Fall back to AnimationPlayer (placeholder / future hand-authored anims).
	if not _anim:
		return
	if not _anim.has_animation(anim):
		return
	if _anim.current_animation != anim:
		_anim.play(anim)

func _get_anim_name() -> String:
	if _attack_timer > 0.0:
		return "enemy_attack"
	match state:
		State.PATROL:  return "enemy_walk"
		State.ALERT:   return "enemy_idle"
		State.CHASE:   return "enemy_run"
		State.GIVE_UP: return "enemy_idle"
		State.RETURN:  return "enemy_walk"
		State.STUNNED: return "enemy_stun"
	return "enemy_idle"
