extends Node2D

# Base script for all procedural and static non-boss levels.
# Attach to the root Node2D of Level.tscn.
#
# Expected scene structure:
#   Level (Node2D) ← this script
#   ├── HUD          (CanvasLayer, script: scripts/HUD.gd)
#   ├── RoomContainer (Node2D)   ← rooms are added here at runtime
#   ├── SpawnPoint   (Marker2D)  ← default player spawn
#   ├── Exit         (Area2D)    ← player walks into this to complete level
#   └── Camera2D / PhantomCamera2D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var level_id:     int  = 1
@export var force_static: bool = false  # skip generator, use existing scene children

# ── Child node references ─────────────────────────────────────────────────────
@onready var _hud:            Node      = $HUD
@onready var _room_container: Node2D    = $RoomContainer
@onready var _spawn_point:    Marker2D  = $SpawnPoint
@onready var _exit_area:      Area2D    = $Exit

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player:             CharacterBody2D = null
var _souls_in_level:     Array           = []   # Array[Node] — soul pickups
var _souls_required:     int             = 0
var _souls_found:        int             = 0
var _is_complete:        bool            = false
var _escape_timer_total: float           = 0.0
var _level_type:         String          = "platformer"

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_level_type = LevelConfig.get_level_type(level_id) if LevelConfig else "platformer"

	if force_static or (LevelGenerator and LevelGenerator.is_static(level_id)):
		_init_static_level()
	else:
		_init_procedural_level()

	_spawn_player()
	_connect_exit()
	_connect_souls()
	_setup_escape_timer()

	GameManager.register_hud(_hud)
	GameManager.begin_level(level_id, _souls_required)

	if LevelConfig and LevelConfig.has_mechanic(level_id, "tutorial_trigger"):
		_fire_tutorial_hints()

# ── Static vs procedural ──────────────────────────────────────────────────────

func _init_static_level() -> void:
	# Rooms are already children of RoomContainer in the saved .tscn.
	# Just count souls that exist in the tree.
	_discover_souls()

