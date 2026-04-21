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
@onready var _hud:             Node       = $HUD
@onready var _pause_screen:    Node       = $PauseScreen
@onready var _room_container:  Node2D     = $RoomContainer
@onready var _spawn_point:     Marker2D   = $SpawnPoint
@onready var _exit_area:       Area2D     = $Exit
@onready var _level_complete:  Node       = get_node_or_null("LevelComplete")
@onready var _soul_reveal:     Node       = get_node_or_null("SoulRevealPanel")

# ── Runtime ───────────────────────────────────────────────────────────────────
var _player:             CharacterBody2D = null
var _souls_in_level:     Array           = []   # Array[Node] — soul pickups
var _souls_required:     int             = 0
var _souls_found:        int             = 0
var _is_complete:        bool            = false
var _escape_timer_total: float           = 0.0
var _level_type:         String          = "platformer"
var _respawn_position:   Vector2         = Vector2.ZERO  # updated by mid-altar

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# When Level.tscn is loaded procedurally, the export stays at default 1.
	# Read the real ID from GameManager which was set before the scene change.
	if level_id == 1 and GameManager and GameManager.current_level_id > 1:
		level_id = GameManager.current_level_id

	_level_type = LevelConfig.get_level_type(level_id) if LevelConfig else "platformer"

	if force_static or (LevelGenerator and LevelGenerator.is_static(level_id)):
		_init_static_level()
	else:
		_init_procedural_level()

	_spawn_player()
	_connect_exit()
	_connect_souls()
	_connect_altars()
	_setup_escape_timer()

	GameManager.register_hud(_hud)
	GameManager.begin_level(level_id, _souls_required)
	_hud.pause_requested.connect(_pause_screen.toggle)
	_connect_level_complete()

	if LevelConfig and LevelConfig.has_mechanic(level_id, "tutorial_trigger"):
		_fire_tutorial_hints()

	_report_level_diagnostics()

	await get_tree().process_frame
	_ready_late()

# ── Diagnostics ───────────────────────────────────────────────────────────────
## Emit a single on-screen info card summarising the level state, and warn
## loudly when something obvious is broken (no rooms, no souls required,
## player spawn outside every room). The user sees this instantly instead
## of having to decode a silent black screen.
func _report_level_diagnostics() -> void:
	var room_count: int = _room_container.get_child_count()
	var spawn_pos: Vector2 = _spawn_point.global_position if _spawn_point else Vector2.ZERO
	var msg: String = "Level %d (%s): rooms=%d, souls=%d, spawn=(%d,%d)" % [
		level_id, _level_type, room_count, _souls_required,
		int(spawn_pos.x), int(spawn_pos.y)]

	if room_count == 0:
		_report_error(msg + " — RoomContainer EMPTY. Static level без hand-made " +
			"сцен і без fallback? Гравець буде падати у порожнечу.")
	elif not _spawn_inside_any_room(spawn_pos):
		_report_warn(msg + " — spawn point is outside every room bounds. Check " +
			"_reposition_spawn_and_exit_* math for this level type.")
	else:
		_report_info(msg)

func _spawn_inside_any_room(pos: Vector2) -> bool:
	for child in _room_container.get_children():
		if not child is Node2D:
			continue
		var room_node: Node2D = child
		var w: float = float(room_node.get_meta("room_width", 720.0))
		var h: float = float(room_node.get_meta("room_height", 540.0))
		var top_left:     Vector2 = room_node.global_position
		var bottom_right: Vector2 = top_left + Vector2(w, h)
		if pos.x >= top_left.x and pos.x <= bottom_right.x \
				and pos.y >= top_left.y and pos.y <= bottom_right.y:
			return true
	return false

func _report_info(msg: String) -> void:
	if is_inside_tree():
		var d: Node = get_node_or_null("/root/DebugOverlay")
		if d and d.has_method("info"):
			d.info(msg)
			return
	print(msg)

# ── Static vs procedural ──────────────────────────────────────────────────────

func _init_static_level() -> void:
	# Hand-made levels ship their rooms as children of RoomContainer. But
	# many "static" levels (circle openers 1/11/21/…, milestones 75/99)
	# don't have authored content yet — if RoomContainer is empty we must
	# fall back to procedural generation or the player spawns into a void.
	if _room_container.get_child_count() == 0:
		_init_procedural_level(true)
		return
	_discover_souls()

func _init_procedural_level(force_procedural: bool = false) -> void:
	var gen: Object
	if force_procedural:
		gen = LevelGenerator.generate_procedural(level_id)
	else:
		gen = LevelGenerator.generate(level_id)

	if _level_type == "vertical":
		_build_vertical_rooms(gen.room_scenes)
	else:
		_build_horizontal_rooms(gen.room_scenes)

	_discover_souls()

	if gen.soul_id > 0:
		_mark_primary_soul(gen.soul_id, gen.soul_data)

# ── Room layout — horizontal (default) ───────────────────────────────────────

func _build_horizontal_rooms(room_scenes: Array) -> void:
	var cursor_x: float = 0.0
	for scene_path: String in room_scenes:
		var room: Node2D = _load_room(scene_path)
		if not room:
			continue
		room.position.x = cursor_x
		_room_container.add_child(room)
		cursor_x += _room_width(room)
	_reposition_spawn_and_exit_h(cursor_x)

# ── Room layout — vertical (vertical level type) ──────────────────────────────

