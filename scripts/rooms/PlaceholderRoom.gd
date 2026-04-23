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
@export var room_width: float = 1080.0

## Height in pixels.
@export var room_height: float = 900.0

## Set by LevelBase for vertical levels. Removes floor/ceiling at room junctions
## so the player can pass freely between stacked rooms:
##   entrance → ceiling kept, floor removed
##   main     → ceiling removed, floor removed
##   exit     → ceiling removed, floor kept
@export var is_vertical: bool = false

## Level ID — set by LevelBase so config queries work.
@export var level_id: int = 0

const WALL_T:      float = 32.0   # floor / ceiling + horizontal room side walls
const SIDE_WALL_T: float = 60.0   # side walls in vertical rooms
const PLATFORM_T:  float = 30.0

# Viewport dimensions — must match project.godot display/window settings.
const VIEWPORT_WIDTH:  float = 1080.0
const VIEWPORT_HEIGHT: float = 1920.0

# Vertical levels span this many screens so the player has room to traverse.
const VERTICAL_ROOM_SCREENS: int = 2

# Row Y positions — computed in _init_zone() from difficulty spacing.
# Based on: floor_y - spacing * N.
# Ensure _row_high leaves enough clearance for PLAYER_HEIGHT + WALL_T above.
var _row_low:  float = 0.0
var _row_mid:  float = 0.0
var _row_high: float = 0.0

# Zone data populated from LevelGenerator.get_zone(level_id) in _init_zone().
var _zone_tier:          String = "medium"
var _platform_width:     float  = 160.0
var _platform_type_hint: String = "stone"

# Bridge rows added by _init_zone() when the computed row spacing exceeds
# MAX_JUMP_HEIGHT. Each entry is a Y position for a static stone platform.
var _bridge_rows: Array = []

# All platform row Y positions for vertical rooms (empty for horizontal).
# Computed in _init_zone() when is_vertical=true; used by _add_main_platforms().
var _all_rows: Array = []

# Per-row layout for vertical rooms — built once in _init_zone() by the Markov
# generator and consumed by both _add_vertical_main_platforms() (placement) and
# _init_zone() itself (per-row v_range so missing_bridge_ys() sees the truth).
# Each entry: { "x": float, "y": float, "kind": String, "width": float, "type": String }
# kind ∈ "single" | "bridge".
var _vert_layout: Array[Dictionary] = []

# ── Section profiles (vertical level pacing) ──────────────────────────────────
#
# Each vertical room is divided into "sections" stacked from bottom to top, like
# beats in a song: rest → challenge → spike → breath → … The Markov generator
# samples width and platform type from the active section's bag, so the player
# experiences a designed rhythm instead of uniform difficulty.
#
# Width multipliers are relative to the zone's _platform_width (110-220 px).
# Type "_hint" is replaced at runtime by the zone's _platform_type_hint
# (stone / moving_horizontal / moving_vertical depending on tier).
const SECTION_PROFILES := {
	"rest": {
		"length_min": 2, "length_max": 3,
		"widths": [[1.5, 0.5], [2.2, 0.5]],
		"types":  [["stone", 1.0]],
		"bridge_chance": 0.0,
	},
	"challenge": {
		"length_min": 3, "length_max": 5,
		"widths": [[0.7, 0.15], [1.0, 0.45], [1.5, 0.40]],
		"types":  [["stone", 0.80], ["_hint", 0.20]],
		"bridge_chance": 0.05,
	},
	"spike": {
		"length_min": 3, "length_max": 4,
		"widths": [[0.7, 0.45], [1.0, 0.45], [1.5, 0.10]],
		"types":  [["stone", 0.30], ["crumbling", 0.25], ["bounce", 0.10],
				["one_way", 0.10], ["_hint", 0.25]],
		"bridge_chance": 0.0,
	},
	"breath": {
		"length_min": 2, "length_max": 3,
		"widths": [[1.5, 0.7], [2.2, 0.3]],
		"types":  [["stone", 1.0]],
		"bridge_chance": 0.20,
	},
}

