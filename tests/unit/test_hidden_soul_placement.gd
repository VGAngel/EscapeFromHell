extends GutTest

# Tests for the hidden ✦ soul placement pipeline (A11):
#   • souls_collection.json assigns levels to all 20 hidden souls
#   • LevelGenerator builds a per-level map and surfaces it on
#     GeneratedLevel.hidden_soul_data
#   • SaveManager.add_hidden_soul persists across the delivery flow

const LevelGeneratorScript := preload("res://scripts/levels/LevelGenerator.gd")
const SaveManagerScript    := preload("res://scripts/managers/SaveManager.gd")

var lg: Node

func before_each() -> void:
	lg = LevelGeneratorScript.new()
	add_child_autofree(lg)
	# _ready loads souls_collection.json into _hidden_soul_per_level.

# ── JSON data ─────────────────────────────────────────────────────────────────

func test_all_20_hidden_souls_have_level() -> void:
	var with_level: int = 0
	for soul: Dictionary in lg._souls.get("hidden_souls", []):
		if int(soul.get("level", 0)) > 0:
			with_level += 1
	assert_eq(with_level, 20,
			"every hidden ✦ soul must have a `level` assigned")

func test_two_hidden_souls_per_circle() -> void:
	var per_circle: Dictionary = {}
	for soul: Dictionary in lg._souls.get("hidden_souls", []):
		var c: int = int(soul.get("circle", 0))
		per_circle[c] = int(per_circle.get(c, 0)) + 1
	for c in range(1, 11):
		assert_eq(per_circle.get(c, 0), 2,
				"circle %d should host exactly 2 hidden souls" % c)

# ── LevelGenerator wiring ─────────────────────────────────────────────────────

func test_per_level_lookup_built() -> void:
	# Circle 1 hidden souls land on levels 5 + 8.
	assert_true(lg._hidden_soul_per_level.has(5))
	assert_true(lg._hidden_soul_per_level.has(8))
	# Circle 10 lands on 95 + 98.
	assert_true(lg._hidden_soul_per_level.has(95))
	assert_true(lg._hidden_soul_per_level.has(98))

func test_generated_level_carries_hidden_data_on_hosting_level() -> void:
	var gen: Object = lg.generate(5)
	assert_false(gen.hidden_soul_data.is_empty(),
			"level 5 should carry hidden_soul_data H1")
	assert_eq(String(gen.hidden_soul_data.get("id", "")), "H1")

func test_generated_level_no_hidden_on_regular_level() -> void:
	# Level 3 has no hidden ✦ — must come back empty.
	var gen: Object = lg.generate(3)
	assert_true(gen.hidden_soul_data.is_empty(),
			"levels without a hidden ✦ should keep hidden_soul_data empty")

# ── SaveManager flow ──────────────────────────────────────────────────────────

func test_save_manager_add_hidden_records_id() -> void:
	var sm: Node = SaveManagerScript.new()
	add_child_autofree(sm)
	sm.add_hidden_soul("H1")
	sm.add_hidden_soul("H7")
	var ids: Array = sm.get_hidden_soul_ids()
	assert_true("H1" in ids)
	assert_true("H7" in ids)
	assert_eq(sm.get_total_hidden_souls(), 2)

func test_save_manager_add_hidden_idempotent() -> void:
	var sm: Node = SaveManagerScript.new()
	add_child_autofree(sm)
	sm.add_hidden_soul("H1")
	sm.add_hidden_soul("H1")
	assert_eq(sm.get_total_hidden_souls(), 1,
			"re-adding the same hidden id must not double-count")
