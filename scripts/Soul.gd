extends Area2D

var _base_y:   float      = 0.0
var _time:     float      = 0.0
var _soul_id:  int        = 0
var _soul_data: Dictionary = {}

func _ready() -> void:
	add_to_group("soul")
	_base_y = global_position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.5) * 10.0

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameManager.collect_soul(_soul_id)
		queue_free()

## Called by LevelBase._mark_primary_soul() to tag this node as a named soul.
func set_soul_data(soul_id: int, data: Dictionary) -> void:
	_soul_id   = soul_id
	_soul_data = data
	set_meta("soul_id", soul_id)
