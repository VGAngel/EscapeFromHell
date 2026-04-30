extends GutTest

# Tests for LevelSelect — player-facing level picker.
# Locked levels render as disabled "🔒" rows; unlocked rows show
# stars + best-time + souls and tap-to-launch.

const LevelSelectScript := preload("res://scripts/ui/LevelSelect.gd")

var ls: CanvasLayer
var sm: Node


func before_each() -> void:
	sm = get_node_or_null("/root/SaveManager")
	ls = LevelSelectScript.new()
	add_child_autofree(ls)


# ── Build ─────────────────────────────────────────────────────────────────────

func test_builds_root_and_list() -> void:
	assert_not_null(ls._root)
	assert_not_null(ls._scroll)
	assert_not_null(ls._list)


func test_router_title_non_empty() -> void:
	assert_ne(ls.router_title(), "")


# ── Population ────────────────────────────────────────────────────────────────

func test_populate_creates_rows_for_all_levels() -> void:
	if sm == null:
		pending("SaveManager autoload missing")
		return
	ls._populate()
	# Expect at least 1 row (matches LevelConfig or fallback range).
	assert_gt(ls._list.get_child_count(), 0,
			"populate must create at least one level row")


func test_locked_levels_are_disabled() -> void:
	if sm == null or not sm.has_method("set_current_level"):
		pending("SaveManager autoload missing")
		return
	sm.set_current_level(1)
	ls._populate()
	# First child = level 1 (unlocked). Some later child should be locked.
	var any_locked := false
	for child in ls._list.get_children():
		if child is Button and child.disabled:
			any_locked = true
			assert_string_contains(child.text, "🔒",
					"locked rows must show the lock icon")
			break
	assert_true(any_locked,
			"with current_level=1, levels 2+ must render as locked")


func test_unlocked_level_button_is_enabled() -> void:
	if sm == null or not sm.has_method("set_current_level"):
		pending("SaveManager autoload missing")
		return
	sm.set_current_level(5)
	ls._populate()
	var first: Button = ls._list.get_child(0) as Button
	assert_false(first.disabled,
			"level 1 must be enabled when current_level=5")


# ── Format helpers ────────────────────────────────────────────────────────────

func test_stars_renders_three_glyphs() -> void:
	assert_eq(ls._stars(0), "☆☆☆")
	assert_eq(ls._stars(1), "★☆☆")
	assert_eq(ls._stars(3), "★★★")
	# Out of range clamps.
	assert_eq(ls._stars(99), "★★★")


func test_format_time_handles_minutes_and_seconds() -> void:
	assert_eq(ls._format_time(0.0), "—:—")
	assert_eq(ls._format_time(45.0), "0:45")
	assert_eq(ls._format_time(125.0), "2:05")
