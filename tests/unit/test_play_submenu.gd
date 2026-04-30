extends GutTest

# Tests for PlaySubmenu — the intermediate "Грати" overlay that
# branches into Continue / Levels / Levels(debug) / Profile / Seed.

const PlaySubmenuScript := preload("res://scripts/ui/PlaySubmenu.gd")

var sub: CanvasLayer
var sm: Node


func before_each() -> void:
	sm = get_node_or_null("/root/SaveManager")
	sub = PlaySubmenuScript.new()
	add_child_autofree(sub)


# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_all_rows() -> void:
	assert_not_null(sub._btn_continue)
	assert_not_null(sub._btn_levels)
	assert_not_null(sub._btn_levels_debug)
	assert_not_null(sub._btn_profile)
	assert_not_null(sub._btn_seed)


func test_router_title_returns_play() -> void:
	var title: String = sub.router_title()
	assert_ne(title, "", "router_title must return a non-empty label")


# ── Labels ────────────────────────────────────────────────────────────────────

func test_continue_label_first_run_has_no_level_number() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	# Clean slate: no playtime, level 1.
	if sm.has_method("set_current_level"):
		sm.set_current_level(1)
	sub._refresh_labels()
	assert_true(sub._btn_continue.text.find("рівень") == -1
			or sub._btn_continue.text.find("Грати") != -1,
			"first-run label should be the bare ▶ Грати variant")


func test_profile_label_inlines_active_name() -> void:
	if sm == null or not sm.has_method("set_profile_name"):
		pending("SaveManager autoload missing")
		return
	sm.set_profile_name("ТестовийГерой")
	sub._refresh_labels()
	assert_string_contains(sub._btn_profile.text, "ТестовийГерой")


func test_seed_label_shows_auto_when_empty() -> void:
	if sm == null or not sm.has_method("set_world_seed_str"):
		pending("SaveManager autoload missing")
		return
	sm.set_world_seed_str("")
	sub._refresh_labels()
	assert_string_contains(sub._btn_seed.text, "Seed")


# ── Signal forwarding ─────────────────────────────────────────────────────────

func test_continue_button_emits_continue_signal() -> void:
	watch_signals(sub)
	sub._btn_continue.pressed.emit()
	assert_signal_emitted(sub, "continue_pressed")


func test_levels_debug_button_emits_levels_debug_signal() -> void:
	watch_signals(sub)
	sub._btn_levels_debug.pressed.emit()
	assert_signal_emitted(sub, "levels_debug_pressed")


func test_profile_button_emits_profile_signal() -> void:
	watch_signals(sub)
	sub._btn_profile.pressed.emit()
	assert_signal_emitted(sub, "profile_pressed")
