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

## Set by LevelBase for vertical levels. Removes floor/ceiling at room junctions
## so the player can pass freely between stacked rooms:
##   entrance → ceiling kept, floor removed
##   main     → ceiling removed, floor removed
##   exit     → ceiling removed, floor kept
@export var is_vertical: bool = false

## Level ID — set by LevelBase so config queries work.
@export var level_id: int = 0

const WALL_T: float = 32.0
const PLATFORM_T: float = 16.0

# Three-row platform layout (540-tall room).
# Row heights assume jump_force=540 / gravity=900 → max rise 162 px and
# walking-head clearance at y=418. ROW_LOW bottom (=y+8) sits at 398,
# leaving a 20 px corridor. Each row is 80 px above the next so both
# climbing up and dropping down stay within the jump budget.
const ROW_LOW:  float = 390.0
const ROW_MID:  float = 310.0
const ROW_HIGH: float = 230.0

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
		_spawn_environment_hazard()
		_spawn_soul()
		_spawn_altar()
		_spawn_bonus()

	queue_redraw()

# ── Enemy spawning ────────────────────────────────────────────────────────────

# Maps levels_config.json enemy_type strings → placeholder scene paths.
# These scenes serve until per-enemy art ships; swap path here, not in config.
const ENEMY_SCENE_MAP := {
	"skeleton":         "res://scenes/enemies/ShadowLost.tscn",
	"skeleton_warrior": "res://scenes/enemies/PaleWanderer.tscn",
	"skeleton_archer":  "res://scenes/enemies/PaleWanderer.tscn",
	"undead_archer":    "res://scenes/enemies/PaleWanderer.tscn",
	"skeleton_witch":   "res://scenes/enemies/WindShade.tscn",
	"necromancer":      "res://scenes/enemies/WindShade.tscn",
	"stone_golem":      "res://scenes/enemies/CursedStone.tscn",
	"fire_golem":       "res://scenes/enemies/FlameImp.tscn",
	"ice_golem":        "res://scenes/enemies/FrostShade.tscn",
	"succubus":         "res://scenes/enemies/RageShade.tscn",
	"hell_knight":      "res://scenes/enemies/HellKnight.tscn",
	"demon_archer":     "res://scenes/enemies/FireHound.tscn",
	"magician_demon":   "res://scenes/enemies/HeresyPriest.tscn",
	"blood_demon":      "res://scenes/enemies/BloodHound.tscn",
	"mimic":            "res://scenes/enemies/MimicShade.tscn",
	"ghost_warrior":    "res://scenes/enemies/WindShade.tscn",
	"phantom_knight":   "res://scenes/enemies/SilentStalker.tscn",
	"dark_entity":      "res://scenes/enemies/VoidSentinel.tscn",
	"reaper":           "res://scenes/enemies/ThroneGuard.tscn",
	"fallen_angel":     "res://scenes/enemies/FrostKnight.tscn",
}

# Fallback pools used when LevelConfig is absent (editor preview, unit tests).
const ENEMY_FALLBACK_POOLS := {
	1:  ["res://scenes/enemies/ShadowLost.tscn",   "res://scenes/enemies/PaleWanderer.tscn"],
	2:  ["res://scenes/enemies/WindShade.tscn",    "res://scenes/enemies/PaleWanderer.tscn"],
	3:  ["res://scenes/enemies/FlameImp.tscn",     "res://scenes/enemies/FireHound.tscn"],
	4:  ["res://scenes/enemies/SwampCrawler.tscn", "res://scenes/enemies/BogPhantom.tscn"],
	5:  ["res://scenes/enemies/RageShade.tscn",    "res://scenes/enemies/FrostKnight.tscn"],
	6:  ["res://scenes/enemies/HeresyPriest.tscn", "res://scenes/enemies/CursedStone.tscn"],
	7:  ["res://scenes/enemies/HellKnight.tscn",   "res://scenes/enemies/BloodHound.tscn"],
	8:  ["res://scenes/enemies/MimicShade.tscn",   "res://scenes/enemies/ClockworkGuard.tscn"],
	9:  ["res://scenes/enemies/FrostShade.tscn",   "res://scenes/enemies/SilentStalker.tscn"],
	10: ["res://scenes/enemies/VoidSentinel.tscn", "res://scenes/enemies/ThroneGuard.tscn"],
}

