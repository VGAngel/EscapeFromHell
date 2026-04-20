extends "res://scripts/LevelBase.gd"

# EscapeLevel — extends LevelBase for escape-type levels.
#
# Key differences from a plain level:
#  • No countdown-death timer — the Pursuer provides the pressure.
#  • A Pursuer node is spawned below the player and activated after
#    PURSUER_START_DELAY seconds.
#  • On respawn the Pursuer resets to its start position (off-screen below)
#    and is re-activated after the same delay.
#  • Pursuer contact calls player.receive_hit(1, knockback_up) — one HP hit
#    plus an upward velocity impulse to push the player away.
#
# Expected scene structure (same as LevelBase):
#   EscapeLevel (Node2D) ← this script
#   ├── HUD
#   ├── RoomContainer
#   ├── SpawnPoint   ← placed at the BOTTOM of the vertical level
#   └── Exit         ← placed at the TOP of the vertical level

const PursuerClass := preload("res://scripts/enemies/Pursuer.gd")

## Seconds after level start before the pursuer begins moving.
const PURSUER_START_DELAY := 2.0

## Pixels below the spawn point where the pursuer appears (off-screen).
const PURSUER_SPAWN_OFFSET := 400.0

var _pursuer: Node = null   # Pursuer instance; typed Node for easier test injection

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super()
	_spawn_pursuer()

## Override: disable the simple countdown-death timer from LevelBase.
## The Pursuer is the pressure mechanic on escape levels.
func _setup_escape_timer() -> void:
	pass

# ── Pursuer lifecycle ─────────────────────────────────────────────────────────

func _spawn_pursuer() -> void:
	if not is_instance_valid(_player):
		return

	var mechanic: String = _get_mechanic_type()
	var cfg := _pursuer_config(mechanic)

	_pursuer = PursuerClass.new()
	_pursuer.mechanic_type = mechanic
	_pursuer.position      = Vector2(0.0, _pursuer_start_y())

	add_child(_pursuer)
	_pursuer.setup(_player as CharacterBody2D, cfg)
	_pursuer.player_caught.connect(_on_pursuer_caught)

	_schedule_pursuer_activate()

func _pursuer_start_y() -> float:
	return _spawn_point.global_position.y + PURSUER_SPAWN_OFFSET

func _schedule_pursuer_activate() -> void:
	get_tree().create_timer(PURSUER_START_DELAY).timeout.connect(
		func() -> void:
			if is_instance_valid(_pursuer):
				_pursuer.activate()
	)

# ── Mechanic config ───────────────────────────────────────────────────────────

func _get_mechanic_type() -> String:
	if not LevelConfig:
		return "chase_shadow"
	var mechanics: Array = LevelConfig.get_special_mechanics(level_id)
	return mechanics[0] if mechanics.size() > 0 else "chase_shadow"

func _pursuer_config(mechanic: String) -> Dictionary:
	match mechanic:
		"chase_shadow":
			return {
				"speed": 75.0, "behavior": "rising",
				"knockback_force": 350.0
			}
		"chase_swamp_wave":
			return {
				"speed": 80.0, "behavior": "rising",
				"knockback_force": 380.0,
				"oscillation_amplitude": 40.0, "oscillation_frequency": 0.5
			}
		"rising_lava_fast":
			return {
				"speed": 115.0, "behavior": "rising",
				"knockback_force": 500.0
			}
		"chase_hell_knight":
			return {
				"speed": 90.0, "behavior": "chasing",
				"knockback_force": 420.0
			}
		"chase_cracking_floor":
			return {
				"speed": 70.0, "behavior": "rising",
				"knockback_force": 350.0,
				"contact_range": 32.0
			}
		"chase_fallen_angel":
			return {
				"speed": 95.0, "behavior": "chasing",
				"knockback_force": 450.0
			}
		"chase_forest":
			return {
				"speed": 72.0, "behavior": "rising",
				"knockback_force": 350.0,
				"oscillation_amplitude": 20.0, "oscillation_frequency": 0.3
			}
		"chase_machine":
			return {
				"speed": 100.0, "behavior": "rising",
				"knockback_force": 460.0
			}
		"chase_void":
			return {
				"speed": 85.0, "behavior": "chasing",
				"knockback_force": 400.0,
				"oscillation_amplitude": 80.0, "oscillation_frequency": 0.8
			}
		"chase_all_elements":
			return {
				"speed": 120.0, "behavior": "rising",
				"knockback_force": 500.0
			}
		"chase_lucifer_hand":
			return {
				"speed": 130.0, "behavior": "chasing",
				"knockback_force": 550.0
			}
		_:
			return {"speed": 80.0, "behavior": "rising", "knockback_force": 380.0}

# ── Events ────────────────────────────────────────────────────────────────────

func _on_pursuer_caught(knockback: Vector2) -> void:
	if not is_instance_valid(_player):
		return
	if _player.has_method("receive_hit"):
		_player.receive_hit(1, knockback)

## Override respawn: reset the Pursuer in addition to LevelBase player respawn.
func _on_respawn() -> void:
	super()
	if is_instance_valid(_pursuer):
		# Update _start_y first so reset_to_start() returns to the correct
		# off-screen position (recalculated from spawn point each respawn).
		_pursuer._start_y = _pursuer_start_y()
		_pursuer.reset_to_start()
		_schedule_pursuer_activate()
