extends GutTest

# Integration tests for LevelComplete.gd (CanvasLayer).
# Shown after each level with stats, stars, and light earned.

var lc: Node

func before_each() -> void:
	# TODO: instantiate LevelComplete, build UI, add to scene
	pass

# ── show_stats ────────────────────────────────────────────────────────────────

func test_show_stats_makes_screen_visible() -> void:
	# TODO: call lc.show_stats({...stats dict...}), assert visible == true
	pass

func test_three_stars_shown_on_perfect_run() -> void:
	# TODO: pass stats with stars=3, assert all 3 star labels at full alpha
	pass

func test_one_star_on_partial_souls() -> void:
	# TODO: pass stats with stars=1, assert only 1 star at full alpha
	pass

func test_light_earned_displayed() -> void:
	# TODO: pass stats with light_earned=15, assert light label shows "15"
	pass

func test_souls_count_displayed() -> void:
	# TODO: pass stats with souls_found=3, souls_total=5,
	# assert souls label shows "3 / 5"
	pass

func test_deaths_displayed() -> void:
	# TODO: pass stats with deaths=2, assert deaths label shows "2"
	pass

func test_time_displayed() -> void:
	# TODO: pass stats with time_seconds=92.0, assert "1:32" formatted time
	pass

# ── Animations ────────────────────────────────────────────────────────────────

func test_stars_animate_in_sequence() -> void:
	# TODO: call show_stats with 3 stars, verify each star fades in with delay
	pass

func test_elements_fade_in_after_stars() -> void:
	# TODO: after star animation completes, assert stats nodes become visible
	pass

# ── Buttons ───────────────────────────────────────────────────────────────────

func test_next_level_button_calls_load_next() -> void:
	# TODO: simulate BtnNext press, assert GameManager.load_next_level() called
	pass

func test_hub_button_calls_load_hub() -> void:
	# TODO: simulate BtnHub press, assert GameManager.load_hub() called
	pass

# ── Input ─────────────────────────────────────────────────────────────────────

func test_tap_anywhere_advances_to_next() -> void:
	# TODO: simulate screen tap / ui_accept, assert next level loads
	pass
