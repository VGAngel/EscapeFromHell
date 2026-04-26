@tool
extends ActionLeaf
class_name GiveUpAction

## Walks toward `last_known_pos` for `give_up_duration` seconds, then succeeds.

@export var give_up_duration: float = 2.5

var _timer: float = 0.0


func before_run(_actor: Node, _blackboard: Blackboard) -> void:
	_timer = give_up_duration


func tick(actor: Node, blackboard: Blackboard) -> int:
	var body := actor as CharacterBody2D
	if not body:
		return FAILURE

	_timer -= body.get_physics_process_delta_time()

	var last_known: Variant = blackboard.get_value(&"last_known_pos")
	if last_known == null:
		return SUCCESS

	var lkp := last_known as Vector2
	var dir: float = signf(lkp.x - body.global_position.x)
	var speed: float = float(body.get(&"move_speed") if body.get(&"move_speed") != null else 80.0)
	body.velocity.x = speed * 0.6 * dir

	if _timer <= 0.0 or absf(body.global_position.x - lkp.x) < 16.0:
		return SUCCESS
	return RUNNING