# Section sequence templates per tier. Keep the loop short; the generator
# cycles through and clips/extends to fit the actual row count of the room.
const TIER_SECTIONS := {
	"easy":    ["rest", "challenge", "breath", "challenge", "rest"],
	"medium":  ["rest", "challenge", "spike", "breath", "challenge", "rest"],
	"hard":    ["challenge", "spike", "breath", "spike", "challenge", "spike"],
	"extreme": ["spike", "challenge", "spike", "breath", "spike", "spike"],
}

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
	# Vertical levels must be at least VERTICAL_ROOM_SCREENS tall so the
	# player has enough space to traverse up and down.
	if is_vertical:
		room_height = VIEWPORT_HEIGHT * VERTICAL_ROOM_SCREENS

	set_meta("room_width",  room_width)
	set_meta("room_height", room_height)

	_init_zone()

	if not Engine.is_editor_hint():
		_build_walls()
		_spawn_enemies()
		_spawn_environment_hazard()
		_spawn_soul()
		_spawn_altar()
		_spawn_bonus()

	queue_redraw()

func _init_zone() -> void:
	var spacing: float = LevelGenerator.PART_JUMP + LevelGenerator.STEP_JUMP  # medium default

	if level_id > 0:
		var zone: Dictionary = LevelGenerator.get_zone(level_id)
		_zone_tier          = zone.get("tier", "medium")
		spacing             = zone.get("spacing", spacing)
		_platform_width     = zone.get("platform_width", _platform_width)
		_platform_type_hint = zone.get("platform_type", _platform_type_hint)

	# Vertical rooms: stretch row spacing toward the jump ceiling so the screen
	# isn't wallpapered with platforms. Capped at 0.9 × MAX_JUMP_HEIGHT to keep
	# every row reachable without bridge inserts.
	if is_vertical:
		spacing = maxf(spacing, LevelGenerator.MAX_JUMP_HEIGHT * 0.9)

	# Safe area: read OS insets (notch, home bar) from SafeArea autoload.
	# Content must stay inside [ceiling_y .. floor_y] on every device.
	var sa_bottom: int = SafeArea.bottom_reserved if SafeArea else 0
	var sa_top:    int = SafeArea.top_reserved    if SafeArea else 0

	var floor_y:   float = room_height - WALL_T - float(sa_bottom)
	var ceiling_y: float = WALL_T + float(sa_top)

	_row_low  = floor_y - spacing
	_row_mid  = _row_low - spacing
	# Clamp: top row must leave room for PLAYER_HEIGHT + buffer below ceiling.
	_row_high = maxf(_row_mid - spacing, ceiling_y + 120.0)

	var platform_data: Array = []

	if is_vertical:
		# Fill all rows from floor to ceiling with uniform spacing, then run the
		# Markov layout so v_range below reflects which rows actually become
		# moving/typed platforms.
		_all_rows = _compute_all_rows(floor_y, ceiling_y, spacing)
		_vert_layout = _build_vertical_layout(_all_rows)
		# v_range comes from each row's resolved platform type, so moving_vertical
		# rows give missing_bridge_ys() the extra reach they actually provide.
		for entry in _vert_layout:
			var ptype: String = String(entry.get("type", "stone"))
			var vr: float = LevelGenerator.platform_v_range(ptype, MOVING_V_DISTANCE)
			platform_data.append({ "y": float(entry.get("y", 0.0)), "v_range": vr })
	else:
		# Horizontal room — three fixed rows with per-row v_range.
		var vr_low:  float = 0.0
		var vr_mid:  float = 0.0
		var vr_high: float = 0.0
		match room_index % 5:
			1, 3:
				vr_mid  = LevelGenerator.platform_v_range(_platform_type_hint, MOVING_V_DISTANCE)
			4:
				vr_high = LevelGenerator.platform_v_range(_platform_type_hint, MOVING_V_DISTANCE)
		platform_data = [
			{ "y": _row_low,  "v_range": vr_low  },
			{ "y": _row_mid,  "v_range": vr_mid  },
			{ "y": _row_high, "v_range": vr_high },
		]

	_bridge_rows = LevelGenerator.missing_bridge_ys(platform_data, floor_y)

