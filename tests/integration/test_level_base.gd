extends GutTest

# Integration tests for LevelBase.gd (Node2D).
#
# LevelBase._ready() requires $HUD/$RoomContainer/$SpawnPoint/$Exit children
# AND spawns Player.tscn — so add_child_autofree on a bare node would crash.
# Two strategies are used:
#
# 1. autofree() — node never enters the tree; _ready() / @onready never fire.
#    Good for pure logic: _room_width, exit body checks, _complete_level.
#
# 2. SafeLevel inner class — overrides _ready() to no-op.
#    NOTE: in Godot 4 @onready runs at NOTIFICATION_READY *before* _ready(),
#    so stub children (HUD, RoomContainer, SpawnPoint, Exit) must be added
#    to the node BEFORE add_child_autofree() is called.
#    Used for _discover_souls which needs get_tree().get_nodes_in_group().

const LevelBaseScript := preload("res://scripts/LevelBase.gd")

class SafeLevel extends LevelBaseScript:
	func _ready() -> void:
		pass  # skip game init; @onready vars are already set by notification


# Build a SafeLevel with the four stub children @onready expects,
# then add it to the scene.  Returns the node (already in tree).
func _make_safe_lb() -> Node:
	var lb: Node = SafeLevel.new()
	var hud := Node.new();    hud.name = "HUD"
	var rc  := Node2D.new();  rc.name  = "RoomContainer"
	var sp  := Marker2D.new(); sp.name = "SpawnPoint"
	var ex  := Area2D.new();  ex.name  = "Exit"
	lb.add_child(hud)
	lb.add_child(rc)
	lb.add_child(sp)
	lb.add_child(ex)
	add_child_autofree(lb)
	return lb


func after_each() -> void:
	# complete_level() sets GameManager._is_transitioning — reset between tests.
	if GameManager:
		GameManager._is_transitioning = false

# ── _room_width ───────────────────────────────────────────────────────────────

func test_room_width_returns_720_for_room_without_meta() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var room: Node2D = autofree(Node2D.new())
	assert_almost_eq(lb._room_width(room), 720.0, 0.001)

func test_room_width_returns_meta_value_when_set() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var room: Node2D = autofree(Node2D.new())
	room.set_meta("room_width", 960)
	assert_almost_eq(lb._room_width(room), 960.0, 0.001)

# ── Exit logic ────────────────────────────────────────────────────────────────

func test_exit_ignores_non_player_body() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	var other: CharacterBody2D  = autofree(CharacterBody2D.new())
	lb._player = player
	lb._souls_required = 0  # would allow completion if body were player
	lb._on_exit_body_entered(other)
	assert_false(lb._is_complete)

func test_exit_does_not_complete_when_souls_missing() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	lb._player         = player
	lb._souls_found    = 1
	lb._souls_required = 3
	lb._on_exit_body_entered(player)
	assert_false(lb._is_complete)

func test_exit_completes_level_when_all_souls_collected() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	lb._player         = player
	lb._souls_found    = 2
	lb._souls_required = 2
	lb._on_exit_body_entered(player)
	assert_true(lb._is_complete)

func test_exit_skipped_when_already_complete() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	var player: CharacterBody2D = autofree(CharacterBody2D.new())
	lb._player         = player
	lb._souls_found    = 2
	lb._souls_required = 2
	lb._is_complete    = true
	lb._on_exit_body_entered(player)
	assert_true(lb._is_complete)

# ── _complete_level ───────────────────────────────────────────────────────────

func test_complete_level_sets_is_complete_flag() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	lb._complete_level()
	assert_true(lb._is_complete)

func test_complete_level_is_idempotent() -> void:
	var lb: Node = autofree(LevelBaseScript.new())
	lb._complete_level()
	lb._complete_level()   # second call should be a no-op (guard at top)
	assert_true(lb._is_complete)

# ── _discover_souls ───────────────────────────────────────────────────────────

func test_discover_souls_counts_nodes_in_group() -> void:
	var lb: Node = _make_safe_lb()

	var s1: Node = Node.new()
	s1.add_to_group("soul")
	add_child_autofree(s1)

	var s2: Node = Node.new()
	s2.add_to_group("soul")
	add_child_autofree(s2)

	lb._discover_souls()
	assert_eq(lb._souls_required, 2)

func test_discover_souls_empty_when_none_in_group() -> void:
	var lb: Node = _make_safe_lb()
	lb._discover_souls()
	assert_eq(lb._souls_required, 0)

func test_discover_souls_populates_souls_in_level_array() -> void:
	var lb: Node = _make_safe_lb()

	var s: Node = Node.new()
	s.add_to_group("soul")
	add_child_autofree(s)

	lb._discover_souls()
	assert_eq(lb._souls_in_level.size(), 1)

# ── _on_soul_collected ────────────────────────────────────────────────────────

func test_on_soul_collected_increments_souls_found() -> void:
	# _on_soul_collected calls _get_boss() → get_tree(), so the node must be
	# in the scene tree.  Use _make_safe_lb() which adds it properly.
	var lb: Node = _make_safe_lb()
	var soul: Node2D = autofree(Node2D.new())
	soul.set_meta("soul_id", 0)
	lb._on_soul_collected(soul)
	assert_eq(lb._souls_found, 1)

func test_on_soul_collected_increments_multiple_times() -> void:
	var lb: Node = _make_safe_lb()
	var soul: Node2D = autofree(Node2D.new())
	soul.set_meta("soul_id", 0)
	lb._on_soul_collected(soul)
	lb._on_soul_collected(soul)
	assert_eq(lb._souls_found, 2)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_souls_required_matches_level_config() -> void:
	# TODO: fully initialized level — requires static or procedural room setup
	pass

func test_rooms_positioned_sequentially() -> void:
	# TODO: requires LevelGenerator.generate() with real room scenes in tree
	pass

func test_player_teleported_to_spawn_on_respawn() -> void:
	# TODO: requires Player.tscn + Marker2D spawn point in the tree
	pass