func _spawn_enemies() -> void:
	if room_type != "main":
		return
	var scene_path: String = _pick_enemy_scene()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
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

func _pick_enemy_scene() -> String:
	if LevelConfig and level_id > 0:
		var types: Array = LevelConfig.get_enemies(level_id)
		if not types.is_empty():
			var type_key: String = types[room_index % types.size()]
			var path: String = ENEMY_SCENE_MAP.get(type_key, "")
			if not path.is_empty():
				return path
	var pool: Array = ENEMY_FALLBACK_POOLS.get(circle, [])
	if pool.is_empty():
		return ""
	return pool[room_index % pool.size()]

# ── Soul spawning ─────────────────────────────────────────────────────────────

func _spawn_soul() -> void:
	if room_type != "main":
		return
	var soul_path := "res://scenes/Soul.tscn"
	if not ResourceLoader.exists(soul_path):
		return
	var packed := load(soul_path) as PackedScene
	if not packed:
		return
	var soul := packed.instantiate() as Node2D
	if not soul:
		return
	soul.add_to_group("soul")
	# Place the soul on the high platform so the player must platformer to reach it.
	soul.position = Vector2(room_width * 0.5, ROW_HIGH - 24.0)
	add_child(soul)

# ── Bonus spawning ────────────────────────────────────────────────────────────

const BONUS_SCENE := "res://scenes/BonusPickup.tscn"
# Maps levels_config bonus strings → BonusPickup.BonusType int
# (HOLY_WATER=0, PRAYER_STONE=1, ANGEL_FEATHER=2, MANNA=3, TORCH=4)
const BONUS_ENUM := {
	"holy_water":    0,
	"prayer_stone":  1,
	"angel_feather": 2,
	"manna":         3,
	"torch":         4,
}

func _spawn_bonus() -> void:
	if room_type != "main":
		return
	# Only odd-indexed rooms get a bonus (even-indexed get a hazard).
	if room_index % 2 == 0:
		return
	var bonuses: Array = []
	if LevelConfig and level_id > 0:
		bonuses = LevelConfig.get_bonuses(level_id)
	if bonuses.is_empty():
		return
	if not ResourceLoader.exists(BONUS_SCENE):
		return
	var packed := load(BONUS_SCENE) as PackedScene
	if not packed:
		return
	var bonus := packed.instantiate()
	if not bonus:
		return
	var key: String = bonuses[room_index % bonuses.size()]
	bonus.set("bonus_type", BONUS_ENUM.get(key, 3))
	# Place on the mid-row platform so the player must navigate up to reach it.
	bonus.position = Vector2(room_width * 0.5, ROW_MID - 40.0)
	add_child(bonus)

# ── Altar spawning ────────────────────────────────────────────────────────────

const ALTAR_SCRIPT := preload("res://scripts/AltarNode.gd")

func _spawn_altar() -> void:
	if room_type != "exit":
		return
	var altar := Node2D.new()
	altar.set_script(ALTAR_SCRIPT)
	altar.name = "AltarNode"
	altar.add_to_group("altar")
	# Altar sits on the high-platform shelf in the exit room.
	altar.position = Vector2(room_width * 0.5, ROW_HIGH - 32.0)

	var area := Area2D.new()
	area.name = "Area2D"
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 64.0
	col.shape = shape
	area.add_child(col)
	altar.add_child(area)

	add_child(altar)

# ── Physics walls ─────────────────────────────────────────────────────────────

