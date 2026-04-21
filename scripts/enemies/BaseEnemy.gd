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

const GRAVITY: float = 900.0

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _anim:           AnimationPlayer = $AnimationPlayer
@onready var _sprite:         Sprite2D        = $Sprite2D
@onready var _alert_icon:     Node2D          = $AlertIcon
@onready var _breath_player:  AudioStreamPlayer2D = $BreathPlayer

func _ready() -> void:
	_patrol_origin = global_position
	_alert_icon.visible = false
	add_to_group("enemy")
	_find_player()

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
func _do_patrol(delta: float) -> void:
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
	_alert_icon.visible = true
	_last_known_pos = _player.global_position
	enemy_alerted.emit(self)
	_play_sound("alert")

func _do_alert(_delta: float) -> void:
	if _alert_timer <= 0.0:
		_alert_icon.visible = false
		_enter_chase()

# ── CHASE ─────────────────────────────────────────────────────────────────────
func _enter_chase() -> void:
	state = State.CHASE
	_chase_timer = chase_duration

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
	_sprite.flip_h = not _facing_right

func _show_question_mark() -> void:
	pass  # override or use AnimationPlayer

func _hide_question_mark() -> void:
	pass

func _play_sound(event: String) -> void:
	pass  # override in subclass

func _update_animation() -> void:
	if not _anim:
		return
	var anim: String = _get_anim_name()
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
