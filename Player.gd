extends CharacterBody2D

@export var player_id: int = 1

const SPEED         = 320.0
const JUMP_VELOCITY = -800.0
const GRAVITY_SCALE = 1.0
const TERMINAL_VEL  = 1000.0
const COYOTE_TIME   = 0.15
const JUMP_BUFFER   = 0.15

const ANIM_BASE = "res://Assets/rpg-platformer-game-assets/1_Main_character/Dark_Elves/PNG/PNG Sequences/"

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var coyote_timer:   float = 0.0
var jump_buf_timer: float = 0.0

var lives: int = 3
var is_dead: bool = false
var _spawn_pos: Vector2

signal life_lost(remaining: int)
signal all_lives_lost

var _left:  String
var _right: String
var _jump:  String

@onready var _sprite: AnimatedSprite2D = $Sprite

func _ready() -> void:
	add_to_group("player")
	_spawn_pos = global_position
	_left  = "p%d_left"  % player_id
	_right = "p%d_right" % player_id
	_jump  = "p%d_jump"  % player_id
	_setup_animations()

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", ANIM_BASE + "Idle/0_Dark_Elves_Idle_%03d.png",                     18, 10.0, true)
	_add_anim(frames, "run",  ANIM_BASE + "Running/0_Dark_Elves_Running_%03d.png",               12, 12.0, true)
	_add_anim(frames, "jump", ANIM_BASE + "Jump Start/0_Dark_Elves_Jump Start_%03d.png",          6, 10.0, false)
	_add_anim(frames, "fall", ANIM_BASE + "Falling Down/0_Dark_Elves_Falling Down_%03d.png",      6,  8.0, true)
	_sprite.sprite_frames = frames
	_sprite.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_tpl: String, count: int, fps: float, loop: bool) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i in range(count):
		var path := path_tpl % i
		var tex := load(path) as Texture2D
		if tex == null:
			push_error("Player: cannot load texture: " + path)
			continue
		frames.add_frame(anim_name, tex)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	_apply_gravity(delta)
	_handle_jump(delta)
	_handle_movement()
	move_and_slide()
	_update_animation()

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * GRAVITY_SCALE * delta
		velocity.y  = minf(velocity.y, TERMINAL_VEL)
		coyote_timer -= delta
	else:
		coyote_timer = COYOTE_TIME

func _handle_jump(delta: float) -> void:
	if Input.is_action_just_pressed(_jump):
		jump_buf_timer = JUMP_BUFFER
	if jump_buf_timer > 0 and coyote_timer > 0:
		velocity.y     = JUMP_VELOCITY
		jump_buf_timer = 0.0
		coyote_timer   = 0.0
	if Input.is_action_just_released(_jump) and velocity.y < 0:
		velocity.y *= 0.5
	jump_buf_timer = maxf(0.0, jump_buf_timer - delta)

func _handle_movement() -> void:
	var dir := Input.get_axis(_left, _right)
	if dir:
		velocity.x = move_toward(velocity.x, dir * SPEED, SPEED * 0.15)
		_sprite.flip_h = dir < 0
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 0.1)

func _update_animation() -> void:
	var anim: String
	if not is_on_floor():
		anim = "jump" if velocity.y < 0 else "fall"
	elif absf(velocity.x) > 10:
		anim = "run"
	else:
		anim = "idle"
	if _sprite.animation != anim:
		_sprite.play(anim)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector2.ZERO
	lives -= 1
	if lives <= 0:
		all_lives_lost.emit()
	else:
		life_lost.emit(lives)
		_sprite.modulate = Color(1.0, 0.2, 0.2, 0.5)
		await get_tree().create_timer(0.8).timeout
		global_position = _spawn_pos
		velocity = Vector2.ZERO
		_sprite.modulate = Color.WHITE
		is_dead = false