## Vertical levels: player spawns at the TOP on a safe shelf and descends
## to the altar at the bottom. Room scenes arrive as [entrance, main…, exit]
## in play order — we keep that order so the entrance sits at y = 0 (top)
## and the exit/altar lands at the bottom of the stack.
func _build_vertical_rooms(room_scenes: Array) -> void:
	var cursor_y: float = 0.0
	for scene_path: String in room_scenes:
		var room: Node2D = _load_room(scene_path)
		if not room:
			continue
		room.position.y = cursor_y
		_room_container.add_child(room)
		cursor_y += _room_height(room)

	_reposition_spawn_and_exit_v(cursor_y)

# ── Room loader helper ────────────────────────────────────────────────────────

func _load_room(scene_path: String) -> Node2D:
	if not ResourceLoader.exists(scene_path):
		_report_warn("LevelBase: room scene not found — %s (level_id=%d)" % [scene_path, level_id])
		return null
	var packed := load(scene_path) as PackedScene
	if not packed:
		_report_warn("LevelBase: room failed to load as PackedScene — %s" % scene_path)
		return null
	var room: Node2D = packed.instantiate() as Node2D
	if not room:
		_report_warn("LevelBase: room instantiate returned null — %s" % scene_path)
		return null
	# Patch `circle` BEFORE the room is added to the tree so PlaceholderRoom._ready
	# picks the right background colour and enemy pool even when we fell back to a
	# circle_1 scene for a later circle.
	var target_circle: int = ceili(float(level_id) / 10.0)
	if "circle" in room and room.circle != target_circle:
		room.circle = target_circle
	return room

# ── Dimension helpers ─────────────────────────────────────────────────────────

func _room_width(room: Node2D) -> float:
	if room.has_meta("room_width"):
		return float(room.get_meta("room_width"))
	return 720.0  # default viewport width

func _room_height(room: Node2D) -> float:
	if room.has_meta("room_height"):
		return float(room.get_meta("room_height"))
	return 540.0  # default viewport height

# ── Spawn / exit placement ────────────────────────────────────────────────────

func _reposition_spawn_and_exit_h(total_width: float) -> void:
	if _spawn_point.position == Vector2.ZERO:
		_spawn_point.position = Vector2(80.0, -64.0)
	_exit_area.position = Vector2(total_width - 80.0, _spawn_point.position.y)

func _reposition_spawn_and_exit_v(total_height: float) -> void:
	# Entrance room is at the top → spawn on the safe shelf the entrance
	# room builds at ROW_HIGH (y≈230). Dropping the player ~97 px above
	# that shelf gives a short, visible landing and stays well under the
	# fall-damage threshold.
	_spawn_point.position = Vector2(360.0, 80.0)
	# Exit / altar sits at the bottom of the exit room (last in the stack).
	_exit_area.position   = Vector2(360.0, total_height - 80.0)

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
		_report_error("LevelBase: res://scenes/Player.tscn not found or failed to load")
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

	# Named souls pop a short reveal panel with the epitaph.
	if _soul_reveal and _soul_reveal.has_method("show_soul") \
			and soul.has_method("get_soul_data"):
		var data: Dictionary = soul.get_soul_data()
		if data.has("name") and data.get("name", "") != "":
			_soul_reveal.show_soul(data)

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
	if GameManager and GameManager.has_method("set_hp"):
		GameManager.set_hp(hp, max_hp)

# ── Level complete ────────────────────────────────────────────────────────────

func _complete_level() -> void:
	if _is_complete:
		return
	_is_complete = true
	GameManager.complete_level()

func _connect_level_complete() -> void:
	if not _level_complete or not _level_complete.has_method("show_results"):
		return
	if not GameManager:
		return
	GameManager.level_completed.connect(_on_level_completed)

func _on_level_completed(_id: int, stats: Dictionary) -> void:
	if _level_complete and _level_complete.has_method("show_results"):
		_level_complete.show_results(stats)

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
	var pos: Vector2 = _respawn_position if _respawn_position != Vector2.ZERO \
		else _spawn_point.global_position
	_player.respawn(pos)
	if _level_type == "escape":
		# Restart escape timer
		_setup_escape_timer()

# ── Altars ────────────────────────────────────────────────────────────────────

func _connect_altars() -> void:
	for altar in get_tree().get_nodes_in_group("altar"):
		if altar.has_signal("respawn_bound"):
			altar.respawn_bound.connect(_on_altar_respawn_bound)

func _on_altar_respawn_bound(world_position: Vector2) -> void:
	_respawn_position = world_position
	if GameManager and GameManager.has_method("set_checkpoint"):
		GameManager.set_checkpoint(world_position)

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
# ESC is handled by HUD._unhandled_input → pause_requested → _pause_screen.toggle().
# PauseScreen owns get_tree().paused state.

# ── DebugOverlay forwarders ───────────────────────────────────────────────────
func _report_warn(msg: String) -> void:
	if is_inside_tree():
		var d: Node = get_node_or_null("/root/DebugOverlay")
		if d and d.has_method("warn"):
			d.warn(msg)
			return
	push_warning(msg)

func _report_error(msg: String) -> void:
	if is_inside_tree():
		var d: Node = get_node_or_null("/root/DebugOverlay")
		if d and d.has_method("error"):
			d.error(msg)
			return
	push_error(msg)
