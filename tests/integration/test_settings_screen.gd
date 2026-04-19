extends GutTest

# Integration tests for SettingsScreen.gd (CanvasLayer).

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	# TODO: instantiate SettingsScreen, assert visible == false
	pass

func test_open_shows_screen() -> void:
	# TODO: call open(), assert visible == true
	pass

func test_close_emits_signal() -> void:
	# TODO: watch "closed", close(), assert received
	pass

# ── Tabs ──────────────────────────────────────────────────────────────────────

func test_first_tab_active_on_open() -> void:
	# TODO: open, assert first tab button modulate == Color.WHITE
	pass

func test_switching_tabs_shows_correct_content() -> void:
	# TODO: tap tab 1 (e.g. Audio), assert audio settings container visible
	pass

# ── Audio settings ────────────────────────────────────────────────────────────

func test_master_volume_slider_reflects_saved_value() -> void:
	# TODO: set SaveManager flag "audio_master" = 0.5, open,
	# assert slider value == 0.5
	pass

func test_master_volume_change_updates_audio_server() -> void:
	# TODO: drag slider to 0.0, assert AudioServer.set_bus_volume_db called
	pass

func test_sfx_toggle_mutes_sfx_bus() -> void:
	# TODO: toggle SFX off, assert SFX bus muted
	pass

# ── Language settings ─────────────────────────────────────────────────────────

func test_language_buttons_present() -> void:
	# TODO: open Language tab, assert at least 2 language buttons exist
	pass

func test_selecting_language_updates_translation() -> void:
	# TODO: press "EN" button, assert TranslationServer.set_locale("en") called
	pass

# ── Input ─────────────────────────────────────────────────────────────────────

func test_escape_closes_screen() -> void:
	# TODO: open, simulate ui_cancel, assert closed
	pass
