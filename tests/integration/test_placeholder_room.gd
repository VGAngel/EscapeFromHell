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
	assert_almost_eq(float(room.get_meta("room_width")), 1080.0, 0.001)

func test_metadata_room_height_set_after_ready() -> void:
	var room := _make_room("main", 1)
	assert_true(room.has_meta("room_height"))
	assert_almost_eq(float(room.get_meta("room_height")), 900.0, 0.001)

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

# ── Markov vertical layout (tests 7-9) ────────────────────────────────────────
#
# _build_vertical_layout is the heart of the shaft generator. Tests here lock
# in the contracts that matter for gameplay regression detection:
#   7  reachability: every consecutive row pair is jumpable in physics
#   8  determinism : same (level_id, room_index) → identical layout
#   9  config     : SECTION_PROFILES + TIER_SECTIONS schema is consistent
#
# autofree(RoomScript.new()) avoids add_child → _ready never runs → walls /
# spawns / asset loads stay out of the way. _build_vertical_layout is pure
# enough to drive directly with manually-set instance vars.

func _make_layout_room() -> Node2D:
	var room: Node2D = autofree(RoomScript.new())
	room.level_id          = 1
	room.room_index        = 1
	room.room_width        = 1080.0
	room._zone_tier        = "easy"
	room._platform_width   = 220.0
	room._platform_type_hint = "stone"
	return room

# Build an evenly-spaced row sequence — same shape as _compute_all_rows would
# return for a real shaft. Returns rows from floor (largest Y) to ceiling
# (smallest Y), spacing 180 px (= MAX_JUMP_HEIGHT × 0.9).
func _make_rows(count: int, spacing: float = 180.0, floor_y: float = 3608.0) -> Array:
	var rows: Array = []
	for i in count:
		rows.append(floor_y - float(i) * spacing)
	return rows

# ── Test 7: reachability ──────────────────────────────────────────────────────

func test_markov_layout_consecutive_y_gaps_are_reachable() -> void:
	var room := _make_layout_room()
	var rows := _make_rows(20)
	var layout: Array = room._build_vertical_layout(rows)

	assert_eq(layout.size(), rows.size(),
		"_build_vertical_layout must produce one entry per input row")

	var max_gap: float = 0.0
	for i in range(1, layout.size()):
		var gap: float = absf(float(layout[i].y) - float(layout[i - 1].y))
		max_gap = maxf(max_gap, gap)

	# MAX_JUMP_HEIGHT × 1.15 leaves room for ±12% Y-jitter without false
	# positives. Catches catastrophic regressions (multi-room ~600 px gaps,
	# or jitter scaling bugs) — current code averages around 180 px gaps.
	var ceiling: float = LevelGenerator.MAX_JUMP_HEIGHT * 1.15
	assert_lt(max_gap, ceiling,
		"max consecutive Y-gap %d must stay below physical jump reach %d" % [int(max_gap), int(ceiling)])

func test_markov_layout_x_distance_respects_jump_arc() -> void:
	# Reachability snap-back must keep |Δx| ≤ horizontal_reach(v_gap) plus
	# half the widths of both platforms (player can walk to the edge before
	# launching). Loose tolerance handles bridge rows (anchor ≠ real platform).
	var room := _make_layout_room()
	var rows := _make_rows(20)
	var layout: Array = room._build_vertical_layout(rows)

	for i in range(1, layout.size()):
		var prev = layout[i - 1]
		var curr = layout[i]
		# Bridges place two real platforms on opposite walls — the snap-back
		# logic uses anchor X only, so skip those pairs from the strict check.
		if String(prev.kind) == "bridge" or String(curr.kind) == "bridge":
			continue
		var v_gap: float = float(prev.y) - float(curr.y)         # > 0 = up
		var max_h: float = room._max_horizontal_jump(v_gap)
		var allowed: float = max_h + (float(prev.width) + float(curr.width)) * 0.5
		var dx: float = absf(float(curr.x) - float(prev.x))
		assert_lte(dx, allowed + 1.0,  # +1 px FP slack
			"row %d → %d: dx %d exceeds reach %d (v_gap=%d)" \
				% [i - 1, i, int(dx), int(allowed), int(v_gap)])

# ── Test 8: deterministic seed ────────────────────────────────────────────────

func test_markov_same_seed_produces_identical_layouts() -> void:
	# Layouts are seeded by hash(level_id × 1000 + room_index). Same inputs
	# must produce byte-identical output so replays / debug seed copy works.
	var rows := _make_rows(15)
	var room_a := _make_layout_room()
	room_a.level_id = 5
	room_a.room_index = 3
	var room_b := _make_layout_room()
	room_b.level_id = 5
	room_b.room_index = 3
	var layout_a: Array = room_a._build_vertical_layout(rows)
	var layout_b: Array = room_b._build_vertical_layout(rows)

	assert_eq(layout_a.size(), layout_b.size())
	for i in layout_a.size():
		assert_almost_eq(float(layout_a[i].x), float(layout_b[i].x), 0.001,
			"row %d X must match" % i)
		assert_almost_eq(float(layout_a[i].y), float(layout_b[i].y), 0.001,
			"row %d Y must match" % i)
		assert_eq(String(layout_a[i].kind), String(layout_b[i].kind),
			"row %d kind must match" % i)