func _build_walls() -> void:
	# In vertical levels the player descends through stacked rooms.
	# Remove the floor on rooms that open downward and the ceiling on rooms
	# that open upward, so there is no physics barrier between rooms.
	var needs_floor:   bool = not is_vertical or room_type == "exit"
	var needs_ceiling: bool = not is_vertical or room_type == "entrance"

	if needs_floor:
		_add_wall("Floor", Vector2(room_width / 2.0, room_height - WALL_T / 2.0),
						   Vector2(room_width, WALL_T))
	if needs_ceiling:
		_add_wall("Ceiling", Vector2(room_width / 2.0, WALL_T / 2.0),
							 Vector2(room_width, WALL_T))
	_add_wall("WallL", Vector2(WALL_T / 2.0, room_height / 2.0),
					   Vector2(WALL_T, room_height))
	_add_wall("WallR", Vector2(room_width - WALL_T / 2.0, room_height / 2.0),
					   Vector2(WALL_T, room_height))

	# Variant mid-platforms based on room_index so rooms differ visually
	match room_type:
		"main":
			_add_main_platforms()
		"entrance":
			# Safe landing shelf near the top — LevelBase spawns the
			# player ~97 px above this for a short, visible drop.
			# Stepping stones descend toward the door at the floor.
			_add_platform(Vector2(room_width / 2.0, ROW_HIGH),
						  Vector2(240.0, PLATFORM_T))
			_add_platform(Vector2(room_width / 2.0, ROW_MID),
						  Vector2(160.0, PLATFORM_T))
			_add_platform(Vector2(room_width / 2.0, ROW_LOW),
						  Vector2(200.0, PLATFORM_T))
		"exit":
			# Ladder of shelves up to the altar — each row reachable from
			# the one below within the 162 px jump budget.
			_add_platform(Vector2(room_width * 0.30, ROW_LOW),  Vector2(140.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.70, ROW_LOW),  Vector2(140.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.50, ROW_MID),  Vector2(180.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.50, ROW_HIGH), Vector2(240.0, PLATFORM_T))

const ONE_WAY_SCRIPT     := preload("res://scripts/platforms/OneWayPlatform.gd")
const CRUMBLING_SCRIPT   := preload("res://scripts/platforms/CrumblingPlatform.gd")
const BOUNCE_SCRIPT      := preload("res://scripts/platforms/BouncePlatform.gd")
const MOVING_SCRIPT      := preload("res://scripts/platforms/MovingPlatform.gd")
const MUD_SCRIPT         := preload("res://scripts/platforms/MudPlatform.gd")
const ASH_SCRIPT         := preload("res://scripts/platforms/AshPlatform.gd")
const FAITH_SCRIPT       := preload("res://scripts/platforms/FaithPlatform.gd")
const SIN_SCRIPT         := preload("res://scripts/platforms/SinPlatform.gd")
const ILLUSORY_SCRIPT    := preload("res://scripts/platforms/IllusoryPlatform.gd")
const ICE_SCRIPT         := preload("res://scripts/platforms/IcePlatform.gd")
const SOUL_BRIDGE_SCRIPT := preload("res://scripts/platforms/SoulBridgePlatform.gd")

const BASE_PLATFORM_SCRIPT := preload("res://scripts/platforms/BasePlatform.gd")

const WIND_ZONE_SCRIPT  := preload("res://scripts/environments/WindZone.gd")
const LAVA_ZONE_SCRIPT  := preload("res://scripts/environments/LavaZone.gd")
const SWAMP_ZONE_SCRIPT := preload("res://scripts/environments/SwampZone.gd")

# ── Environment hazards per circle ────────────────────────────────────────────

func _spawn_environment_hazard() -> void:
	if room_type != "main":
		return
	# Only even-indexed rooms get a hazard — keeps the challenge varied.
	if room_index % 2 != 0:
		return
	# Pull trap list from config when available; fall back to circle heuristic.
	var traps: Array = []
	if LevelConfig and level_id > 0:
		traps = LevelConfig.get_traps(level_id)
	if traps.is_empty():
		traps = _fallback_traps_for_circle(circle)
	if traps.is_empty():
		return
	var trap_type: String = traps[room_index % traps.size()]
	match trap_type:
		"wind_blast":
			_add_wind_zone()
		"lava_pit", "lava_flow":
			_add_lava_zone()
		"sinking_platform", "poison_gas":
			_add_swamp_zone()
		# Other trap types will have dedicated scenes when art ships.

func _fallback_traps_for_circle(c: int) -> Array:
	match c:
		2: return ["sinking_platform", "poison_gas"]
		3: return ["lava_pit", "lava_flow"]
		4: return ["sinking_platform"]
		_: return []

