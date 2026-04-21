@tool
extends Node2D

# PlaceholderRoom — generates a fully playable placeholder room at runtime.
#
# Attach to a Node2D in a room .tscn. Set exported vars via the scene file.
# The script draws walls/background and creates StaticBody2D physics at startup.
#
# LevelBase reads room_width / room_height from node metadata; we write those
# in _ready() so no manual metadata entry is needed in the .tscn.

## "entrance" | "main" | "exit"
@export var room_type: String = "main"

## Room variant index (shown in the debug label).
@export var room_index: int = 1

## Circle number (affects background color).
@export var circle: int = 1

## Width in pixels.
@export var room_width: float = 720.0

## Height in pixels.
@export var room_height: float = 540.0

const WALL_T: float = 32.0

# Per-circle base colors (index 0 = unused, 1-10 = circles)
const CIRCLE_COLORS: Array = [
	Color(0, 0, 0),             # 0 – unused
	Color(0.10, 0.04, 0.20),    # 1 – void purple
	Color(0.04, 0.10, 0.20),    # 2 – deep blue
	Color(0.20, 0.08, 0.04),    # 3 – charred red
	Color(0.04, 0.16, 0.08),    # 4 – swamp green
	Color(0.18, 0.12, 0.02),    # 5 – gold dust
	Color(0.02, 0.14, 0.18),    # 6 – icy teal
	Color(0.14, 0.02, 0.14),    # 7 – crimson dusk
	Color(0.16, 0.08, 0.00),    # 8 – iron rust
	Color(0.08, 0.08, 0.08),    # 9 – ashen grey
	Color(0.20, 0.00, 0.00),    # 10 – blood red (final)
]

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Expose dimensions as metadata so LevelBase._room_width/height() can read them.
	set_meta("room_width",  room_width)
	set_meta("room_height", room_height)

	if not Engine.is_editor_hint():
		_build_walls()
		_spawn_enemies()

	queue_redraw()

# ── Enemy spawning ────────────────────────────────────────────────────────────

# Each circle has a pool of enemy scenes. One is picked per "main" room based
# on room_index so rooms feel varied without being fully random.
const ENEMY_POOLS := {
	1: [
		"res://scenes/enemies/ShadowLost.tscn",
		"res://scenes/enemies/PaleWanderer.tscn",
	],
}

func _spawn_enemies() -> void:
	if room_type != "main":
		return
	var pool: Array = ENEMY_POOLS.get(circle, [])
	if pool.is_empty():
		return
	var scene_path: String = pool[room_index % pool.size()]
	if not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if not packed:
		return
	var enemy := packed.instantiate() as Node2D
	if not enemy:
		return
	var x_offset: float = 140.0 + float((room_index * 73) % 320)
	enemy.position = Vector2(x_offset, room_height - WALL_T - 40.0)
	add_child(enemy)

# ── Physics walls ─────────────────────────────────────────────────────────────

func _build_walls() -> void:
	_add_wall("Floor",   Vector2(room_width / 2.0, room_height - WALL_T / 2.0),
						 Vector2(room_width, WALL_T))
	_add_wall("Ceiling", Vector2(room_width / 2.0, WALL_T / 2.0),
						 Vector2(room_width, WALL_T))
	_add_wall("WallL",   Vector2(WALL_T / 2.0, room_height / 2.0),
						 Vector2(WALL_T, room_height))
	_add_wall("WallR",   Vector2(room_width - WALL_T / 2.0, room_height / 2.0),
						 Vector2(WALL_T, room_height))

	# Variant mid-platforms based on room_index so rooms differ visually
	match room_type:
		"main":
			_add_main_platforms()
		"entrance":
			# Low platform near bottom-center — gives footing on spawn
			_add_platform(Vector2(room_width / 2.0, room_height - WALL_T - 80.0),
						  Vector2(240.0, WALL_T))
		"exit":
			# Two raised ledges near the top for the altar area
			_add_platform(Vector2(room_width / 2.0, WALL_T + 120.0), Vector2(300.0, WALL_T))

const ONE_WAY_SCRIPT   := preload("res://scripts/platforms/OneWayPlatform.gd")
const CRUMBLING_SCRIPT := preload("res://scripts/platforms/CrumblingPlatform.gd")
const BOUNCE_SCRIPT    := preload("res://scripts/platforms/BouncePlatform.gd")
const MOVING_SCRIPT    := preload("res://scripts/platforms/MovingPlatform.gd")