func test_markov_different_seeds_produce_different_layouts() -> void:
	# Sanity: the seed actually varies output. Same level, different rooms
	# → at least one row differs.
	var rows := _make_rows(15)
	var room_a := _make_layout_room()
	room_a.level_id = 5
	room_a.room_index = 1
	var room_b := _make_layout_room()
	room_b.level_id = 5
	room_b.room_index = 99
	var layout_a: Array = room_a._build_vertical_layout(rows)
	var layout_b: Array = room_b._build_vertical_layout(rows)

	var any_differ: bool = false
	for i in layout_a.size():
		if absf(float(layout_a[i].x) - float(layout_b[i].x)) > 1.0:
			any_differ = true
			break
	assert_true(any_differ, "different room_index must produce at least one different X")

func test_markov_world_seed_affects_layout() -> void:
	# Two players with different world seeds (set from the main-menu seed
	# button) MUST get different layouts for the same level/room — otherwise
	# the seed control is cosmetic and replays diverge silently.
	if not SaveManager:
		pending("SaveManager autoload unavailable — skipped")
		return
	var rows := _make_rows(15)
	var original_seed: String = SaveManager.get_world_seed_str()

	SaveManager.set_world_seed_str("seed_a_xyz")
	var room_a := _make_layout_room()
	room_a.level_id = 1
	room_a.room_index = 1
	var layout_a: Array = room_a._build_vertical_layout(rows)

	SaveManager.set_world_seed_str("seed_b_qwe")
	var room_b := _make_layout_room()
	room_b.level_id = 1
	room_b.room_index = 1
	var layout_b: Array = room_b._build_vertical_layout(rows)

	# Restore original world seed so other tests aren't polluted.
	SaveManager.set_world_seed_str(original_seed)

	var any_differ: bool = false
	for i in layout_a.size():
		if absf(float(layout_a[i].x) - float(layout_b[i].x)) > 1.0:
			any_differ = true
			break
	assert_true(any_differ,
		"world seed change must alter Markov layout for the same (level_id, room_index)")

# ── Test 9: section profile / tier templates schema ───────────────────────────

func test_tier_sections_covers_all_difficulty_tiers() -> void:
	# TIER_SECTIONS must define a section sequence for every tier returned
	# by LevelGenerator.get_zone() — easy / medium / hard / extreme.
	var required: Array[String] = ["easy", "medium", "hard", "extreme"]
	for tier in required:
		assert_true(RoomScript.TIER_SECTIONS.has(tier),
			"TIER_SECTIONS missing entry for tier '%s'" % tier)
		assert_gt((RoomScript.TIER_SECTIONS[tier] as Array).size(), 0,
			"tier '%s' must have at least one section in its template" % tier)

func test_section_profiles_have_required_keys() -> void:
	# Every section name referenced by TIER_SECTIONS must exist in
	# SECTION_PROFILES with all the fields _build_vertical_layout reads.
	var required_keys: Array[String] = ["length_min", "length_max",
			"widths", "types", "bridge_chance"]
	for tier in RoomScript.TIER_SECTIONS:
		for section_name in RoomScript.TIER_SECTIONS[tier]:
			assert_true(RoomScript.SECTION_PROFILES.has(section_name),
				"section '%s' (referenced by tier '%s') missing from SECTION_PROFILES" \
					% [section_name, tier])
			var profile: Dictionary = RoomScript.SECTION_PROFILES[section_name]
			for key in required_keys:
				assert_true(profile.has(key),
					"profile '%s' missing key '%s'" % [section_name, key])

func test_section_profile_widths_and_types_are_well_formed() -> void:
	# Every weighted-bag entry must be [value, weight] with positive weight,
	# and the bag must sum to > 0 so _sample_weighted picks something.
	for section_name in RoomScript.SECTION_PROFILES:
		var profile: Dictionary = RoomScript.SECTION_PROFILES[section_name]
		for bag_key in ["widths", "types"]:
			var bag: Array = profile[bag_key]
			assert_gt(bag.size(), 0, "'%s'.%s is empty" % [section_name, bag_key])
			var total: float = 0.0
			for entry in bag:
				assert_eq((entry as Array).size(), 2,
					"'%s'.%s entry must be [value, weight]" % [section_name, bag_key])
				total += float(entry[1])
			assert_gt(total, 0.0,
				"'%s'.%s weights must sum > 0" % [section_name, bag_key])
