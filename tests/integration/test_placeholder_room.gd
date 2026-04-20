extends GutTest

# Integration tests for PlaceholderRoom.gd.
#
# PlaceholderRoom generates walls/platforms in _ready() and exposes
# room_width / room_height as node metadata so LevelBase can read them.

const RoomScript := preload("res://scripts/rooms/PlaceholderRoom.gd")

func _make_room(type: String, idx: int, circle: int = 1) -> Node2D:
	var room: Node2D = Node2D.new()
	room.set_script(RoomScript)
	room.set("room_type",  type)
	room.set("room_index", idx)
	room.set("circle",     circle)
	add_child_autofree(room)
	return room

# ── Metadata ──────────────────────────────────────────────────────────────────

func test_metadata_room_width_set_after_ready() -> void:
	var room := _make_room("main", 1)
	assert_true(room.has_meta("room_width"))
	assert_almost_eq(float(room.get_meta("room_width")), 720.0, 0.001)

func test_metadata_room_height_set_after_ready() -> void:
	var room := _make_room("main", 1)
	assert_true(room.has_meta("room_height"))
	assert_almost_eq(float(room.get_meta("room_height")), 540.0, 0.001)

func test_custom_room_width_reflected_in_metadata() -> void:
	var room: Node2D = Node2D.new()
	room.set_script(RoomScript)
	room.set("room_width",  960.0)
	room.set("room_height", 720.0)
	add_child_autofree(room)
	assert_almost_eq(float(room.get_meta("room_width")),  960.0, 0.001)
	assert_almost_eq(float(room.get_meta("room_height")), 720.0, 0.001)

# ── Physics walls ─────────────────────────────────────────────────────────────

func test_entrance_room_has_physics_children() -> void:
	var room := _make_room("entrance", 1)
	var static_bodies := room.get_children().filter(
		func(c): return c is StaticBody2D)
	assert_gt(static_bodies.size(), 0, "entrance room must have at least one wall")

func test_main_room_has_floor_wall() -> void:
	var room := _make_room("main", 1)
	var names: Array = room.get_children().map(func(c): return c.name)
	assert_true("Floor" in names, "main room must have a Floor StaticBody2D")

func test_main_room_has_ceiling_wall() -> void:
	var room := _make_room("main", 1)
	var names: Array = room.get_children().map(func(c): return c.name)
	assert_true("Ceiling" in names, "main room must have a Ceiling StaticBody2D")

func test_exit_room_has_walls() -> void:
	var room := _make_room("exit", 1)
	var static_bodies := room.get_children().filter(
		func(c): return c is StaticBody2D)
	assert_gte(static_bodies.size(), 4, "exit room must have at least 4 wall bodies")

# ── Room variants ─────────────────────────────────────────────────────────────

func test_main_room_variants_differ_in_child_count() -> void:
	# Variant 0 and variant 1 (room_index % 5) have different platform counts
	var r0 := _make_room("main", 5)   # index 5 → 5%5=0 → zigzag (3 extra platforms)
	var r1 := _make_room("main", 1)   # index 1 → 1%5=1 → single shelf (1 extra platform)
	# Both have 4 walls; variants add different numbers of platforms
	assert_ne(r0.get_child_count(), r1.get_child_count(),
		"different room_index variants should produce different child counts")

# ── Scene loading ─────────────────────────────────────────────────────────────

func test_circle1_entrance_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/rooms/circle_1/room_entrance_1.tscn"))

func test_circle1_exit_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/rooms/circle_1/room_exit_1.tscn"))

func test_circle1_main_scenes_exist_1_to_24() -> void:
	for i in range(1, 25):
		var path := "res://scenes/rooms/circle_1/room_main_%d.tscn" % i
		assert_true(ResourceLoader.exists(path), "missing: %s" % path)

func test_circle1_entrance_loads_and_has_metadata() -> void:
	var packed := load("res://scenes/rooms/circle_1/room_entrance_1.tscn") as PackedScene
	assert_not_null(packed)
	var room: Node2D = packed.instantiate() as Node2D
	add_child_autofree(room)
	assert_true(room.has_meta("room_width"))
	assert_true(room.has_meta("room_height"))

func test_circle1_main_1_loads_and_has_correct_dimensions() -> void:
	var packed := load("res://scenes/rooms/circle_1/room_main_1.tscn") as PackedScene
	assert_not_null(packed)
	var room: Node2D = packed.instantiate() as Node2D
	add_child_autofree(room)
	assert_almost_eq(float(room.get_meta("room_width")),  720.0, 0.001)
	assert_almost_eq(float(room.get_meta("room_height")), 540.0, 0.001)
