extends CharacterBody2D

const SPEED = 320.0 # Slightly faster walking for better feel
const JUMP_VELOCITY = -800.0
const GRAVITY_SCALE = 1.0
const TERMINAL_VELOCITY = 1000.0

# Game Feel Constants
const COYOTE_TIME = 0.15
const JUMP_BUFFER_TIME = 0.15

# Squash and Stretch Constants
const SQUASH_SPEED = 12.0 # Slightly slower for smoother transitions
const SCALE_IDLE = Vector2(0.2, 0.2)
const SCALE_JUMP = Vector2(0.18, 0.22) # Less extreme stretch
const SCALE_FALL = Vector2(0.19, 0.21) # Subtler fall stretch
const SCALE_LAND = Vector2(0.22, 0.18) # Subtler land squash

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")

# Timers
var coyote_timer = 0.0
var jump_buffer_timer = 0.0
var target_scale = SCALE_IDLE

@onready var animated_sprite = $AnimatedSprite2D

func _ready():
	floor_snap_length = 8.0
	floor_constant_speed = true

func _physics_process(delta):
	apply_gravity(delta)
	handle_jump(delta)
	handle_movement(delta)
	
	update_timers(delta)
	move_and_slide()
	
	update_target_scale()
	update_animations()

func _process(delta):
	# Using 1.0 - exp(-speed * delta) for smooth frame-rate independent transition
	var lerp_factor = 1.0 - exp(-SQUASH_SPEED * delta)
	animated_sprite.scale = animated_sprite.scale.lerp(target_scale, lerp_factor)

func apply_gravity(delta):
	if not is_on_floor():
		velocity.y += gravity * GRAVITY_SCALE * delta
		velocity.y = min(velocity.y, TERMINAL_VELOCITY)
		coyote_timer -= delta
	else:
		if coyote_timer < 0: # Just landed
			# Only trigger squash if we were falling fast
			if abs(velocity.y) < 10:
				animated_sprite.scale = SCALE_LAND
		coyote_timer = COYOTE_TIME

func handle_jump(delta):
	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER_TIME
	
	if jump_buffer_timer > 0 and coyote_timer > 0:
		velocity.y = JUMP_VELOCITY
		jump_buffer_timer = 0
		coyote_timer = 0
		animated_sprite.scale = SCALE_JUMP # Visual stretch
	
	if Input.is_action_just_released("ui_accept") and velocity.y < 0:
		velocity.y *= 0.5
	
	jump_buffer_timer -= delta

func handle_movement(_delta):
	var direction = Input.get_axis("ui_left", "ui_right")
	if direction:
		# Balanced acceleration
		velocity.x = move_toward(velocity.x, direction * SPEED, SPEED * 0.12)
		animated_sprite.flip_h = direction < 0
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED * 0.08)

func update_timers(delta):
	jump_buffer_timer = max(0, jump_buffer_timer)
	coyote_timer = max(0, coyote_timer)

func update_target_scale():
	if not is_on_floor():
		if velocity.y < 0:
			target_scale = SCALE_JUMP
		else:
			target_scale = SCALE_FALL
	else:
		target_scale = SCALE_IDLE

func update_animations():
	var anim = "idle"
	if not is_on_floor():
		anim = "jump" if velocity.y < 0 else "fall"
	else:
		anim = "run" if abs(velocity.x) > 10 else "idle"
	
	if animated_sprite.animation != anim:
		animated_sprite.play(anim)
