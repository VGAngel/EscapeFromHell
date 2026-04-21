extends Area2D

# Wind totem for boss_02 "activate_in_sequence" mechanic.
# Player must stand on it for activation_hold seconds, BUT only when the
# boss is not blocking it (boss.is_blocking_totem returns false).
#
# Added to groups "collectible" and "totem" so BossLevel picks it up
# via _register_arena_objects → BossAI.register_arena_objects.

signal activated(index: int)

@export var totem_index:     int   = 0      # order in the required sequence
@export var activation_hold: float = 1.5

var _activated:    bool  = false
var _hold_timer:   float = 0.0
var _base_y:       float = 0.0
var _time:         float = 0.0
var _player_in:    bool  = false

func _ready() -> void:
	add_to_group("collectible")
	add_to_group("totem")
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 1.8) * 3.0
	queue_redraw()

	if _activated or not _player_in:
		_hold_timer = 0.0
		return
	# Don't progress while the boss is blocking this totem.
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss and boss.has_method("is_blocking_totem"):
		if boss.is_blocking_totem(global_position):
			_hold_timer = 0.0
			return
	_hold_timer += delta
	if _hold_timer >= activation_hold:
		_activate()

func _activate() -> void:
	_activated = true
	monitoring = false
	activated.emit(totem_index)
	var boss: Node = get_tree().get_first_node_in_group("boss")
	if boss and boss.has_method("on_totem_activated"):
		boss.on_totem_activated(totem_index)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in = false

func _draw() -> void:
	var base: Color = Color("#AACCFF") if not _activated else Color("#FFFFFF")
	draw_circle(Vector2.ZERO, 16.0, base)
	var ring: Color = Color("#55AAFF")
	# Progress arc
	var ratio: float = clampf(_hold_timer / activation_hold, 0.0, 1.0) if not _activated else 1.0
	var segments: int = 24
	var prev := Vector2.UP * 20.0
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		if t > ratio:
			break
		var next: Vector2 = Vector2.UP.rotated(TAU * t) * 20.0
		draw_line(prev, next, ring, 3.0)
		prev = next
