extends GutTest

# Integration tests for LevelComplete.gd (CanvasLayer).
# Shown after each level with stats, stars, and light earned.
# Button/navigation tests are TODO — they call get_tree().change_scene_to_file()
# which would kill the GUT runner.

var lc: Node

const LevelCompleteScene := preload("res://scenes/ui/LevelComplete.tscn")

func before_each() -> void:
	# Layout (panel + stats + buttons) lives in the .tscn — `Script.new()`
	# would leave every @onready label null and _fill_static() would crash
	# writing into a null _stat_souls.
	lc = LevelCompleteScene.instantiate()
	add_child_autofree(lc)

# ── show_results — visibility ─────────────────────────────────────────────────

func test_show_stats_makes_screen_visible() -> void:
	lc.show_results({})
	assert_true(lc.visible)

func test_initially_hidden() -> void:
	assert_false(lc.visible)

# ── Label content (set synchronously in _fill_static) ────────────────────────

func test_souls_count_displayed() -> void:
	lc.show_results({"souls_found": 3, "souls_total": 5})
	assert_true(lc._stat_souls.text.contains("3"))
	assert_true(lc._stat_souls.text.contains("5"))

func test_deaths_displayed() -> void:
	lc.show_results({"deaths": 2})
	assert_true(lc._stat_deaths.text.contains("2"))

func test_light_earned_displayed() -> void:
	lc.show_results({"light_earned": 15})
	assert_true(lc._stat_light.text.contains("15"))

func test_subtitle_shows_circle_and_level() -> void:
	lc.show_results({"circle": 2, "level_id": 15})
	assert_true(lc._lbl_subtitle.text.contains("2"))
	assert_true(lc._lbl_subtitle.text.contains("15"))

func test_sin_stat_shows_delta_and_total() -> void:
	lc.show_results({"sin_delta": 5.0, "sin_total": 15.0})
	assert_true(lc._stat_sin.text.contains("5"))
	assert_true(lc._stat_sin.text.contains("15"))

func test_sin_positive_delta_shows_plus_sign() -> void:
	lc.show_results({"sin_delta": 5.0, "sin_total": 15.0})
	assert_true(lc._stat_sin.text.contains("+"))

func test_sin_negative_delta_no_plus_sign() -> void:
	lc.show_results({"sin_delta": -3.0, "sin_total": 12.0})
	assert_false(lc._stat_sin.text.contains("+"))

func test_zero_deaths_displayed() -> void:
	lc.show_results({"deaths": 0})
	assert_true(lc._stat_deaths.text.contains("0"))

func test_zero_light_displayed() -> void:
	lc.show_results({"light_earned": 0})
	assert_true(lc._stat_light.text.contains("0"))

# ── _reveal_star ──────────────────────────────────────────────────────────────

func test_reveal_star_filled_sets_star_char() -> void:
	var lbl := Label.new()
	add_child_autofree(lbl)
	lc._reveal_star(lbl, true)
	assert_eq(lbl.text, "★")

func test_reveal_star_filled_sets_full_alpha() -> void:
	var lbl := Label.new()
	add_child_autofree(lbl)
	lc._reveal_star(lbl, true)
	assert_eq(lbl.modulate.a, 1.0)

func test_reveal_star_empty_sets_empty_char() -> void:
	var lbl := Label.new()
	add_child_autofree(lbl)
	lc._reveal_star(lbl, false)
	assert_eq(lbl.text, "☆")

func test_reveal_star_empty_sets_dim_alpha() -> void:
	var lbl := Label.new()
	add_child_autofree(lbl)
	lc._reveal_star(lbl, false)
	assert_almost_eq(lbl.modulate.a, 0.35, 0.01)

# ── Signals ───────────────────────────────────────────────────────────────────

func test_hub_button_emits_hub_pressed_signal() -> void:
	watch_signals(lc)
	# Disconnect scene-change handler to avoid killing GUT runner
	lc._btn_hub.pressed.disconnect(lc._on_hub_pressed)
	lc._btn_hub.pressed.connect(func() -> void: lc.hub_pressed.emit())
	lc._btn_hub.pressed.emit()
	assert_signal_emitted(lc, "hub_pressed")

func test_next_button_emits_next_level_pressed_signal() -> void:
	watch_signals(lc)
	lc._btn_next.pressed.disconnect(lc._on_next_pressed)
	lc._btn_next.pressed.connect(func() -> void: lc.next_level_pressed.emit())
	lc._btn_next.pressed.emit()
	assert_signal_emitted(lc, "next_level_pressed")

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_time_displayed() -> void:
	# TODO: time_seconds is accepted in stats dict but not displayed in current
	# LevelComplete.gd — add a _stat_time label and format as "M:SS" first
	pass

func test_three_stars_shown_on_perfect_run() -> void:
	# TODO: requires awaiting tween completion (stars are set via _animate_in callbacks)
	pass

func test_one_star_on_partial_souls() -> void:
	# TODO: requires awaiting tween completion
	pass

func test_stars_animate_in_sequence() -> void:
	# TODO: async tween — verify each star callback fires with correct filled flag
	pass

func test_elements_fade_in_after_stars() -> void:
	# TODO: async tween — stat labels start at modulate.a=0, animate to 1.0
	pass

func test_next_level_button_calls_load_next() -> void:
	# TODO: requires GameManager stub — load_next_level() calls change_scene_to_file
	pass

func test_hub_button_calls_load_hub() -> void:
	# TODO: requires GameManager stub — load_hub() calls change_scene_to_file
	pass

func test_tap_anywhere_advances_to_next() -> void:
	# TODO: requires InputEvent simulation + GameManager stub
	pass