func _init_procedural_level() -> void:
	var gen: Object = LevelGenerator.generate(level_id)

	var cursor_x: float = 0.0
	for scene_path: String in gen.room_scenes:
		if not ResourceLoader.exists(scene_path):
			push_warning("Level: room scene not found: %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		if not packed:
			continue
		var room: Node2D = packed.instantiate()
		room.position.x = cursor_x
		_room_container.add_child(room)
		cursor_x += _room_width(room)

	_discover_souls()

	# Override spawn/exit to match the assembled layout
	_reposition_spawn_and_exit(cursor_x)

	# Place the named soul if present
	if gen.soul_id > 0:
		_mark_primary_soul(gen.soul_id, gen.soul_data)

func _room_width(room: Node2D) -> float:
	# Rooms should export a "room_width" metadata or have a set size.
	if room.has_meta("room_width"):
		return float(room.get_meta("room_width"))
	return 720.0  # default viewport width

func _reposition_spawn_and_exit(total_width: float) -> void:
	# Move spawn to the beginning of the first room if not manually placed.
	if _spawn_point.position == Vector2.ZERO:
		_spawn_point.position = Vector2(80, -64)
	# Move exit to the far-right of the last room.
	_exit_area.position = Vector2(total_width - 80, _spawn_point.position.y)

# ── Soul discovery ────────────────────────────────────────────────────────────

func _discover_souls() -> void:
	_souls_in_level.clear()
	for soul in get_tree().get_nodes_in_group("soul"):
		_souls_in_level.append(soul)
	_souls_required = _souls_in_level.size()

func _mark_primary_soul(soul_id: int, soul_data: Dictionary) -> void:
	# Tag the first untagged soul node with the named-soul data.
	for soul in _souls_in_level:
		if soul.has_method("set_soul_data") and not soul.get_meta("soul_id", 0):
			soul.set_soul_data(soul_id, soul_data)
			soul.set_meta("soul_id", soul_id)
			break

# ── Player ────────────────────────────────────────────────────────────────────

func _spawn_player() -> void:
	var player_scene := load("res://scenes/Player.tscn") as PackedScene
	if not player_scene:
		push_error("Level: res://scenes/Player.tscn not found")
		return
	_player = player_scene.instantiate() as CharacterBody2D
	_player.global_position = _spawn_point.global_position
	add_child(_player)

	_player.player_died.connect(_on_player_died)
	_player.soul_delivered.connect(_on_soul_delivered)
	_player.hp_changed.connect(_on_player_hp_changed)

# ── Exit ──────────────────────────────────────────────────────────────────────

func _connect_exit() -> void:
	if _exit_area.body_entered.connect(_on_exit_body_entered) != OK:
		push_warning("Level: failed to connect Exit.body_entered")

func _on_exit_body_entered(body: Node2D) -> void:
	if body != _player or _is_complete:
		return
	if _souls_found < _souls_required:
		# Nudge player back — not all souls collected yet
		if TutorialManager:
			TutorialManager.show_hint("collect_souls_first")
		return
	_complete_level()

# ── Souls ─────────────────────────────────────────────────────────────────────

func _connect_souls() -> void:
	for soul in _souls_in_level:
		if soul.has_signal("soul_collected"):
			soul.soul_collected.connect(_on_soul_collected.bind(soul))

func _on_soul_collected(soul: Node) -> void:
	var soul_id: int = soul.get_meta("soul_id", 0)
	_souls_found += 1
	GameManager.collect_soul(soul_id)

	# Boss mechanic hook — forward to boss if present
	var boss: Node = _get_boss()
	if boss and boss.has_method("on_collectible_picked"):
		boss.on_collectible_picked()

func _on_soul_delivered(_soul_id: String) -> void:
	# Souls are counted on pickup in this design; delivery is visual only.
	pass

# ── Player events ─────────────────────────────────────────────────────────────

func _on_player_died() -> void:
	if _is_complete:
		return
	var cause: String = "enemy_hit"  # Player.gd can emit cause if extended
	GameManager.trigger_death(cause)

func _on_player_hp_changed(hp: int, max_hp: int) -> void:
	GameManager.set_hp(hp, max_hp) if GameManager.has_method("set_hp") else null

# ── Level complete ────────────────────────────────────────────────────────────

func _complete_level() -> void:
	if _is_complete:
		return
	_is_complete = true
	GameManager.complete_level()

# ── Escape timer ──────────────────────────────────────────────────────────────

func _setup_escape_timer() -> void:
	if _level_type != "escape":
		return
	_escape_timer_total = LevelConfig.get_level(level_id).get("escape_time", 60.0) if LevelConfig else 60.0
	GameManager.start_escape_timer(_escape_timer_total)
	get_tree().create_timer(_escape_timer_total).timeout.connect(_on_escape_timer_expired)

func _on_escape_timer_expired() -> void:
	if _is_complete:
		return
	GameManager.instant_death("fall")

# ── Respawn ───────────────────────────────────────────────────────────────────

func _on_respawn() -> void:
	if not _player:
		return
	_player.respawn(_spawn_point.global_position)
	if _level_type == "escape":
		# Restart escape timer
		_setup_escape_timer()

func _ready_late() -> void:
	# Connect GameManager respawn signal after all nodes are ready.
	if GameManager.player_respawned.connect(_on_respawn) != OK:
		push_warning("Level: failed to connect player_respawned")

# ── Tutorial ──────────────────────────────────────────────────────────────────

func _fire_tutorial_hints() -> void:
	if not TutorialManager:
		return
	var mechanics: Array = LevelConfig.get_special_mechanics(level_id) if LevelConfig else []
	for mechanic in mechanics:
		match mechanic:
			"first_soul":       TutorialManager.show_hint("first_soul")
			"first_staff":      TutorialManager.show_hint("first_staff")
			"first_checkpoint": TutorialManager.show_hint("checkpoint")

# ── Boss hook (BossLevel inherits from Level and overrides) ───────────────────

func _get_boss() -> Node:
	return get_tree().get_first_node_in_group("boss")

# ── Pause ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()

func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	# PauseScreen visibility is handled by the PauseScreen node itself
	# via its own _unhandled_input or by connecting to the HUD signal.
