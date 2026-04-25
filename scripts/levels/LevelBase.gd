extends Node2D

# Base script for all procedural and static non-boss levels.
# Attach to the root Node2D of Level.tscn.
#
# Expected scene structure:
#   Level (Node2D) ← this script
#   ├── HUD          (CanvasLayer, script: scripts/HUD.gd)
#   ├── RoomContainer (Node2D)   ← rooms are added here at runtime
#   ├── SpawnPoint   (Marker2D)  ← default player spawn
#   ├── Exit         (Node2D)    ← PortalExit script; activated after soul delivery
#   └── Camera2D / PhantomCamera2D

# ── Exports ───────────────────────────────────────────────────────────────────
@export var level_id:     int  = 1
@export var force_static: bool = false  # skip generator, use existing scene children

# ── Child node references ─────────────────────────────────────────────────────
@onready var _hud:               Node       = $HUD
@onready var _pause_screen:      Node       = $PauseScreen
@onready var _collection_screen: Node       = get_node_or_null("CollectionScreen")
@onready var _settings_screen:   Node       = get_node_or_null("SettingsScreen")
@onready var _room_container:  Node2D     = $RoomContainer
@onready var _spawn_point:     Marker2D   = $SpawnPoint
@onready var _exit_area:       Node2D     = $Exit
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
var _carried_soul_data:  Dictionary      = {}

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
	_connect_bonuses()
	_connect_altars()
	_setup_escape_timer()

	GameManager.register_hud(_hud)
	GameManager.begin_level(level_id, _souls_required)
	_hud.pause_requested.connect(_pause_screen.toggle)
	_pause_screen.collection_requested.connect(_on_pause_collection)
	_pause_screen.settings_requested.connect(_on_pause_settings)
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
		var w: float = float(room_node.get_meta("room_width", 1080.0))
		var h: float = float(room_node.get_meta("room_height", 900.0))
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
		_build_vertical_shaft(gen)
	else:
		_build_horizontal_rooms(gen.room_scenes)

	var dbg: Node = get_node_or_null("/root/DebugOverlay")
	if dbg and dbg.has_method("show_zone"):
		dbg.show_zone(level_id, gen.difficulty_zone, gen.vertical_spacing,
			gen.platform_type_hint, gen.platform_width)

	_spawn_soul_node(gen)
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

# ── Room layout — vertical (single shaft) ────────────────────────────────────

## Vertical levels are ONE tall room (a "shaft") instead of N stacked
## 2-screen rooms — eliminates cross-room platform gaps and lets the Markov
## section pacing flow uninterrupted across the full descent.
##
## We still need an underlying scene to instantiate (PlaceholderRoom carries
## the script + exported defaults), so we borrow the entrance scene of the
## level's circle — overrides below replace the per-scene values that mattered
## for the old multi-room path.
func _build_vertical_shaft(gen: Object) -> void:
	var circle: int = ceili(float(level_id) / 10.0)
	var scene_path: String = ""
	if not gen.room_scenes.is_empty():
		scene_path = String(gen.room_scenes[0])
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/rooms/circle_%d/room_entrance_1.tscn" % circle
	if not ResourceLoader.exists(scene_path):
		scene_path = "res://scenes/rooms/circle_1/room_entrance_1.tscn"
	var room: Node2D = _load_room(scene_path)
	if not room:
		_report_warn("LevelBase: failed to build vertical shaft for level %d" % level_id)
		return
	if "is_vertical" in room:
		room.is_vertical = true
	if "room_type" in room:
		room.room_type = "shaft"
	if "room_count" in room:
		room.room_count = maxi(1, gen.room_count)
	if "tileset" in room and LevelConfig:
		room.tileset = LevelConfig.get_tileset_for_level(level_id)
	# Force a sane width — entrance scenes ship with 720 px, but the shaft
	# uses the full 1080 px viewport so Markov has room to spread platforms.
	if "room_width" in room:
		room.room_width = 1080.0
	room.position = Vector2.ZERO
	_room_container.add_child(room)

	_reposition_spawn_and_exit_v(_room_height(room))

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
	# Patch exported vars BEFORE the room is added to the tree so PlaceholderRoom._ready
	# picks the right background colour, enemy pool, and config queries.
	var target_circle: int = ceili(float(level_id) / 10.0)
	if "circle" in room and room.circle != target_circle:
		room.circle = target_circle
	if "level_id" in room:
		room.level_id = level_id
	return room

