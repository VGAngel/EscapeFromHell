extends GutTest

# Integration tests for LevelBase.gd (Node2D).
# Requires a fully built Level.tscn scene with RoomContainer and SpawnPoint.

# ── _room_width ───────────────────────────────────────────────────────────────

func test_room_width_returns_720_for_room_without_meta() -> void:
	# TODO: create bare Node2D room without "room_width" meta,
	# instantiate LevelBase, call _room_width(room),
	# assert result == 720
	pass

func test_room_width_returns_meta_value_when_set() -> void:
	# TODO: create Node2D with set_meta("room_width", 960),
	# assert _room_width() returns 960
	pass

# ── Soul discovery ────────────────────────────────────────────────────────────

func test_discover_souls_counts_nodes_in_group() -> void:
	# TODO: add 3 Soul nodes to group "soul" in scene,
	# call _discover_souls(), assert _souls_total == 3
	pass

func test_souls_required_matches_level_config() -> void:
	# TODO: mock LevelConfig.get_souls_count() = 2,
	# assert _souls_required == 2 after _ready()
	pass

# ── Exit logic ────────────────────────────────────────────────────────────────

func test_exit_locked_when_souls_missing() -> void:
	# TODO: set _souls_found = 0, _souls_required = 2,
	# trigger exit body_entered with player, assert level NOT completed
	pass

func test_exit_triggers_complete_when_all_souls_collected() -> void:
	# TODO: set _souls_found == _souls_required,
	# trigger exit, assert complete_level() called (watch GameManager signal)
	pass

# ── Respawn ───────────────────────────────────────────────────────────────────

func test_player_teleported_to_spawn_on_respawn() -> void:
	# TODO: connect player_respawned, move player away from spawn,
	# emit respawn, assert player position == SpawnPoint.global_position
	pass

# ── Procedural room layout ────────────────────────────────────────────────────

func test_rooms_positioned_sequentially() -> void:
	# TODO: generate a 3-room layout, assert each room.position.x
	# is offset by its predecessor's _room_width()
	pass