func _add_wind_zone() -> void:
	var zone := Area2D.new()
	zone.set_script(WIND_ZONE_SCRIPT)
	zone.position = Vector2(room_width * 0.5, room_height * 0.45)
	zone.set("zone_size", Vector2(room_width - WALL_T * 2.0, 160.0))
	# Alternate direction across rooms so the player has to read each one.
	@warning_ignore("integer_division")
	var group: int = room_index / 2
	var dir := Vector2.RIGHT if group % 2 == 0 else Vector2.LEFT
	zone.set("wind_direction", dir)
	zone.set("wind_force", 280.0)
	add_child(zone)

func _add_lava_zone() -> void:
	var zone := Area2D.new()
	zone.set_script(LAVA_ZONE_SCRIPT)
	# Floor-hugging lava strip in the middle of the room, leaving walkable
	# shoulders on both sides.
	var lava_width: float = room_width * 0.4
	zone.position = Vector2(room_width * 0.5, room_height - WALL_T - 12.0)
	zone.set("zone_size", Vector2(lava_width, 24.0))
	add_child(zone)

func _add_swamp_zone() -> void:
	var zone := Area2D.new()
	zone.set_script(SWAMP_ZONE_SCRIPT)
	# Swamp covers most of the floor except the edges where the player spawns.
	var swamp_width: float = room_width - WALL_T * 2.0 - 120.0
	zone.position = Vector2(room_width * 0.5, room_height - WALL_T - 24.0)
	zone.set("zone_size", Vector2(swamp_width, 48.0))
	add_child(zone)

func _add_main_platforms() -> void:
	# Three-row platform layout so the player can drop from any shelf,
	# fall to the floor, and climb back up. Rows live at ROW_LOW/MID/HIGH
	# (80 px apart, all within the 162 px jump budget). Columns sit at
	# ~22% / 50% / 78% of the room width so gaps between shelves stay
	# inside the ~185 px horizontal jump range at an 80-px rise.
	#
	# Each variant keeps the same scaffolding and just swaps one shelf
	# for a special type so players meet each mechanic in sequence.
	var col_l: float = room_width * 0.22
	var col_c: float = room_width * 0.50
	var col_r: float = room_width * 0.78
	var shelf: Vector2 = Vector2(110.0, PLATFORM_T)
	var wide:  Vector2 = Vector2(200.0, PLATFORM_T)

	match room_index % 5:
		0:  # zigzag — mid-center is one-way (drop through)
			_add_platform(Vector2(col_l, ROW_LOW),  shelf)
			_add_platform(Vector2(col_r, ROW_LOW),  shelf)
			_add_typed_platform(Vector2(col_c, ROW_MID), shelf, "one_way")
			_add_platform(Vector2(col_l, ROW_HIGH), shelf)
			_add_platform(Vector2(col_r, ROW_HIGH), shelf)
		1:  # wide crumbling shelf in the middle row
			_add_platform(Vector2(col_l, ROW_LOW),  shelf)
			_add_platform(Vector2(col_r, ROW_LOW),  shelf)
			_add_typed_platform(Vector2(col_c, ROW_MID), wide, "crumbling")
			_add_platform(Vector2(col_c, ROW_HIGH), shelf)
		2:  # bounce pad bottom-left, static ladder on the right
			_add_typed_platform(Vector2(col_l, ROW_LOW), shelf, "bounce")
			_add_platform(Vector2(col_r, ROW_LOW),  shelf)
			_add_platform(Vector2(col_c, ROW_MID),  shelf)
			_add_platform(Vector2(col_l, ROW_HIGH), shelf)
			_add_platform(Vector2(col_r, ROW_HIGH), shelf)
		3:  # horizontal mover bridges the mid row
			_add_platform(Vector2(col_l, ROW_LOW),  shelf)
			_add_platform(Vector2(col_r, ROW_LOW),  shelf)
			_add_typed_platform(Vector2(col_c, ROW_MID), shelf, "moving_horizontal")
			_add_platform(Vector2(col_l, ROW_HIGH), shelf)
			_add_platform(Vector2(col_r, ROW_HIGH), shelf)
		4:  # vertical mover shuttles between mid and high rows
			_add_platform(Vector2(col_l, ROW_LOW),  shelf)
			_add_platform(Vector2(col_r, ROW_LOW),  shelf)
			_add_typed_platform(Vector2(col_c, ROW_MID), shelf, "moving_vertical")
			_add_platform(Vector2(col_l, ROW_HIGH), shelf)
			_add_platform(Vector2(col_r, ROW_HIGH), shelf)

