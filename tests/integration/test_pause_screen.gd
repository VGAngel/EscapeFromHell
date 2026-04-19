extends GutTest

# Integration tests for PauseScreen.gd (CanvasLayer).

var pause: Node

func before_each() -> void:
	# TODO: instantiate PauseScreen, build UI, add to scene
	pass

# ── Open / close ──────────────────────────────────────────────────────────────

func test_pause_screen_invisible_by_default() -> void:
	# TODO: assert pause.visible == false after _ready()
	pass

func test_open_makes_screen_visible() -> void:
	# TODO: call pause.open(), assert visible == true
	pass

func test_close_emits_signal() -> void:
	# TODO: watch "closed" signal, call close(), assert signal received
	pass

func test_close_pauses_game_tree() -> void:
	# TODO: call open(), assert get_tree().paused == true
	pass

func test_close_resumes_game_tree() -> void:
	# TODO: open then close, assert get_tree().paused == false
	pass

# ── Stats display ─────────────────────────────────────────────────────────────

func test_sin_displayed_on_open() -> void:
	# TODO: set SaveManager sin = 42.0, open screen,
	# assert sin label shows "42"
	pass

func test_hp_displayed_on_open() -> void:
	# TODO: set GameManager hp = 2, max_hp = 3, open,
	# assert hearts display 2/3
	pass

func test_souls_displayed_on_open() -> void:
	# TODO: add 5 souls to SaveManager, open, assert souls label shows 5
	pass

# ── Buttons ───────────────────────────────────────────────────────────────────

func test_resume_button_closes_screen() -> void:
	# TODO: call open(), simulate BtnResume press, assert visible == false
	pass

func test_restart_button_calls_game_manager() -> void:
	# TODO: simulate BtnRestart press, assert GameManager.restart_level() called
	pass

func test_main_menu_button_loads_menu() -> void:
	# TODO: simulate BtnMainMenu press, assert scene changed to MainMenu.tscn
	pass

# ── Input ─────────────────────────────────────────────────────────────────────

func test_escape_key_closes_screen() -> void:
	# TODO: open screen, simulate ui_cancel input, assert screen closes
	pass
