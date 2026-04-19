extends Area2D

var _base_y: float
var _time: float = 0.0

func _ready() -> void:
	_base_y = global_position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.5) * 10.0

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		GameManager.collect_soul(get_meta("soul_id", 0))
		queue_free()
