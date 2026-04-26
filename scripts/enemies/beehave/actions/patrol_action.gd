@tool
extends ActionLeaf
class_name PatrolAction

## Walks the actor back and forth around a patrol origin (set on first tick).
## Reverses on walls, edges (using existing left/right edge raycasts), and at
## the patrol distance limit. Always returns RUNNING — terminate it via a
## sibling condition higher up the tree (e.g. CanSeePlayerCondition).

@export var patrol_distance_override: float = -1.0
@export var move_speed_override:      float = -1.0

var _patrol_origin: Vector2 = Vector2.ZERO
var _patrol_dir:    float   = 1.0
var _origin_set:    bool    = false


func before_run(actor: Node, _blackboard: Blackboard) -> void:
	if not _origin_set:
		_patrol_origin = (actor as Node2D).global_position
		_origin_set = true


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var body := actor as CharacterBody2D
	if not body:
		return FAILURE

	var patrol_distance: float = patrol_distance_override
	if patrol_distance <= 0.0:
		patrol_distance = float(body.get(&"patrol_distance") if body.get(&"patrol_distance") != null else 120.0)

	var move_speed: float = move_speed_override
	if move_speed <= 0.0:
		move_speed = float(body.get(&"move_speed") if body.get(&"move_speed") != null else 80.0)

	var should_reverse := false
	if absf(body.global_position.x - _patrol_origin.x) >= patrol_distance:
		should_reverse = true
	if body.is_on_wall():
		should_reverse = true

	# Edge detection — reuses BaseEnemy's _ray_left / _ray_right if present.
	if body.is_on_floor() and not should_reverse:
		var leading: Variant = body.get(&"_ray_right") if _patrol_dir > 0.0 else body.get(&"_ray_left")
		if leading is RayCast2D and not (leading as RayCast2D).is_colliding():
			should_reverse = true

	if should_reverse:
		_patrol_dir *= -1.0

	body.velocity.x = move_speed * _patrol_dir
	return RUNNING