func _compute_all_rows(floor_y: float, ceiling_y: float, spacing: float) -> Array:
	# Generate evenly-spaced row Y positions from the floor upward.
	# Stops before ceiling_y + PLAYER_HEIGHT + buffer (120 px).
	var rows: Array = []
	var y: float = floor_y - spacing
	var min_y: float = ceiling_y + 120.0
	while y >= min_y:
		rows.append(y)
		y -= spacing
	return rows

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
	var x_pos: float
	var y_pos: float
	if is_vertical and not _all_rows.is_empty():
		@warning_ignore("integer_division")
		var row_idx: int = _all_rows.size() / 5
		y_pos = float(_all_rows[row_idx]) - 60.0
		x_pos = _vert_platform_x(row_idx)
	else:
		x_pos = 140.0 + float((room_index * 73) % 320)
		y_pos = room_height - WALL_T - 40.0
	enemy.position = Vector2(x_pos, y_pos)
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
	if is_vertical and not _all_rows.is_empty():
		@warning_ignore("integer_division")
		var row_idx: int = _all_rows.size() * 7 / 10
		soul.position = Vector2(_vert_platform_x(row_idx), float(_all_rows[row_idx]) - 24.0)
	else:
		soul.position = Vector2(room_width * 0.5, _row_high - 24.0)
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
	if is_vertical and not _all_rows.is_empty():
		@warning_ignore("integer_division")
		var row_idx: int = _all_rows.size() / 2
		bonus.position = Vector2(_vert_platform_x(row_idx), float(_all_rows[row_idx]) - 40.0)
	else:
		bonus.position = Vector2(room_width * 0.5, _row_mid - 40.0)
	add_child(bonus)

# ── Altar spawning ────────────────────────────────────────────────────────────

const ALTAR_SCRIPT := preload("res://scripts/AltarNode.gd")

func _spawn_altar() -> void:
	var spawn_in_vertical_entrance := is_vertical and room_type == "entrance"
	var spawn_in_horizontal_exit   := not is_vertical and room_type == "exit"
	if not spawn_in_vertical_entrance and not spawn_in_horizontal_exit:
		return

	var altar := Node2D.new()
	altar.set_script(ALTAR_SCRIPT)
	altar.name = "AltarNode"
	altar.add_to_group("altar")

	if spawn_in_vertical_entrance:
		# Top of vertical level — place just above the topmost platform row.
		var sa_top_px: int = SafeArea.top_reserved if SafeArea else 0
		var altar_y: float = WALL_T + float(sa_top_px) + 140.0
		if not _all_rows.is_empty():
			altar_y = float(_all_rows.back()) - 32.0
		altar.position = Vector2(room_width * 0.5, altar_y)
	else:
		# Horizontal level — altar on the high-platform shelf in the exit room.
		altar.position = Vector2(room_width * 0.5, _row_high - 32.0)

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
	var needs_floor:   bool = not is_vertical or room_type == "exit"
	var needs_ceiling: bool = not is_vertical or room_type == "entrance"

	# Safe area: floor/ceiling walls are pushed inward so physics content
	# never appears under the OS notch or home-bar indicator.
	var sa_bottom: int = SafeArea.bottom_reserved if SafeArea else 0
	var sa_top:    int = SafeArea.top_reserved    if SafeArea else 0
	var sa_left:   int = SafeArea.left_reserved   if SafeArea else 0
	var sa_right:  int = SafeArea.right_reserved  if SafeArea else 0

	var floor_y:   float = room_height - WALL_T / 2.0 - float(sa_bottom)
	var ceiling_y: float = WALL_T / 2.0 + float(sa_top)
	# Side walls span the safe-area-adjusted height.
	var wall_h:    float = room_height - float(sa_top + sa_bottom)
	var wall_mid_y: float = float(sa_top) + wall_h / 2.0
	var side_t:    float = SIDE_WALL_T if is_vertical else WALL_T
	var wall_l_x:  float = side_t / 2.0 + float(sa_left)
	var wall_r_x:  float = room_width - side_t / 2.0 - float(sa_right)

	if needs_floor:
		_add_wall("Floor",   Vector2(room_width / 2.0, floor_y),   Vector2(room_width, WALL_T))
	if needs_ceiling:
		_add_wall("Ceiling", Vector2(room_width / 2.0, ceiling_y), Vector2(room_width, WALL_T))
	_add_wall("WallL", Vector2(wall_l_x, wall_mid_y), Vector2(side_t, wall_h))
	_add_wall("WallR", Vector2(wall_r_x, wall_mid_y), Vector2(side_t, wall_h))

	# Variant mid-platforms based on room_index so rooms differ visually.
	# Vertical rooms always use the full _all_rows distribution so the player
	# has platforms to land on across the whole 2-screen room height,
	# including the entrance (top) and exit (bottom) rooms.
	if is_vertical:
		_add_main_platforms()
		return
	match room_type:
		"main":
			_add_main_platforms()
		"entrance":
			_add_platform(Vector2(room_width / 2.0, _row_high), Vector2(280.0, PLATFORM_T))
			_add_platform(Vector2(room_width / 2.0, _row_mid),  Vector2(200.0, PLATFORM_T))
			_add_platform(Vector2(room_width / 2.0, _row_low),  Vector2(240.0, PLATFORM_T))
		"exit":
			_add_platform(Vector2(room_width * 0.30, _row_low),  Vector2(180.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.70, _row_low),  Vector2(180.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.50, _row_mid),  Vector2(220.0, PLATFORM_T))
			_add_platform(Vector2(room_width * 0.50, _row_high), Vector2(280.0, PLATFORM_T))