func _add_typed_platform(pos: Vector2, sz: Vector2, type: String) -> void:
	# Circle-specific overrides — each circle reshapes the same procedural
	# layout by swapping in its thematic platform type. Keeps the room
	# geometry stable while giving each circle a distinct feel.
	var resolved: String = type
	match circle:
		4:
			if type == "crumbling": resolved = "mud"
		5:
			if type == "crumbling": resolved = "ash"
		6:
			if type == "crumbling": resolved = "faith"
		7:
			if type == "crumbling": resolved = "illusory"
			elif type == "one_way": resolved = "sin_platform"
		9:
			if type == "one_way":   resolved = "ice"
		10:
			if type == "one_way":   resolved = "soul_bridge"

	var body: PhysicsBody2D = null
	match resolved:
		"one_way":
			body = StaticBody2D.new()
			body.set_script(ONE_WAY_SCRIPT)
		"crumbling":
			body = StaticBody2D.new()
			body.set_script(CRUMBLING_SCRIPT)
		"bounce":
			body = StaticBody2D.new()
			body.set_script(BOUNCE_SCRIPT)
		"mud":
			body = StaticBody2D.new()
			body.set_script(MUD_SCRIPT)
		"ash":
			body = StaticBody2D.new()
			body.set_script(ASH_SCRIPT)
		"faith":
			body = StaticBody2D.new()
			body.set_script(FAITH_SCRIPT)
		"sin_platform":
			body = StaticBody2D.new()
			body.set_script(SIN_SCRIPT)
		"illusory":
			body = StaticBody2D.new()
			body.set_script(ILLUSORY_SCRIPT)
		"ice":
			body = StaticBody2D.new()
			body.set_script(ICE_SCRIPT)
		"soul_bridge":
			body = StaticBody2D.new()
			body.set_script(SOUL_BRIDGE_SCRIPT)
		"moving_horizontal":
			body = AnimatableBody2D.new()
			body.set_script(MOVING_SCRIPT)
			body.set("move_axis", "horizontal")
			body.set("distance",  140.0)
		"moving_vertical":
			body = AnimatableBody2D.new()
			body.set_script(MOVING_SCRIPT)
			body.set("move_axis", "vertical")
			# Negative distance → platform rises UP from its start position.
			# If we moved down it would sweep through the walking corridor
			# (player head ≈ y=418 standing on the floor).
			body.set("distance",  -80.0)
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
	# BasePlatform handles both the collision shape and the PlaceholderVisual,
	# so plain stone shelves show up on screen instead of being invisible
	# air-walls the player bumps into.
	var body := StaticBody2D.new()
	body.set_script(BASE_PLATFORM_SCRIPT)
	body.name = "Platform_%d" % get_child_count()
	body.position = pos
	body.collision_layer = 1
	body.set("platform_type", "stone")
	body.set("size", size)
	add_child(body)
	# One-way: player can jump up through the shelf from below and land on top.
	var shape: CollisionShape2D = body.get("_shape")
	if shape:
		shape.one_way_collision = true
		shape.one_way_collision_margin = 2.0

# ── Visuals ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	var bg: Color = CIRCLE_COLORS[clampi(circle, 0, CIRCLE_COLORS.size() - 1)]
	var wall_c: Color = bg.darkened(0.35)

	# Background fill
	draw_rect(Rect2(0, 0, room_width, room_height), bg)

	# Walls — match physics: omit floor/ceiling that are open in vertical levels
	var needs_floor:   bool = not is_vertical or room_type == "exit"
	var needs_ceiling: bool = not is_vertical or room_type == "entrance"
	if needs_floor:
		draw_rect(Rect2(0, room_height - WALL_T, room_width, WALL_T), wall_c)
	if needs_ceiling:
		draw_rect(Rect2(0, 0, room_width, WALL_T), wall_c)
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
