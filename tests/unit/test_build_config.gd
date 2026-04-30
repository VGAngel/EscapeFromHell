extends GutTest

# Tests for BuildConfig — the debug/release gate that controls
# whether dev-only UI surfaces (Levels(debug), Seed row, DebugOverlay)
# render in the build.

const BuildConfigScript := preload("res://scripts/managers/BuildConfig.gd")
const PlaySubmenuScript := preload("res://scripts/ui/PlaySubmenu.gd")

var bc: Node


func before_each() -> void:
	bc = get_node_or_null("/root/BuildConfig")
	if bc and bc.has_method("clear_override"):
		bc.clear_override()


func after_each() -> void:
	if bc and bc.has_method("clear_override"):
		bc.clear_override()


# ── Autoload presence ─────────────────────────────────────────────────────────

func test_autoload_registered() -> void:
	assert_not_null(bc, "BuildConfig must be registered as an autoload")
	assert_true(bc.has_method("show_debug_ui"))
	assert_true(bc.has_method("is_debug_build"))


# ── Override ──────────────────────────────────────────────────────────────────

func test_force_off_hides_debug_ui() -> void:
	if bc == null:
		pending("BuildConfig autoload missing")
		return
	bc.set_override(BuildConfigScript.Mode.FORCE_OFF)
	assert_false(bc.show_debug_ui(),
			"FORCE_OFF must hide debug UI even in editor")


func test_force_on_shows_debug_ui() -> void:
	if bc == null:
		pending("BuildConfig autoload missing")
		return
	bc.set_override(BuildConfigScript.Mode.FORCE_ON)
	assert_true(bc.show_debug_ui(),
			"FORCE_ON must reveal debug UI even in release")


# ── Wiring through PlaySubmenu ────────────────────────────────────────────────

func test_play_submenu_hides_debug_rows_in_release() -> void:
	if bc == null:
		pending("BuildConfig autoload missing")
		return
	bc.set_override(BuildConfigScript.Mode.FORCE_OFF)
	var sub := PlaySubmenuScript.new()
	add_child_autofree(sub)
	assert_false(sub._btn_levels_debug.visible,
			"Levels (debug) row must be hidden in release builds")
	assert_false(sub._btn_seed.visible,
			"Seed row must be hidden in release builds")
	# Player-facing rows stay visible.
	assert_true(sub._btn_continue.visible)
	assert_true(sub._btn_levels.visible)
	assert_true(sub._btn_profile.visible)


func test_play_submenu_shows_debug_rows_when_force_on() -> void:
	if bc == null:
		pending("BuildConfig autoload missing")
		return
	bc.set_override(BuildConfigScript.Mode.FORCE_ON)
	var sub := PlaySubmenuScript.new()
	add_child_autofree(sub)
	assert_true(sub._btn_levels_debug.visible,
			"Levels (debug) row must be visible in dev builds")
	assert_true(sub._btn_seed.visible,
			"Seed row must be visible in dev builds")
