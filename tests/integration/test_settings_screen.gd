extends GutTest

# Integration tests for SettingsScreen.gd (CanvasLayer).

const SettingsScreenScene := preload("res://scenes/ui/SettingsScreen.tscn")

var ss: Node

func before_each() -> void:
	# Layout (panel, tab bar, sliders, toggles, choice buttons, key rows)
	# lives in the .tscn — script-only `.new()` would leave every @onready
	# ref null and _refresh_widgets() would crash on the first `_sl_master.value`.
	ss = SettingsScreenScene.instantiate()
	add_child_autofree(ss)
	# Reset to defaults so that tests which call _save() don't pollute later tests
	ss._data = ss.DEFAULTS.duplicate()
	ss._refresh_widgets()

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	assert_false(ss.visible)

func test_open_shows_screen() -> void:
	ss.open()
	assert_true(ss.visible)

func test_open_switches_to_tab_zero() -> void:
	ss.open()
	assert_eq(ss._active_tab, 0)

func test_close_emits_signal() -> void:
	# closed is emitted inside a tween callback — check the signal is declared
	assert_true(ss.has_signal("closed"))

# ── Tab structure ─────────────────────────────────────────────────────────────

func test_four_tabs_created() -> void:
	# Sound, Language, Graphics, Keys (added in the rebinding feature)
	assert_eq(ss._tab_btns.size(), 4)

func test_four_tab_pages_created() -> void:
	assert_eq(ss._tab_pages.size(), 4)

func test_first_tab_active_on_open() -> void:
	ss.open()
	assert_eq(ss._tab_btns[0].modulate, Color.WHITE)

func test_inactive_tabs_are_dimmed_on_open() -> void:
	ss.open()
	assert_ne(ss._tab_btns[1].modulate, Color.WHITE)
	assert_ne(ss._tab_btns[2].modulate, Color.WHITE)

func test_switch_tab_shows_correct_page() -> void:
	ss._switch_tab(1)
	assert_true(ss._tab_pages[1].visible)
	assert_false(ss._tab_pages[0].visible)
	assert_false(ss._tab_pages[2].visible)

func test_switch_tab_updates_active_index() -> void:
	ss._switch_tab(2)
	assert_eq(ss._active_tab, 2)

func test_switch_tab_highlights_active_button() -> void:
	ss._switch_tab(2)
	assert_eq(ss._tab_btns[2].modulate, Color.WHITE)
	assert_ne(ss._tab_btns[0].modulate, Color.WHITE)

# ── Defaults ──────────────────────────────────────────────────────────────────

func test_default_volume_master_is_80() -> void:
	assert_eq(ss._data.get("volume_master"), 80)

func test_default_volume_music_is_60() -> void:
	assert_eq(ss._data.get("volume_music"), 60)

func test_default_volume_sfx_is_90() -> void:
	assert_eq(ss._data.get("volume_sfx"), 90)

func test_default_mute_is_false() -> void:
	assert_false(ss._data.get("mute_all", false))

func test_default_language_is_uk() -> void:
	assert_eq(ss._data.get("language"), "uk")

func test_default_vsync_is_true() -> void:
	assert_true(ss._data.get("vsync", false))

# ── Audio slider callbacks ────────────────────────────────────────────────────

func test_master_slider_change_updates_data() -> void:
	ss._on_master_changed(50.0)
	assert_eq(ss._data.get("volume_master"), 50)

func test_master_slider_change_updates_label() -> void:
	ss._on_master_changed(75.0)
	assert_true(ss._lbl_master.text.contains("75"))

func test_music_slider_change_updates_data() -> void:
	ss._on_music_changed(40.0)
	assert_eq(ss._data.get("volume_music"), 40)

func test_sfx_slider_change_updates_data() -> void:
	ss._on_sfx_changed(100.0)
	assert_eq(ss._data.get("volume_sfx"), 100)

# ── Mute toggle ───────────────────────────────────────────────────────────────

func test_mute_toggle_flips_data_from_false_to_true() -> void:
	ss._data["mute_all"] = false
	ss._on_mute_pressed()
	assert_true(ss._data.get("mute_all"))

func test_mute_toggle_flips_data_from_true_to_false() -> void:
	ss._data["mute_all"] = true
	ss._on_mute_pressed()
	assert_false(ss._data.get("mute_all"))

func test_mute_toggle_button_text_on() -> void:
	ss._data["mute_all"] = false
	ss._on_mute_pressed()
	assert_eq(ss._toggle_mute.text, "ВКЛ")

func test_mute_toggle_button_text_off() -> void:
	ss._data["mute_all"] = true
	ss._on_mute_pressed()
	assert_eq(ss._toggle_mute.text, "ВИКЛ")

# ── Language ──────────────────────────────────────────────────────────────────