# Moving platform travel distances — single source of truth used by both
# _add_typed_platform() (behaviour) and _init_zone() (path validation).
const MOVING_V_DISTANCE: float = -80.0   # negative = upward; min_y = pos.y + MOVING_V_DISTANCE
const MOVING_H_DISTANCE: float = 140.0   # positive = rightward; Y unchanged

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
	var col_l: float = room_width * 0.22
	var col_c: float = room_width * 0.50
	var col_r: float = room_width * 0.78
	var shelf: Vector2 = Vector2(_platform_width, PLATFORM_T)
	var wide:  Vector2 = Vector2(_platform_width * 1.5, PLATFORM_T)

	# Bridge shelves: fill any gap > MAX_JUMP_HEIGHT, alternate columns.
	for i in _bridge_rows.size():
		var by: float = float(_bridge_rows[i])
		var offsets: Array = [0.22, 0.50, 0.78]
		_add_platform(Vector2(room_width * offsets[i % 3], by), Vector2(100.0, PLATFORM_T))

	if not _all_rows.is_empty():
		_add_vertical_main_platforms(col_l, col_c, col_r, shelf, wide)
		return

	# ── Horizontal room — 3-row layout ───────────────────────────────────────
	match room_index % 5:
		0:  # zigzag — mid-center one-way
			_add_platform(Vector2(col_l, _row_low),  shelf)
			_add_platform(Vector2(col_r, _row_low),  shelf)
			_add_typed_platform(Vector2(col_c, _row_mid), shelf, "one_way")
			_add_platform(Vector2(col_l, _row_high), shelf)
			_add_platform(Vector2(col_r, _row_high), shelf)
		1:  # zone-type special shelf mid row
			_add_platform(Vector2(col_l, _row_low),  shelf)
			_add_platform(Vector2(col_r, _row_low),  shelf)
			_add_typed_platform(Vector2(col_c, _row_mid), wide, _platform_type_hint)
			_add_platform(Vector2(col_c, _row_high), shelf)
		2:  # bounce pad bottom-left, static ladder right
			_add_typed_platform(Vector2(col_l, _row_low), shelf, "bounce")
			_add_platform(Vector2(col_r, _row_low),  shelf)
			_add_platform(Vector2(col_c, _row_mid),  shelf)
			_add_platform(Vector2(col_l, _row_high), shelf)
			_add_platform(Vector2(col_r, _row_high), shelf)
		3:  # zone-type mover mid row
			_add_platform(Vector2(col_l, _row_low),  shelf)
			_add_platform(Vector2(col_r, _row_low),  shelf)
			_add_typed_platform(Vector2(col_c, _row_mid), shelf, _platform_type_hint)
			_add_platform(Vector2(col_l, _row_high), shelf)
			_add_platform(Vector2(col_r, _row_high), shelf)
		4:  # zone-type mover high row
			_add_platform(Vector2(col_l, _row_low),  shelf)
			_add_platform(Vector2(col_r, _row_low),  shelf)
			_add_platform(Vector2(col_c, _row_mid),  shelf)
			_add_typed_platform(Vector2(col_c, _row_high), shelf, _platform_type_hint)
			_add_platform(Vector2(col_l, _row_high), shelf)
			_add_platform(Vector2(col_r, _row_high), shelf)

