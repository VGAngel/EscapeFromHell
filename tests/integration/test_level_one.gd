extends GutTest

# End-to-end smoke tests for level 1 — the first level new players see.
# Covers regressions users hit before:
#   * RoomContainer empty (static level without content) → invisible scene
#   * Player sprite missing → invisible player
#   * Player camera not current → camera stuck on (0,0)
#   * Player outside room bounds → falls into void
#
# Uses the real autoloads and the actual Level.tscn + Player.tscn so
# nothing is mocked away.

const LEVEL_SCENE  := preload("res://scenes/levels/Level.tscn")
const PLAYER_SCENE := preload("res://scenes/Player.tscn")

var level: Node2D

func before_each() -> void:
	if SaveManager:
		SaveManager._reset()
	if GameManager:
		GameManager.current_level_id = 1

# ── Helpers ───────────────────────────────────────────────────────────────────

func _make_level() -> Node2D:
	var l: Node2D = LEVEL_SCENE.instantiate() as Node2D
	l.level_id = 1
	add_child_autofree(l)
	return l

func _find_player(root: Node) -> CharacterBody2D:
	for child in root.get_children():
		if child.is_in_group("player"):
			return child as CharacterBody2D
	return null

# ── LevelGenerator contract for level 1 ───────────────────────────────────────

func test_level_1_is_flagged_static() -> void:
	assert_true(LevelGenerator.is_static(1),
		"level 1 is a circle opener; LevelGenerator must treat it as static")

func test_generate_procedural_produces_rooms_for_level_1() -> void:
	var res: Object = LevelGenerator.generate_procedural(1)
	assert_gt(res.room_scenes.size(), 0,
		"fallback path must still return a non-empty room list")

# ── LevelBase fallback ────────────────────────────────────────────────────────

func test_level_1_spawns_rooms_via_fallback() -> void:
	level = _make_level()
	var rc: Node = level.get_node("RoomContainer")
	assert_gt(rc.get_child_count(), 0,
		"level 1 ships with no hand-made content — LevelBase must fall back " +
		"to procedural generation. RoomContainer was empty → user sees a void.")

# ── Player presence ───────────────────────────────────────────────────────────

func test_player_is_spawned_and_in_group() -> void:
	level = _make_level()
	var p: CharacterBody2D = _find_player(level)
	assert_not_null(p, "LevelBase._spawn_player must add Player.tscn as a child")

func test_player_has_visible_sprite() -> void:
	level = _make_level()
	var p: CharacterBody2D = _find_player(level)
	assert_not_null(p)
	var anim_sprite: AnimatedSprite2D = p.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	assert_not_null(anim_sprite, "AnimatedSprite2D child required for Dark_Elves frames")
	assert_not_null(anim_sprite.sprite_frames,
		"SpriteFrames must be loaded — otherwise the player is an invisible " +
		"rectangle following the camera")

func test_player_has_idle_animation_loaded() -> void:
	level = _make_level()
	var p: CharacterBody2D = _find_player(level)
	var anim_sprite: AnimatedSprite2D = p.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	assert_true(anim_sprite.sprite_frames.has_animation("player_idle"),
		"player_idle animation must be present — it's the default state")
	assert_gt(anim_sprite.sprite_frames.get_frame_count("player_idle"), 0,
		"player_idle must have at least one frame")

# ── Camera priority ───────────────────────────────────────────────────────────

func test_player_camera_becomes_current() -> void:
	level = _make_level()
	var p: CharacterBody2D = _find_player(level)
	var cam: Camera2D = p.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(cam, "Player.tscn ships a Camera2D child")
	# In Godot 4, make_current() sets the node as the viewport's active camera
	# once in tree — verify the method was called by checking the scene tree.
	var active: Camera2D = p.get_viewport().get_camera_2d()
	assert_eq(active, cam,
		"Player's Camera2D must take over from Level.tscn's static camera; " +
		"otherwise the camera stays at (0,0) and the player falls off-screen.")

# ── Spawn inside a room ───────────────────────────────────────────────────────

func test_player_spawns_inside_total_room_stack_y_range() -> void:
	# Level 1 is vertical — rooms stack from y=0 downward. Total stack
	# height = room_count * 540 for the default room_height. Player must
	# spawn somewhere inside [0, total_h], otherwise _spawn_point math
	# got inverted and they're outside every room.
	level = _make_level()
	var p: CharacterBody2D = _find_player(level)
	var rc: Node = level.get_node("RoomContainer")
	var room_count: int = rc.get_child_count()
	assert_gt(room_count, 0)
	var max_y: float = float(room_count) * 540.0
	var pos: Vector2 = p.global_position
	assert_true(pos.y >= 0.0 and pos.y <= max_y,
		"Player spawn y=%.0f must be within [0, %.0f] for a %d-room vertical stack" % [
			pos.y, max_y, room_count])
	assert_true(pos.x >= 0.0 and pos.x <= 720.0,
		"Player spawn x=%.0f must be within the room width [0, 720]" % pos.x)