# ── Dimension helpers ─────────────────────────────────────────────────────────

func _room_width(room: Node2D) -> float:
	if room.has_meta("room_width"):
		return float(room.get_meta("room_width"))
	return 1080.0

func _room_height(room: Node2D) -> float:
	if room.has_meta("room_height"):
		return float(room.get_meta("room_height"))
	return 900.0

# ── Spawn / exit placement ────────────────────────────────────────────────────

func _reposition_spawn_and_exit_h(total_width: float) -> void:
	var sa_top: int = SafeArea.top_reserved if SafeArea else 0
	var rooms: Array = _room_container.get_children()
	var rh: float = _room_height(rooms[0]) if not rooms.is_empty() else 900.0

	if _spawn_point.position == Vector2.ZERO:
		# Spawn near the left edge, at the floor level minus player height + buffer.
		var spawn_y: float = rh - 32.0 - 100.0 - float(sa_top) - 20.0
		_spawn_point.position = Vector2(80.0, spawn_y)

	_exit_area.position = Vector2(total_width - 80.0, _spawn_point.position.y)

func _reposition_spawn_and_exit_v(total_height: float) -> void:
	# Safe area insets — push spawn/exit away from notch and home bar.
	var sa_top:    int = SafeArea.top_reserved    if SafeArea else 0
	var sa_bottom: int = SafeArea.bottom_reserved if SafeArea else 0

	# Room width from the first child (entrance room); fall back to viewport width.
	var rooms: Array = _room_container.get_children()
	var rw: float = _room_width(rooms[0]) if not rooms.is_empty() else 1080.0

	# Default spawn: centre X, just below the ceiling.
	var spawn_x: float = rw * 0.5
	var spawn_y: float = float(sa_top) + 32.0 + 60.0   # WALL_T=32 + drop buffer

	# Prefer spawning on the same top platform as the altar so the player
	# lands exactly where the altar stands. PlaceholderRoom adds the altar
	# before _ready() returns, so it is already in the tree here.
	var altar_node: Node = get_tree().get_first_node_in_group("altar")
	if altar_node and is_instance_valid(altar_node):
		var local: Vector2 = to_local(altar_node.global_position)
		spawn_x = local.x
		spawn_y = local.y - 60.0   # drop buffer so player falls onto the platform

	# Exit: centre X, just above the floor safe area of the last room.
	var exit_x: float = rw * 0.5
	var exit_y: float = total_height - float(sa_bottom) - 32.0 - 60.0

	_spawn_point.position = Vector2(spawn_x, spawn_y)
	_exit_area.position   = Vector2(exit_x,  exit_y)

# ── Soul discovery ────────────────────────────────────────────────────────────

func _discover_souls() -> void:
	_souls_in_level.clear()
	for soul in get_tree().get_nodes_in_group("soul"):
		_souls_in_level.append(soul)
	var cfg_count: int = LevelConfig.get_souls_count(level_id) if LevelConfig else _souls_in_level.size()
	_souls_required = mini(_souls_in_level.size(), maxi(cfg_count, 1))
	_assign_soul_types()

