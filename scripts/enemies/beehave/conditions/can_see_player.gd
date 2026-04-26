@tool
extends ConditionLeaf
class_name CanSeePlayerCondition

## SUCCESS when actor sees a player within `detection_range`.
## Reads `detection_range` from the actor (CharacterBody2D) if exposed.

@export var detection_range_override: float = -1.0


func tick(actor: Node, _blackboard: Blackboard) -> int:
	var player := actor.get_tree().get_first_node_in_group(&"player") as Node2D
	if not player:
		return FAILURE

	var range: float = detection_range_override
	if range <= 0.0:
		range = float(actor.get(&"detection_range") if actor.get(&"detection_range") != null else 200.0)

	if (actor as Node2D).global_position.distance_to(player.global_position) <= range:
		_blackboard.set_value(&"player", player)
		_blackboard.set_value(&"last_known_pos", player.global_position)
		return SUCCESS
	return FAILURE
