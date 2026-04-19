extends GutTest

# Integration tests for PauseScreen.gd (CanvasLayer).

var ps: Node

func before_each() -> void:
	ps = preload("res://scripts/ui/PauseScreen.gd").new()
	add_child_autofree(ps)
	if SaveManager:
		SaveManager._reset()

func after_each() -> void:
	get_tree().paused = false  # ensure tree isn't left paused by a failing test

# ── Open / close ──────────────────────────────────────────────────────────────

func test_pause_screen_invisible_by_default() -> void:
	assert_false(ps.visible)

func test_open_makes_screen_visible() -> void:
	ps.open()
	assert_true(ps.visible)

func test_open_pauses_game_tree() -> void:
	ps.open()
	assert_true(get_tree().paused)

func test_close_resumes_game_tree() -> void:
	ps.open()
	ps.close()
	assert_false(get_tree().paused)

func test_close_emits_resumed_signal() -> void:
	watch_signals(ps)
	ps.open()
	ps.close()
	assert_signal_emitted(ps, "resumed")

func test_open_twice_is_idempotent() -> void:
	ps.open()
	ps.open()
	assert_true(ps._visible_flag)

func test_close_when_not_open_does_not_crash() -> void:
	ps.close()
	assert_false(get_tree().paused)

func test_toggle_opens_when_closed() -> void:
	ps.toggle()
	assert_true(ps._visible_flag)

func test_toggle_closes_when_open() -> void:
	ps.open()
	ps.toggle()
	assert_false(ps._visible_flag)

# ── Stats ─────────────────────────────────────────────────────────────────────

func test_sin_displayed_on_open() -> void:
	SaveManager.set_sin(42.0)
	ps.open()
	assert_true(ps._lbl_sin_pct.text.contains("42"))

func test_sin_zero_displayed_on_open() -> void:
	SaveManager.set_sin(0.0)
	ps.open()
	assert_true(ps._lbl_sin_pct.text.contains("0"))

func test_souls_displayed_on_open() -> void:
	for i in 5:
		SaveManager.add_soul(i)
	ps.open()
	assert_true(ps._lbl_souls.text.contains("5"))

func test_level_label_not_empty_on_open() -> void:
	ps.open()
	assert_true(ps._lbl_level.text.length() > 0)

# ── _sin_color ────────────────────────────────────────────────────────────────

func test_sin_color_at_0_is_white() -> void:
	assert_eq(ps._sin_color(0.0), Color("#FFFFFF"))

func test_sin_color_at_30_is_orange() -> void:
	assert_eq(ps._sin_color(30.0), Color("#FFAA00"))

func test_sin_color_at_60_is_red_orange() -> void:
	assert_eq(ps._sin_color(60.0), Color("#FF4400"))

func test_sin_color_at_85_is_dark_red() -> void:
	assert_eq(ps._sin_color(85.0), Color("#AA0000"))

func test_sin_color_at_29_is_white() -> void:
	assert_eq(ps._sin_color(29.0), Color("#FFFFFF"))

# ── _set_sin ──────────────────────────────────────────────────────────────────

func test_set_sin_bar_width_at_50_percent() -> void:
	ps._set_sin(50.0)
	assert_almost_eq(ps._sin_bar.size.x, 60.0, 0.01)

func test_set_sin_bar_width_at_zero() -> void:
	ps._set_sin(0.0)
	assert_almost_eq(ps._sin_bar.size.x, 0.0, 0.01)

func test_set_sin_bar_width_at_full() -> void:
	ps._set_sin(100.0)
	assert_almost_eq(ps._sin_bar.size.x, 120.0, 0.01)

func test_set_sin_updates_pct_label() -> void:
	ps._set_sin(75.0)
	assert_true(ps._lbl_sin_pct.text.contains("75"))

# ── Buttons ───────────────────────────────────────────────────────────────────

func test_resume_button_clears_visible_flag() -> void:
	ps.open()
	ps._btn_resume.pressed.emit()
	assert_false(ps._visible_flag)

func test_collection_button_emits_collection_requested() -> void:
	watch_signals(ps)
	ps._btn_collection.pressed.emit()
	assert_signal_emitted(ps, "collection_requested")

func test_settings_button_emits_settings_requested() -> void:
	watch_signals(ps)
	ps._btn_settings.pressed.emit()
	assert_signal_emitted(ps, "settings_requested")

func test_menu_button_shows_confirm_panel() -> void:
	ps.open()
	ps._btn_menu.pressed.emit()
	assert_true(ps._confirm_panel.visible)

func test_confirm_no_hides_confirm_panel() -> void:
	ps.open()
	ps._btn_menu.pressed.emit()
	ps._btn_exit_no.pressed.emit()
	assert_false(ps._confirm_panel.visible)

func test_open_hides_confirm_panel() -> void:
	# Confirm panel should be hidden every time screen opens
	ps.open()
	ps._btn_menu.pressed.emit()
	ps.close()
	ps.open()
	assert_false(ps._confirm_panel.visible)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_hp_displayed_on_open() -> void:
	# PauseScreen shows circle/level + souls + sin — no HP display.
	# Stub was based on incorrect assumption; nothing to test here.
	pass

func test_restart_button_calls_game_manager() -> void:
	# PauseScreen has no restart button — only resume/collection/settings/menu.
	pass

func test_main_menu_button_loads_menu() -> void:
	# TODO: _on_exit_yes_pressed calls GameManager.load_main_menu() → scene change
	pass

func test_escape_key_closes_screen() -> void:
	# TODO: requires creating and injecting a real InputEventAction for "ui_cancel"
	pass