func _add_vertical_main_platforms(_col_l: float, _col_c: float, _col_r: float,
		_shelf: Vector2, _wide: Vector2) -> void:
	# Thin consumer: layout (with per-row width and type) is built in
	# _build_vertical_layout() during _init_zone() so v_range stays in sync.
	var bridge_left_x:  float = room_width * 0.20
	var bridge_right_x: float = room_width * 0.80
	for entry in _vert_layout:
		var pos := Vector2(float(entry.get("x", room_width * 0.5)),
				float(entry.get("y", 0.0)))
		var size := Vector2(float(entry.get("width", _platform_width)), PLATFORM_T)
		var ptype: String = String(entry.get("type", "stone"))
		match String(entry.get("kind", "single")):
			"single":
				if ptype == "stone":
					_add_platform(pos, size)
				else:
					_add_typed_platform(pos, size, ptype)
			"bridge":
				# Bridges are always safe stone footing — they exist to break the
				# "stacked single platforms" look, not to add danger.
				var bridge_size := Vector2(_platform_width, PLATFORM_T)
				_add_platform(Vector2(bridge_left_x,  pos.y), bridge_size)
				_add_platform(Vector2(bridge_right_x, pos.y), bridge_size)

# Section-based Markov layout generator for vertical rooms.
#
# Phase 1: pick a section sequence for the tier and map each row to a section.
#          Sections (rest / challenge / spike / breath) define width and type
#          weights so difficulty has a designed rhythm.
# Phase 2: per row, pick X via a Markov chain over horizontal zones (anti-3-
#          in-a-row), pick width/type from the active section's profile.
#
# Deterministic per (level_id, room_index): replay-safe.
func _build_vertical_layout(rows: Array) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash((level_id if level_id > 0 else 0) * 1000 + room_index)

	const ZONE_COUNT: int = 4
	# Zone center X relative to room_width — kept inside [0.18 .. 0.82] so even
	# wide platforms don't clip walls. Equally spaced by design.
	var zone_center: Array[float] = []
	for z in ZONE_COUNT:
		zone_center.append(0.18 + (0.82 - 0.18) * float(z) / float(ZONE_COUNT - 1))

	# Transition weights by |delta| between zones: stay, ±1, ±2, ±3.
	# Tuned so adjacent moves dominate but the path occasionally crosses the room.
	var weight_by_delta: Array[float] = [0.08, 0.40, 0.12, 0.04]

	var section_per_row: Array[String] = _assign_sections(rows.size(), rng)

	var layout: Array[Dictionary] = []
	var prev_zone: int = rng.randi() % ZONE_COUNT
	var prev_prev: int = -1
	var prev_kind: String = ""
	# Reachability state: anchor X and full width of the previous platform the
	# player would launch from (for bridges, the side closer to the next zone).
	var prev_x: float = -INF
	var prev_w: float = 0.0
	var prev_y: float = 0.0

	for i in rows.size():
		var section_name: String = section_per_row[i]
		var profile: Dictionary = SECTION_PROFILES[section_name]

		var zone: int = _markov_pick_zone(rng, prev_zone, prev_prev,
				ZONE_COUNT, weight_by_delta)

		# Y jitter within ±12% of one row gap so the grid doesn't read as such.
		# Skip first/last row so floor/ceiling alignment stays clean.
		var ry: float = float(rows[i])
		if i > 0 and i < rows.size() - 1:
			var gap: float = absf(float(rows[i]) - float(rows[i - 1]))
			ry += rng.randf_range(-gap * 0.12, gap * 0.12)

		var x: float = room_width * zone_center[zone]
		x += rng.randf_range(-room_width * 0.03, room_width * 0.03)

		# Bridge or single? Probability comes from the section profile.
		# Anti-repeat: never two bridges in a row (visually heavy).
		var bridge_chance: float = float(profile.get("bridge_chance", 0.0))
		var kind: String = "single"
		if rng.randf() < bridge_chance and prev_kind != "bridge":
			kind = "bridge"
			# Anchor X = side closer to the chosen zone (spawn helper hint).
			x = (room_width * 0.20) if zone * 2 < ZONE_COUNT else (room_width * 0.80)

		var width_mult: float = _sample_weighted(profile["widths"], rng)
		var width: float = _platform_width * width_mult
		var ptype: String = _sample_weighted_str(profile["types"], rng)
		if ptype == "_hint":
			ptype = _platform_type_hint

		# Reachability: snap X toward the previous platform if the jump from
		# its closest edge can't physically clear the gap. Without this, narrow
		# platforms in distant zones become unreachable on uphill rows.
		if prev_x != -INF and kind == "single":
			var v_gap: float = prev_y - ry  # > 0 means new row is higher
			var max_center_dx: float = _max_horizontal_jump(v_gap) \
					+ (prev_w + width) * 0.5
			var dx: float = x - prev_x
			if absf(dx) > max_center_dx:
				x = prev_x + signf(dx) * max_center_dx
				# Keep inside playable band so the snapped X never clips a wall.
				x = clampf(x, room_width * 0.10, room_width * 0.90)

		layout.append({
			"x": x, "y": ry, "kind": kind,
			"width": width, "type": ptype,
		})
		# For bridges, the player launches from one of the two shelves; use the
		# anchor side as the "previous" position.
		prev_x = x
		prev_w = width if kind == "single" else _platform_width
		prev_y = ry
		prev_prev = prev_zone
		prev_zone = zone
		prev_kind = kind

	return layout