func _add_main_platforms() -> void:
	# Five distinct layouts keyed by room_index % 5 so even large pools vary.
	# Each variant mixes in one special platform type so players meet each
	# mechanic within a short sequence of rooms.
	match room_index % 5:
		0:  # zigzag staircase — middle step is one-way
			_add_platform(Vector2(180, 200), Vector2(160, WALL_T))
			_add_typed_platform(Vector2(380, 320), Vector2(160, WALL_T), "one_way")
			_add_platform(Vector2(560, 200), Vector2(160, WALL_T))
		1:  # single wide shelf — crumbles under you
			_add_typed_platform(Vector2(room_width / 2.0, 280), Vector2(400, WALL_T), "crumbling")
		2:  # two low shelves — left one is a bounce pad
			_add_typed_platform(Vector2(200, 360), Vector2(200, WALL_T), "bounce")
			_add_platform(Vector2(520, 360), Vector2(200, WALL_T))
		3:  # high static + low moving horizontal
			_add_platform(Vector2(240, 180), Vector2(180, WALL_T))
			_add_typed_platform(Vector2(480, 380), Vector2(180, WALL_T), "moving_horizontal")
		4:  # center pillar — bottom rises/falls
			_add_platform(Vector2(room_width / 2.0, 200), Vector2(120, WALL_T))
			_add_typed_platform(Vector2(room_width / 2.0, 380), Vector2(120, WALL_T), "moving_vertical")

func _add_typed_platform(pos: Vector2, sz: Vector2, type: String) -> void:
	var body: PhysicsBody2D = null
	match type:
		"one_way":
			body = StaticBody2D.new()
			body.set_script(ONE_WAY_SCRIPT)
		"crumbling":
			body = StaticBody2D.new()
			body.set_script(CRUMBLING_SCRIPT)
		"bounce":
			body = StaticBody2D.new()
			body.set_script(BOUNCE_SCRIPT)
		"moving_horizontal":
			body = AnimatableBody2D.new()
			body.set_script(MOVING_SCRIPT)
			body.set("move_axis", "horizontal")
			body.set("distance",  140.0)
		"moving_vertical":
			body = AnimatableBody2D.new()
			body.set_script(MOVING_SCRIPT)
			body.set("move_axis", "vertical")
			body.set("distance",  80.0)
		_:
			_add_platform(pos, sz)
			return
	body.name = "TypedPlatform_%d" % get_child_count()
	body.position = pos
	body.set("size", sz)
	add_child(body)

func _add_wall(wall_name: String, pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.position = pos
	body.collision_layer = 1
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape_node.shape = rect
	body.add_child(shape_node)
	add_child(body)

func _add_platform(pos: Vector2, size: Vector2) -> void:
	var body := StaticBody2D.new()
	body.name = "Platform_%d" % get_child_count()
	body.position = pos
	body.collision_layer = 1
	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape_node.shape = rect
	body.add_child(shape_node)
	add_child(body)

# ── Visuals ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var bg: Color = CIRCLE_COLORS[clampi(circle, 0, CIRCLE_COLORS.size() - 1)]
	var wall_c: Color = bg.darkened(0.35)

	# Background fill
	draw_rect(Rect2(0, 0, room_width, room_height), bg)

	# Walls (editor-visible even without physics)
	draw_rect(Rect2(0, room_height - WALL_T, room_width, WALL_T), wall_c)  # floor
	draw_rect(Rect2(0, 0, room_width, WALL_T),                   wall_c)  # ceiling
	draw_rect(Rect2(0, 0, WALL_T, room_height),                  wall_c)  # left
	draw_rect(Rect2(room_width - WALL_T, 0, WALL_T, room_height), wall_c)  # right

	# Type badge
	var type_colors := {"entrance": Color(0.2, 0.8, 0.3), "main": Color(0.6, 0.6, 0.9), "exit": Color(1.0, 0.85, 0.2)}
	var badge_c: Color = type_colors.get(room_type, Color.WHITE)
	draw_rect(Rect2(WALL_T + 4, WALL_T + 4, 12, 12), badge_c)

	# Debug label
	var font := ThemeDB.fallback_font
	var label := "circle_%d / %s_%d  [%.0f×%.0f]" % [circle, room_type, room_index, room_width, room_height]
	draw_string(font, Vector2(WALL_T + 22, WALL_T + 16), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))