func _spawn_soul_node(_gen: Object) -> void:
	var soul_scene := load("res://scenes/Soul.tscn") as PackedScene
	if not soul_scene:
		_report_warn("LevelBase: Soul.tscn not found — no soul spawned")
		return
	var soul: Node = soul_scene.instantiate()

	# Place soul at roughly 65% of level height (vertical) or 50% width (horizontal).
	var rooms: Array = _room_container.get_children()
	if rooms.is_empty():
		soul.position = Vector2(360.0, 400.0)
	elif _level_type == "vertical":
		var total_h: float = 0.0
		for r: Node in rooms:
			total_h += _room_height(r)
		var cx: float = _room_width(rooms[0]) * 0.5 if not rooms.is_empty() else 540.0
		soul.position = Vector2(cx, total_h * 0.65)
	else:
		var total_w: float = 0.0
		for r: Node in rooms:
			total_w += _room_width(r)
		var rh: float = _room_height(rooms[0]) if not rooms.is_empty() else 900.0
		soul.position = Vector2(total_w * 0.5, rh * 0.35)

	# Apply soul type from level config before _discover_souls() runs.
	var types: Array = LevelConfig.get_soul_types(level_id) if LevelConfig else []
	if soul.has_method("set_soul_type"):
		soul.set_soul_type(types[0] if not types.is_empty() else "innocent")

	_room_container.add_child(soul)

func _assign_soul_types() -> void:
	var types: Array = LevelConfig.get_soul_types(level_id) if LevelConfig else []
	for i: int in _souls_in_level.size():
		var soul: Node = _souls_in_level[i]
		if soul.has_method("set_soul_type"):
			soul.set_soul_type(types[i] if i < types.size() else "innocent")

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
	_player.soul_dropped.connect(_on_soul_dropped)
	_player.hp_changed.connect(_on_player_hp_changed)

# ── Exit ──────────────────────────────────────────────────────────────────────

func _connect_exit() -> void:
	if _exit_area.has_signal("player_entered"):
		_exit_area.player_entered.connect(_on_exit_entered)
	elif _exit_area.has_signal("body_entered"):
		_exit_area.body_entered.connect(_on_exit_body_entered)
	else:
		push_warning("Level: Exit node has no recognised entry signal")

func _on_exit_entered() -> void:
	if _is_complete:
		return
	if _souls_found < _souls_required:
		if TutorialManager:
			TutorialManager.show_hint("collect_souls_first")
		return
	_complete_level()

func _on_exit_body_entered(body: Node2D) -> void:
	if body != _player or _is_complete:
		return
	if _souls_found < _souls_required:
		if TutorialManager:
			TutorialManager.show_hint("collect_souls_first")
		return
	_complete_level()

# ── Souls ─────────────────────────────────────────────────────────────────────

func _connect_souls() -> void:
	for soul in _souls_in_level:
		if soul.has_signal("soul_pickup_started"):
			soul.soul_pickup_started.connect(_on_soul_pickup_started)

## Called when the player manually picks up a soul from the ground.
## Stores soul data so it can be shown on altar delivery.
func _on_soul_pickup_started(soul: Node) -> void:
	var soul_id: int = soul.get_meta("soul_id", 0)
	_carried_soul_data = {"soul_id": soul_id}
	if soul.has_method("get_soul_data"):
		_carried_soul_data.merge(soul.get_soul_data())
	if soul.has_method("get_soul_type"):
		_carried_soul_data["soul_type"] = soul.get_soul_type()

	var boss: Node = _get_boss()
	if boss and boss.has_method("on_collectible_picked"):
		boss.on_collectible_picked()

# ── Bonuses ───────────────────────────────────────────────────────────────────

func _connect_bonuses() -> void:
	for bonus in get_tree().get_nodes_in_group("bonus"):
		if bonus.has_signal("bonus_collected"):
			bonus.bonus_collected.connect(_on_bonus_collected)

