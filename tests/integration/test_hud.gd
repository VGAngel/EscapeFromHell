extends GutTest

# Integration tests for HUD.gd (CanvasLayer).
# HUD builds UI dynamically in _build_ui() called from _ready().

var hud: Node

func before_each() -> void:
	hud = preload("res://scripts/ui/HUD.gd").new()
	add_child_autofree(hud)
	if SaveManager:
		SaveManager._reset()

# ── _sin_color (pure lookup) ──────────────────────────────────────────────────

func test_sin_color_at_zero_is_white() -> void:
	assert_eq(hud._sin_color(0.0), Color("#FFFFFF"))

func test_sin_color_at_30_is_orange() -> void:
	assert_eq(hud._sin_color(30.0), Color("#FFAA00"))

func test_sin_color_at_60_is_red_orange() -> void:
	assert_eq(hud._sin_color(60.0), Color("#FF4400"))

func test_sin_color_at_85_is_dark_red() -> void:
	assert_eq(hud._sin_color(85.0), Color("#AA0000"))

func test_sin_color_at_100_is_dark_red() -> void:
	assert_eq(hud._sin_color(100.0), Color("#AA0000"))

func test_sin_color_threshold_50_is_orange() -> void:
	assert_eq(hud._sin_color(50.0), Color("#FFAA00"))

func test_sin_color_at_29_is_white() -> void:
	assert_eq(hud._sin_color(29.0), Color("#FFFFFF"))

# ── setup / hearts ────────────────────────────────────────────────────────────

func test_setup_fills_hp_hearts() -> void:
	hud.setup(1, 1, 3, 5)
	var children: Array = hud._hearts.get_children()
	for i in 3:
		assert_eq(children[i].text, "♥")

func test_setup_marks_empty_hearts_beyond_max_hp() -> void:
	hud.setup(1, 1, 3, 5)
	var children: Array = hud._hearts.get_children()
	for i in range(3, hud.MAX_HEARTS):
		assert_eq(children[i].text, "♡")

func test_setup_hides_hearts_beyond_max_hp() -> void:
	hud.setup(1, 1, 3, 5)
	var children: Array = hud._hearts.get_children()
	for i in range(3, hud.MAX_HEARTS):
		assert_false(children[i].visible)

func test_setup_sets_level_label() -> void:
	hud.setup(2, 15, 3, 5)
	assert_true(hud._level_label.text.contains("2"))
	assert_true(hud._level_label.text.contains("15"))

func test_setup_sets_souls_level_display() -> void:
	hud.setup(1, 1, 3, 5)
	assert_true(hud._souls_level.text.contains("0"))
	assert_true(hud._souls_level.text.contains("5"))

func test_setup_resets_souls_found_to_zero() -> void:
	hud.setup(1, 1, 3, 5)
	hud.add_soul_found()
	hud.setup(1, 2, 3, 5)
	assert_eq(hud._souls_found, 0)

# ── set_hp ────────────────────────────────────────────────────────────────────

func test_set_hp_2_of_3_shows_two_filled() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_hp(2, 3)
	var children: Array = hud._hearts.get_children()
	assert_eq(children[0].text, "♥")
	assert_eq(children[1].text, "♥")
	assert_eq(children[2].text, "♡")

func test_set_hp_zero_shows_all_empty() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_hp(0, 3)
	var children: Array = hud._hearts.get_children()
	for i in 3:
		assert_eq(children[i].text, "♡")

func test_set_hp_full_shows_all_filled() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_hp(0, 3)
	hud.set_hp(3, 3)
	var children: Array = hud._hearts.get_children()
	for i in 3:
		assert_eq(children[i].text, "♥")

# ── add_soul_found ────────────────────────────────────────────────────────────

func test_add_soul_found_increments_internal_counter() -> void:
	hud.setup(1, 1, 3, 5)
	hud.add_soul_found()
	assert_eq(hud._souls_found, 1)

func test_add_soul_found_twice_shows_2_in_label() -> void:
	hud.setup(1, 1, 3, 5)
	hud.add_soul_found()
	hud.add_soul_found()
	assert_true(hud._souls_level.text.contains("2"))

