extends Area2D

# Collectible key fragment for boss_01 ("collect_and_escape" mechanic).
# Added to groups "collectible" and "fragment" so BossLevel picks it up
# via _register_arena_objects → BossAI.register_arena_objects.
#
# When player enters, emits `collected` and calls BossAI.on_collectible_picked
# (via the owning BossLevel forwarding on_collectible_picked to the boss).

signal collected

const GLOW_RADIUS: float = 14.0

@export var fragment_index: int = 0   # 0, 1, 2

var _picked: bool = false
var _base_y: float = 0.0
var _time:   float = 0.0

func _ready() -> void:
	add_to_group("collectible")
	add_to_group("fragment")
	_base_y = position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	# Gentle bobbing so the fragment feels alive.
	position.y = _base_y + sin(_time * 2.2) * 4.0
	queue_redraw()

func _draw() -> void:
	var glow: Color = Color("#FFD060")
	draw_circle(Vector2.ZERO, GLOW_RADIUS * (1.0 + 0.08 * sin(_time * 3.0)), glow)
	draw_circle(Vector2.ZERO, GLOW_RADIUS * 0.55, Color("#FFFFFF"))

func _on_body_entered(body: Node2D) -> void:
	if _picked:
		return
	if not body.is_in_group("player"):
		return
	_picked = true
	collected.emit()
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss and boss.has_method("on_collectible_picked"):
		boss.on_collectible_picked()
	_play_collect_fx()

func _play_collect_fx() -> void:
	monitoring = false
	var tw := create_tween()
	tw.parallel().tween_property(self, "scale",    Vector2(1.8, 1.8), 0.18)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