func _on_bonus_collected(type: int, bonus_name: String) -> void:
	match type:
		0:  # HOLY_WATER — невразливість 5с
			if _player and _player.has_method("apply_invincibility"):
				_player.apply_invincibility(5.0)
			if GameManager:
				GameManager.activate_bonus("holy_water", "💧", 5.0)
		1:  # PRAYER_STONE — заморожує ворогів 8с
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if enemy.has_method("stun"):
					enemy.stun(8.0)
			if GameManager:
				GameManager.activate_bonus("prayer_stone", "🪨", 8.0)
		2:  # ANGEL_FEATHER — тимчасовий подвійний стрибок 30с
			if _player and _player.has_method("apply_temp_double_jump"):
				_player.apply_temp_double_jump(30.0)
			if GameManager:
				GameManager.activate_bonus("angel_feather", "🪶", 30.0)
		3:  # MANNA — відновлює 1 серце
			if _player and _player.has_method("heal"):
				_player.heal(1)
			elif _player:
				_player.current_hp = mini(_player.current_hp + 1, _player.max_hp)
				_player.hp_changed.emit(_player.current_hp, _player.max_hp)
		4:  # TORCH — майбутній ефект освітлення
			if GameManager:
				GameManager.activate_bonus("torch", "🔦", 30.0)
	if TutorialManager and TutorialManager.has_method("show_hint"):
		TutorialManager.show_hint("bonus_" + bonus_name.to_lower())

## Called when the player dies while carrying a soul.
## Re-spawns a Soul node at the death position so the player can retrieve it.
func _on_soul_dropped(_soul_id: String, drop_position: Vector2) -> void:
	var soul_scene := load("res://scenes/Soul.tscn") as PackedScene
	if not soul_scene or not _room_container:
		_carried_soul_data = {}
		return
	var soul: Node2D = soul_scene.instantiate()
	# Convert world drop position to _room_container local space before _ready()
	# captures _base_y for the bobbing animation.
	soul.position = drop_position - _room_container.global_position
	_room_container.add_child(soul)
	var soul_type: String = _carried_soul_data.get("soul_type", "innocent")
	if soul.has_method("set_soul_type"):
		soul.set_soul_type(soul_type)
	var stored_id: int = int(_carried_soul_data.get("soul_id", 0))
	if stored_id != 0 and soul.has_method("set_soul_data"):
		var data: Dictionary = _carried_soul_data.duplicate()
		data.erase("soul_type")
		soul.set_soul_data(stored_id, data)
		soul.set_meta("soul_id", stored_id)
	if soul.has_signal("soul_pickup_started"):
		soul.soul_pickup_started.connect(_on_soul_pickup_started)
	if not _souls_in_level.has(soul):
		_souls_in_level.append(soul)
	_carried_soul_data = {}

func _on_soul_delivered(soul_id: String) -> void:
	_souls_found += 1
	var id: int = soul_id.to_int() if soul_id.is_valid_int() else \
		_carried_soul_data.get("soul_id", 0)
	GameManager.collect_soul(id)
	# Show soul name reveal panel here — at delivery, not at pickup.
	if _soul_reveal and _soul_reveal.has_method("show_soul") \
			and _carried_soul_data.has("name") and _carried_soul_data.get("name", "") != "":
		_soul_reveal.show_soul(_carried_soul_data)
	_show_soul_delivered_popup()
	_carried_soul_data = {}
	if _souls_found >= _souls_required and _exit_area and _exit_area.has_method("activate"):
		_exit_area.activate()

func _show_soul_delivered_popup() -> void:
	if not _player or not is_inside_tree():
		return
	var lbl := Label.new()
	lbl.text = "Душа доставлена"
	lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	lbl.position = _player.global_position + Vector2(-60.0, -120.0)
	add_child(lbl)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 120.0, 2.2)
	tw.tween_property(lbl, "modulate:a", 0.0, 2.2).set_delay(0.4)
	await get_tree().create_timer(2.6).timeout
	if is_instance_valid(lbl):
		lbl.queue_free()

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
	# Lift respawn slightly so the player has time to react and lands on the
	# first platform instead of falling straight past it.
	pos.y -= 80.0
	_player.respawn(pos)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("reset_to_patrol"):
			enemy.reset_to_patrol()
	if _level_type == "escape":
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

# ── Pause overlay callbacks ───────────────────────────────────────────────────

func _on_pause_collection() -> void:
	if _collection_screen and _collection_screen.has_method("open"):
		_collection_screen.open()

func _on_pause_settings() -> void:
	if _settings_screen and _settings_screen.has_method("open"):
		_settings_screen.open()

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