# Build a per-row section assignment for a vertical room. The tier's section
# template is repeated/clipped to fill `row_count` rows, with each section's
# concrete length sampled inside its [length_min, length_max] range.
func _assign_sections(row_count: int, rng: RandomNumberGenerator) -> Array[String]:
	var template: Array = TIER_SECTIONS.get(_zone_tier, TIER_SECTIONS["medium"])
	var assignment: Array[String] = []
	assignment.resize(row_count)
	var idx: int = 0
	var step: int = 0
	while idx < row_count:
		var name: String = String(template[step % template.size()])
		var profile: Dictionary = SECTION_PROFILES[name]
		var length: int = rng.randi_range(int(profile["length_min"]),
				int(profile["length_max"]))
		for _k in length:
			if idx >= row_count:
				break
			assignment[idx] = name
			idx += 1
		step += 1
	return assignment

# Pick a numeric option from a [[value, weight], ...] table. Used for widths.
func _sample_weighted(table: Array, rng: RandomNumberGenerator) -> float:
	var total: float = 0.0
	for row in table:
		total += float(row[1])
	var pick: float = rng.randf() * total
	var acc: float = 0.0
	for row in table:
		acc += float(row[1])
		if pick <= acc:
			return float(row[0])
	return float(table[table.size() - 1][0])

# Pick a string option from a [[value, weight], ...] table. Used for types.
func _sample_weighted_str(table: Array, rng: RandomNumberGenerator) -> String:
	var total: float = 0.0
	for row in table:
		total += float(row[1])
	var pick: float = rng.randf() * total
	var acc: float = 0.0
	for row in table:
		acc += float(row[1])
		if pick <= acc:
			return String(row[0])
	return String(table[table.size() - 1][0])

