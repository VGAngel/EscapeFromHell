class_name Pursuer
extends Node2D

# Pursuer — a rising or chasing hazard used on escape-type levels.
#
# Design:
#   RISING   — a horizontal wave (lava, shadow, swamp) that climbs upward at
#              constant speed. Optional horizontal oscillation for variety.
#   CHASING  — an entity (knight, angel) that moves directly toward the player.
#
# Attach as a child of EscapeLevel (or any Node2D).
# Call setup(player, cfg) after adding to the tree, then activate() to start.
#
# Signal player_caught fires at most once per CONTACT_COOLDOWN_TIME seconds
# so the player has time to react between hits.

## Fires when the pursuer reaches the player. The Vector2 is the knockback
## impulse to apply — already scaled by knockback_force, pointing upward.
signal player_caught(knockback: Vector2)

enum Behavior { RISING, CHASING }

# ── Config (written by setup()) ───────────────────────────────────────────────
var speed:                 float    = 80.0    # px / sec
var knockback_force:       float    = 400.0   # px / sec added to player velocity
var behavior:              Behavior = Behavior.RISING
var mechanic_type:         String   = "chase_shadow"
var oscillation_amplitude: float    = 0.0     # px, horizontal sway (RISING only)
var oscillation_frequency: float    = 1.0     # Hz
var contact_range:         float    = 64.0    # px — distance that triggers signal

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player:           CharacterBody2D = null
var _start_y:          float           = 0.0
var _active:           bool            = false
var _time:             float           = 0.0
var _contact_cooldown: float           = 0.0

const CONTACT_COOLDOWN_TIME := 1.5   # sec between successive hits

# ── Public API ────────────────────────────────────────────────────────────────

## Configure the pursuer before it starts moving.
## cfg keys (all optional):
##   speed, knockback_force, contact_range,
##   oscillation_amplitude, oscillation_frequency,
##   behavior ("rising" | "chasing")
func setup(player: CharacterBody2D, cfg: Dictionary) -> void:
	_player            = player
	_start_y           = position.y
	speed                 = cfg.get("speed",                 speed)
	knockback_force       = cfg.get("knockback_force",       knockback_force)
	contact_range         = cfg.get("contact_range",         contact_range)
	oscillation_amplitude = cfg.get("oscillation_amplitude", 0.0)
	oscillation_frequency = cfg.get("oscillation_frequency", 1.0)
	var beh: String = cfg.get("behavior", "rising")
	behavior = Behavior.CHASING if beh == "chasing" else Behavior.RISING

## Start moving. Called after the initial delay (PURSUER_START_DELAY).
func activate() -> void:
	_active = true

## Return pursuer to its original position and reset all timers.
## EscapeLevel calls this on player respawn.
func reset_to_start() -> void:
	position.y        = _start_y
	_time             = 0.0
	_contact_cooldown = 0.0
	_active           = false

# ── Process ───────────────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if not _active:
		return
	_time             += delta
	_contact_cooldown  = maxf(_contact_cooldown - delta, 0.0)
	_move(delta)
	_check_player_overlap()

func _move(delta: float) -> void:
	match behavior:
		Behavior.RISING:
			position.y -= speed * delta
			if oscillation_amplitude > 0.0:
				position.x = sin(_time * oscillation_frequency * TAU) * oscillation_amplitude

		Behavior.CHASING:
			if not is_instance_valid(_player):
				return
			# Move toward player at full speed; never overtake (approach from below).
			var target := _player.position
			position = position.move_toward(target, speed * delta)
			if oscillation_amplitude > 0.0:
				position.x += sin(_time * oscillation_frequency * TAU) \
							  * oscillation_amplitude * delta

## Exposed so unit tests can call it without relying on _physics_process.
func _check_player_overlap() -> void:
	if _contact_cooldown > 0.0:
		return
	if not is_instance_valid(_player):
		return
	if position.distance_to(_player.position) <= contact_range:
		_contact_cooldown = CONTACT_COOLDOWN_TIME
		player_caught.emit(Vector2(0.0, -knockback_force))
