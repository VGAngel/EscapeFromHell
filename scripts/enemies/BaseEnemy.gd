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
@export var contact_range:     float = 28.0
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
var _give_up_timer:  float = 2.5
var _last_known_pos: Vector2 = Vector2.ZERO
var _patrol_origin:  Vector2 = Vector2.ZERO
var _patrol_dir:     float   = 1.0
var _facing_right:   bool    = true
var _hit_cooldown:   float   = 0.0
var _config_applied: bool    = false

const GRAVITY: float = 900.0

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _anim:           AnimationPlayer     = get_node_or_null("AnimationPlayer")
@onready var _sprite:         Sprite2D            = get_node_or_null("Sprite2D")
@onready var _anim_sprite:    AnimatedSprite2D    = get_node_or_null("AnimatedSprite2D")
@onready var _alert_icon:     Node2D              = get_node_or_null("AlertIcon")
@onready var _breath_player:  AudioStreamPlayer2D = get_node_or_null("BreathPlayer")

func _ready() -> void:
	_patrol_origin = global_position
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

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
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
			state = State.RETURN
	if _chase_timer > 0.0:
		_chase_timer -= delta
	if _alert_timer > 0.0:
		_alert_timer -= delta
	if _give_up_timer > 0.0 and state == State.GIVE_UP:
		_give_up_timer -= delta

# ── PATROL ────────────────────────────────────────────────────────────────────
func _do_patrol(_delta: float) -> void:
	velocity.x = move_speed * _patrol_dir

	var dist_from_origin: float = global_position.x - _patrol_origin.x
	if absf(dist_from_origin) >= patrol_distance:
		_patrol_dir *= -1.0

	if is_on_wall():
		_patrol_dir *= -1.0

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
		_alert_icon.visible = false
		_enter_chase()

# ── CHASE ─────────────────────────────────────────────────────────────────────
func _enter_chase() -> void:
	state = State.CHASE
	_chase_timer = chase_duration
	_tutorial_hint("enemy_chasing")

func _do_chase(delta: float) -> void:
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

	if is_on_wall():
		velocity.x = 0.0

# ── GIVE UP ───────────────────────────────────────────────────────────────────
func _enter_give_up() -> void:
	state = State.GIVE_UP
	_give_up_timer = 2.5
	velocity.x = 0.0
	_show_question_mark()
	enemy_lost_target.emit(self)
	_play_sound("give_up")

func _do_give_up(delta: float) -> void:
	var dir: float = sign(_last_known_pos.x - global_position.x)
	velocity.x = move_speed * 0.6 * dir

	var reached: bool = absf(global_position.x - _last_known_pos.x) < 16.0
	if reached or _give_up_timer <= 0.0:
		_hide_question_mark()
		state = State.RETURN

# ── RETURN ────────────────────────────────────────────────────────────────────
func _do_return(delta: float) -> void:
	var dir: float = sign(_patrol_origin.x - global_position.x)
	velocity.x = move_speed * 0.7 * dir

	if absf(global_position.x - _patrol_origin.x) < 12.0:
		global_position.x = _patrol_origin.x
		velocity.x = 0.0
		state = State.PATROL

# ── STUNNED ───────────────────────────────────────────────────────────────────
func _do_stunned() -> void:
	velocity.x = move_toward(velocity.x, 0.0, 600.0 * get_physics_process_delta_time())

func receive_knockback(direction: Vector2, stun_duration: float) -> void:
	state = State.STUNNED
	_stun_timer = stun_duration
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
	return true

func _collect_frames_in_dir(path: String) -> Array:
	var frames: Array = []
	var dir := DirAccess.open(path)
	if not dir:
		return frames
	var files: Array = []
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".png") and not fname.begins_with("."):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
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
	if _hit_cooldown > 0.0:
		_hit_cooldown -= delta
		return
	if not _player or state == State.STUNNED:
		return
	if contact_damage <= 0:
		return
	if global_position.distance_to(_player.global_position) > contact_range:
		return
	_hit_cooldown = HIT_COOLDOWN_TIME
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
	pass  # override in subclass

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
	match state:
		State.PATROL:  return "enemy_walk"
		State.ALERT:   return "enemy_idle"
		State.CHASE:   return "enemy_run"
		State.GIVE_UP: return "enemy_idle"
		State.RETURN:  return "enemy_walk"
		State.STUNNED: return "enemy_stun"
	return "enemy_idle"
