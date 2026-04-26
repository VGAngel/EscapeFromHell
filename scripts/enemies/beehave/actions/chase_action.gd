@tool
extends ActionLeaf
class_name ChaseAction

## Moves the actor toward `player` stored in blackboard.
## Returns RUNNING while chasing, FAILURE when player ref is lost or when
## chase_duration elapses (counted from the first tick of this run).

@export var chase_duration: float = 6.0

var _chase_timer: float = 0.0


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_chase_timer = chase_duration


func tick(actor: Node, blackboard: Blackboard) -> int:
	var body   := actor as CharacterBody2D
	var player := blackboard.get_value(&"player") as Node2D
	if not body or not player:
		return FAILURE

	_chase_timer -= body.get_physics_process_delta_time()
	if _chase_timer <= 0.0:
		return FAILURE

	blackboard.set_value(&"last_known_pos", player.global_position)

	var chase_speed: float = 96.0  # default; allow override via actor stat
	var ms: Variant = body.get(&"move_speed")
	var mult: Variant = body.get(&"chase_speed_mult")
	if ms != null and mult != null:
		chase_speed = float(ms) * float(mult)

	var dir: float = signf(player.global_position.x - body.global_position.x)
	body.velocity.x = chase_speed * dir
	return RUNNING
