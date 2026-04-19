extends GutTest

# Integration tests for HUD.gd (CanvasLayer).
# HUD builds its UI dynamically in _build_ui() — requires scene tree.

var hud: Node

func before_each() -> void:
	# TODO: instantiate HUD, call setup(), wait one frame for UI to build
	# hud = preload("res://scripts/HUD.gd").new()
	# add_child_autofree(hud)
	# await get_tree().process_frame
	pass

# ── _sin_color (pure lookup) ──────────────────────────────────────────────────

func test_sin_color_at_zero_is_white_ish() -> void:
	# TODO: instantiate bare HUD node, call _sin_color(0.0),
	# assert returned Color matches SIN_COLORS[0]
	pass

func test_sin_color_at_100_is_red() -> void:
	# TODO: call _sin_color(100.0), assert bright red color returned
	pass

func test_sin_color_threshold_50() -> void:
	# TODO: assert _sin_color(50.0) matches the color at the 50% threshold
	pass

# ── setup / HP display ────────────────────────────────────────────────────────

func test_setup_creates_correct_heart_count() -> void:
	# TODO: call hud.setup(1, 1, 3, 5), assert 3 heart nodes created
	pass

func test_set_hp_updates_hearts_visually() -> void:
	# TODO: call hud.set_hp(2, 3), assert one heart is dimmed
	pass

func test_set_hp_zero_flashes_screen_red() -> void:
	# TODO: call hud.set_hp(0, 3), assert damage flash was triggered
	pass

# ── Sin bar ───────────────────────────────────────────────────────────────────

func test_set_sin_updates_bar_width() -> void:
	# TODO: call hud.set_sin(50.0), assert sin bar width == viewport_width * 0.5
	pass

func test_sin_bar_pulses_above_85_percent() -> void:
	# TODO: call hud.set_sin(90.0), process frames, assert _sin_bar.modulate.a oscillates
	pass

func test_sin_white_flash_at_first_crossing_85() -> void:
	# TODO: set sin below 85, then above, assert white flash overlay created
	pass

# ── Soul counter ──────────────────────────────────────────────────────────────

func test_add_soul_found_increments_display() -> void:
	# TODO: call hud.add_soul_found() twice, assert counter shows 2
	pass

func test_set_total_souls_updates_display() -> void:
	# TODO: call hud.set_total_souls(42), assert total souls label shows 42
	pass

# ── Bonus icons ───────────────────────────────────────────────────────────────

func test_start_bonus_creates_icon() -> void:
	# TODO: call hud.start_bonus("prayer", "🙏", 5.0),
	# assert icon node added to bonus bar
	pass

func test_bonus_icon_removed_after_duration() -> void:
	# TODO: start bonus with duration 0.1s, wait, assert icon removed
	pass

# ── Escape timer ──────────────────────────────────────────────────────────────

func test_start_escape_timer_shows_timer() -> void:
	# TODO: call hud.start_escape_timer(60.0),
	# assert escape timer control becomes visible
	pass

func test_escape_timer_decrements_over_time() -> void:
	# TODO: start timer, wait 1 second, assert displayed time decreased
	pass