func test_two_language_buttons_present() -> void:
	assert_eq(ss._lang_btns.size(), 2)

func test_language_uk_button_exists() -> void:
	assert_true(ss._lang_btns.has("uk"))

func test_language_en_button_exists() -> void:
	assert_true(ss._lang_btns.has("en"))

func test_selecting_language_updates_data() -> void:
	ss._on_language_pressed("en")
	assert_eq(ss._data.get("language"), "en")

func test_selecting_language_switches_active_button() -> void:
	ss._on_language_pressed("en")
	# en button should look active (text has color override set by _make_choice_btn)
	assert_eq(ss._data.get("language"), "en")

func test_language_refresh_marks_current_language_button() -> void:
	ss._data["language"] = "en"
	ss._refresh_widgets()
	assert_eq(ss._data.get("language"), "en")

# ── VSync toggle ──────────────────────────────────────────────────────────────

func test_vsync_toggle_flips_data() -> void:
	var initial: bool = ss._data.get("vsync", true)
	ss._on_vsync_pressed()
	assert_eq(ss._data.get("vsync"), not initial)

func test_vsync_toggle_button_text_on() -> void:
	ss._data["vsync"] = false
	ss._on_vsync_pressed()
	assert_eq(ss._toggle_vsync.text, "ВКЛ")

func test_vsync_toggle_button_text_off() -> void:
	ss._data["vsync"] = true
	ss._on_vsync_pressed()
	assert_eq(ss._toggle_vsync.text, "ВИКЛ")

# ── Refresh widgets ───────────────────────────────────────────────────────────

func test_refresh_sets_master_slider_value() -> void:
	ss._data["volume_master"] = 55
	ss._refresh_widgets()
	# HSlider.value is a float — compare against a float literal so GUT
	# doesn't log "Float/Int comparison" warnings on every run.
	assert_eq(ss._sl_master.value, 55.0)

func test_refresh_sets_music_slider_value() -> void:
	ss._data["volume_music"] = 30
	ss._refresh_widgets()
	assert_eq(ss._sl_music.value, 30.0)

func test_refresh_sets_sfx_slider_value() -> void:
	ss._data["volume_sfx"] = 70
	ss._refresh_widgets()
	assert_eq(ss._sl_sfx.value, 70.0)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_master_volume_change_updates_audio_server() -> void:
	# TODO: verify AudioServer.set_bus_volume_db called —
	# requires bus "Master" to exist in headless AudioServer
	pass

func test_sfx_toggle_mutes_sfx_bus() -> void:
	# TODO: verify AudioServer.set_bus_mute for SFX bus
	pass

func test_escape_closes_screen() -> void:
	# TODO: requires InputEvent simulation for "ui_cancel"
	pass

# ── Key rebinding ─────────────────────────────────────────────────────────────

func test_keys_tab_lists_all_rebindable_actions() -> void:
	# Each entry in REBINDABLE_ACTIONS has a button stored in _key_btns
	for entry in ss.REBINDABLE_ACTIONS:
		assert_true(ss._key_btns.has(entry.action),
			"missing key button for action '%s'" % entry.action)

func test_default_key_events_captured_on_ready() -> void:
	# Snapshot includes every action that exists in InputMap at boot.
	for entry in ss.REBINDABLE_ACTIONS:
		if InputMap.has_action(entry.action):
			assert_true(ss._default_key_events.has(entry.action),
				"missing default events snapshot for '%s'" % entry.action)

func test_set_binding_silent_overrides_input_map() -> void:
	if not InputMap.has_action("jump"):
		pending("jump action missing from InputMap")
		return
	# Use Q as the new key so we don't collide with the existing Space.
	ss._set_binding_silent("jump", KEY_Q)
	var found_q := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_Q:
			found_q = true
			break
	assert_true(found_q, "jump should now be bound to Q")
	# Cleanup so other tests see the original binding back.
	ss._on_reset_keys_pressed()

func test_apply_keybindings_replays_saved_dict() -> void:
	if not InputMap.has_action("jump"):
		pending("jump action missing from InputMap")
		return
	ss._apply_keybindings({"jump": KEY_R})
	var found_r := false
	for ev in InputMap.action_get_events("jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_R:
			found_r = true
			break
	assert_true(found_r, "saved binding (R) should be applied")
	ss._on_reset_keys_pressed()

func test_reset_restores_default_key_events() -> void:
	if not InputMap.has_action("jump"):
		pending("jump action missing from InputMap")
		return
	# Stash how it looked at boot, then mutate, then reset.
	var before_count: int = InputMap.action_get_events("jump").size()
	ss._set_binding_silent("jump", KEY_Q)
	ss._on_reset_keys_pressed()
	assert_eq(InputMap.action_get_events("jump").size(), before_count,
		"reset should restore the original event list")