# Max horizontal distance (in px) the player can travel mid-air while clearing
# a vertical rise of `v_gap` px. Derived from Player.gd physics:
#   jump_force=600, gravity=900, walk_speed=180.
# Apex time t_apex = 0.667s, max_jump_height ≈ 200 px.
# Same-level jump: full air ≈ 1.33s → ~240 px horizontal.
# Max upward jump: only apex time → ~120 px.
# Linear interp between the two with a 1.15× generosity factor (player can
# walk to the platform's edge before launching, which we approximate via
# +(prev_w + width)/2 in the caller).
func _max_horizontal_jump(v_gap: float) -> float:
	const SAME_LEVEL_REACH: float = 240.0
	const MAX_UP_REACH:     float = 120.0
	if v_gap <= 0.0:
		# Falling/level — full hang time, plus a margin since the player can
		# also delay-input the jump and pick up extra horizontal in the fall.
		return SAME_LEVEL_REACH * 1.15
	var max_up: float = LevelGenerator.MAX_JUMP_HEIGHT
	var t: float = clampf(v_gap / max_up, 0.0, 1.0)
	return lerpf(SAME_LEVEL_REACH, MAX_UP_REACH, t) * 1.15

func _markov_pick_zone(rng: RandomNumberGenerator, prev: int, prev_prev: int,
		zone_count: int, weight_by_delta: Array[float]) -> int:
	# Build candidate weights for this step. Skip the candidate that would form
	# three rows in a row in the same zone (prev == prev_prev == candidate).
	var weights: Array[float] = []
	weights.resize(zone_count)
	var total: float = 0.0
	for z in zone_count:
		var d: int = absi(z - prev)
		var w: float = 0.0
		if d < weight_by_delta.size():
			w = weight_by_delta[d]
		if z == prev and prev == prev_prev:
			w = 0.0  # anti-repeat veto
		weights[z] = w
		total += w
	if total <= 0.0:
		# All vetoed (unlikely): pick any neighbor.
		return clampi(prev + (1 if rng.randf() < 0.5 else -1), 0, zone_count - 1)
	var pick: float = rng.randf() * total
	var acc: float = 0.0
	for z in zone_count:
		acc += weights[z]
		if pick <= acc:
			return z
	return zone_count - 1

func _vert_platform_x(row_idx: int) -> float:
	if row_idx >= 0 and row_idx < _vert_layout.size():
		return float(_vert_layout[row_idx].get("x", room_width * 0.5))
	return room_width * 0.5

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
			body.set("distance",  MOVING_H_DISTANCE)
		"moving_vertical":
			body = AnimatableBody2D.new()
			body.set_script(MOVING_SCRIPT)
			body.set("move_axis", "vertical")
			body.set("distance",  MOVING_V_DISTANCE)
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

	var needs_floor:   bool = not is_vertical or room_type == "exit"
	var needs_ceiling: bool = not is_vertical or room_type == "entrance"
	var sa_bottom: int = SafeArea.bottom_reserved if SafeArea else 0
	var sa_top:    int = SafeArea.top_reserved    if SafeArea else 0
	var sa_left:   int = SafeArea.left_reserved   if SafeArea else 0
	var sa_right:  int = SafeArea.right_reserved  if SafeArea else 0

	if needs_floor:
		draw_rect(Rect2(0, room_height - WALL_T - sa_bottom, room_width, WALL_T), wall_c)
	if needs_ceiling:
		draw_rect(Rect2(0, sa_top, room_width, WALL_T), wall_c)
	var side_t: float = SIDE_WALL_T if is_vertical else WALL_T
	draw_rect(Rect2(sa_left, 0, side_t, room_height), wall_c)
	draw_rect(Rect2(room_width - side_t - sa_right, 0, side_t, room_height), wall_c)

	# Type badge
	var type_colors := {"entrance": Color(0.2, 0.8, 0.3), "main": Color(0.6, 0.6, 0.9), "exit": Color(1.0, 0.85, 0.2)}
	var badge_c: Color = type_colors.get(room_type, Color.WHITE)
	draw_rect(Rect2(WALL_T + 4, WALL_T + 4, 12, 12), badge_c)

	# Debug label
	var font := ThemeDB.fallback_font
	var label := "circle_%d / %s_%d  [%.0f×%.0f]" % [circle, room_type, room_index, room_width, room_height]
	draw_string(font, Vector2(WALL_T + 22, WALL_T + 16), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))