# ── set_total_souls ───────────────────────────────────────────────────────────

func test_set_total_souls_updates_label() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_total_souls(42)
	assert_true(hud._souls_total.text.contains("42"))

# ── set_sin / sin bar ─────────────────────────────────────────────────────────

func test_set_sin_updates_internal_value() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_sin(55.0)
	assert_eq(hud._sin, 55.0)

func test_set_sin_bar_width_proportional_to_value() -> void:
	hud.setup(1, 1, 3, 5)
	var bg_w: float = hud._sin_bar_bg.size.x
	hud.set_sin(50.0)
	assert_almost_eq(hud._sin_bar.size.x, bg_w * 0.5, 0.01)

func test_set_sin_zero_bar_width_zero() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_sin(0.0)
	assert_almost_eq(hud._sin_bar.size.x, 0.0, 0.01)

func test_set_sin_100_fills_bar_completely() -> void:
	hud.setup(1, 1, 3, 5)
	var bg_w: float = hud._sin_bar_bg.size.x
	hud.set_sin(100.0)
	assert_almost_eq(hud._sin_bar.size.x, bg_w, 0.01)

func test_set_sin_updates_bar_color() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_sin(90.0)
	assert_eq(hud._sin_bar.color, Color("#AA0000"))

func test_set_sin_clamps_above_100() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_sin(150.0)
	assert_eq(hud._sin, 100.0)

func test_set_sin_clamps_below_zero() -> void:
	hud.setup(1, 1, 3, 5)
	hud.set_sin(-10.0)
	assert_eq(hud._sin, 0.0)

# ── start_bonus ───────────────────────────────────────────────────────────────

func test_start_bonus_adds_entry() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_bonus("prayer", "🙏", 5.0)
	assert_true(hud._active_bonuses.has("prayer"))

func test_start_bonus_creates_node_in_bonus_row() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_bonus("prayer", "🙏", 5.0)
	assert_eq(hud._bonus_row.get_child_count(), 1)

func test_start_bonus_same_id_refreshes_timer_not_duplicates() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_bonus("prayer", "🙏", 5.0)
	hud.start_bonus("prayer", "🙏", 10.0)
	assert_eq(hud._active_bonuses["prayer"]["time_left"], 10.0)
	assert_eq(hud._bonus_row.get_child_count(), 1)

func test_start_two_different_bonuses() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_bonus("prayer", "🙏", 5.0)
	hud.start_bonus("shield", "🛡", 3.0)
	assert_eq(hud._active_bonuses.size(), 2)

# ── escape timer ──────────────────────────────────────────────────────────────

func test_start_escape_timer_sets_active_flag() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_escape_timer(60.0)
	assert_true(hud._escape_active)

func test_start_escape_timer_shows_bar() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_escape_timer(60.0)
	assert_true(hud._escape_bg.visible)
	assert_true(hud._escape_bar.visible)

func test_stop_escape_timer_clears_active_flag() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_escape_timer(60.0)
	hud.stop_escape_timer()
	assert_false(hud._escape_active)

func test_stop_escape_timer_hides_bar() -> void:
	hud.setup(1, 1, 3, 5)
	hud.start_escape_timer(60.0)
	hud.stop_escape_timer()
	assert_false(hud._escape_bg.visible)
	assert_false(hud._escape_bar.visible)

func test_escape_bar_hidden_by_default() -> void:
	assert_false(hud._escape_bg.visible)
	assert_false(hud._escape_bar.visible)

# ── TODO (async / process) ────────────────────────────────────────────────────

func test_sin_bar_pulses_above_85_percent() -> void:
	# TODO: requires process frame simulation — _sin_pulse_timer increments in _process
	pass

func test_sin_white_flash_at_first_crossing_85() -> void:
	# TODO: async tween — _set_sin creates tween on 85 threshold crossing
	pass

func test_set_hp_zero_flashes_screen_red() -> void:
	# TODO: async — _flash_screen creates a temporary ColorRect via tween
	pass

func test_escape_timer_decrements_over_time() -> void:
	# TODO: requires process frame simulation with delta
	pass

func test_bonus_icon_removed_after_duration() -> void:
	# TODO: requires process frame simulation
	pass
