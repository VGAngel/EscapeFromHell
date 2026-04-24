extends GutTest

# Smoke tests — coarse "does the game even boot" checks.
#
# Runs first in CI: if any of these fail, finer integration tests are
# almost certainly going to fail too, but their messages would be noise.
# Smoke tests should stay cheap (< 1 sec total) and depend on autoloads
# already being available (GUT runs inside the project, so they are).
#
# Add a check here whenever a regression breaks the whole game (rather
# than one feature) — e.g. missing autoload, broken scene reference,
# corrupted config.

const PlayerScript     := preload("res://scripts/Player.gd")
const PlaceholderRoom  := preload("res://scripts/rooms/PlaceholderRoom.gd")
const LevelBaseScript  := preload("res://scripts/levels/LevelBase.gd")

# ── Autoloads exist ───────────────────────────────────────────────────────────

func test_autoload_game_manager_present() -> void:
	assert_not_null(GameManager,            "GameManager autoload missing")

func test_autoload_save_manager_present() -> void:
	assert_not_null(SaveManager,            "SaveManager autoload missing")

func test_autoload_level_config_present() -> void:
	assert_not_null(LevelConfig,            "LevelConfig autoload missing")

func test_autoload_level_generator_present() -> void:
	assert_not_null(LevelGenerator,         "LevelGenerator autoload missing")

func test_autoload_safe_area_present() -> void:
	assert_not_null(SafeArea,               "SafeArea autoload missing")

func test_autoload_debug_overlay_present() -> void:
	assert_not_null(DebugOverlay,           "DebugOverlay autoload missing")

func test_autoload_localization_present() -> void:
	assert_not_null(Loc,                    "Loc (LocalizationManager) autoload missing")

# ── Critical scripts compile ──────────────────────────────────────────────────

func test_player_script_loads() -> void:
	assert_not_null(PlayerScript,           "Player.gd failed to preload (parse error?)")

func test_placeholder_room_script_loads() -> void:
	assert_not_null(PlaceholderRoom,        "PlaceholderRoom.gd failed to preload")

func test_level_base_script_loads() -> void:
	assert_not_null(LevelBaseScript,        "LevelBase.gd failed to preload")

# ── Critical scenes exist on disk ─────────────────────────────────────────────

func test_player_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/Player.tscn"),
		"Player.tscn missing — game can't spawn the protagonist")

func test_level_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/levels/Level.tscn"),
		"Level.tscn missing — generic level container is gone")

func test_main_menu_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/ui/MainMenu.tscn"),
		"MainMenu.tscn missing — game has no entry point")

func test_hub_scene_exists() -> void:
	assert_true(ResourceLoader.exists("res://scenes/Hub.tscn"),
		"Hub.tscn missing — between-levels screen is gone")

# ── Config files load ─────────────────────────────────────────────────────────

func test_levels_config_json_loads() -> void:
	var f := FileAccess.open("res://levels_config.json", FileAccess.READ)
	assert_not_null(f, "levels_config.json missing or unreadable")
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		assert_not_null(parsed, "levels_config.json is malformed JSON")
		assert_true(parsed.has("circle_defaults"), "levels_config.json missing circle_defaults")
		assert_true(parsed.has("levels"),          "levels_config.json missing levels array")

func test_bosses_config_json_loads() -> void:
	var f := FileAccess.open("res://bosses_config.json", FileAccess.READ)
	assert_not_null(f, "bosses_config.json missing")
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		assert_not_null(parsed, "bosses_config.json is malformed JSON")

# ── End-to-end: generator can produce a valid level ───────────────────────────

func test_level_generator_produces_level_1() -> void:
	# If LevelGenerator.generate() crashes for level 1, the whole game is
	# unstartable — this single check catches a huge class of regressions.
	var gen = LevelGenerator.generate(1)
	assert_not_null(gen,                          "LevelGenerator.generate(1) returned null")
	assert_eq(int(gen.level_id), 1,                "level_id mismatch")
	assert_eq(int(gen.circle), 1,                  "circle mismatch")
	assert_gt(int(gen.room_count), 0,              "room_count must be > 0")
	assert_ne(String(gen.difficulty_zone), "",     "difficulty_zone must be set")

func test_level_generator_produces_each_circle_opener() -> void:
	# Every circle opener (1, 11, 21 … 91) must generate without crashing.
	# Catches per-circle config drift (missing room scenes, broken pools).
	for circle in range(1, 11):
		var level_id: int = (circle - 1) * 10 + 1
		var gen = LevelGenerator.generate(level_id)
		assert_not_null(gen, "generate(%d) returned null for circle %d" % [level_id, circle])
		assert_eq(int(gen.circle), circle, "level %d expected circle %d" % [level_id, circle])

# ── Per-circle tileset config covers every circle ─────────────────────────────

func test_every_circle_has_tileset_config() -> void:
	# get_circle_tileset must return a non-empty value for every real circle
	# (1-10) — otherwise the shaft renders with the wrong art set.
	for circle in range(1, 11):
		var tileset: String = LevelConfig.get_circle_tileset(circle)
		assert_ne(tileset, "",
			"circle %d has empty tileset — check levels_config.json" % circle)
