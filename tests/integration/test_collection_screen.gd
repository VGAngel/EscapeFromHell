extends GutTest

# Integration tests for CollectionScreen.gd (CanvasLayer).
# Injects lightweight test soul data after _ready() so tests are independent
# of souls_collection.json content.
# _rebuild_grid() uses queue_free() (deferred) — tests checking grid cell counts
# must await get_tree().process_frame after any filter change or open().

const TEST_NAMED := [
	{"id": 1, "name": "Іван",  "circle": 1, "type": "innocent", "age": 25, "level": 1,
	 "sin": "none",  "full_story": "Тест"},
	{"id": 2, "name": "Марія", "circle": 2, "type": "broken",   "age": 30, "level": 2,
	 "sin": "greed", "full_story": "Тест 2"},
	{"id": 3, "name": "Петро", "circle": 1, "type": "sleeping",  "age": 45, "level": 1,
	 "sin": "none",  "full_story": "Тест 3"},
]
const TEST_HIDDEN := [
	{"id": "h1", "name": "Ангел", "circle": 3, "type": "hidden", "age": 99,
	 "reward": "Додаткове життя"},
]

var screen: Node

func before_each() -> void:
	screen = preload("res://scripts/ui/CollectionScreen.gd").new()
	add_child_autofree(screen)
	if SaveManager:
		SaveManager._reset()
	screen._named_souls  = TEST_NAMED.duplicate(true)
	screen._hidden_souls = TEST_HIDDEN.duplicate(true)
	screen._filter_circle  = 0
	screen._filter_type    = "all"
	screen._filter_missing = false
	screen._rebuild_grid()
	await get_tree().process_frame

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	assert_false(screen.visible)

func test_open_makes_visible() -> void:
	screen.open()
	assert_true(screen.visible)

func test_close_signal_declared() -> void:
	assert_true(screen.has_signal("closed"))

func test_open_calls_close_sheet_instant() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])  # opens sheet
	assert_true(screen._sheet_open)
	screen.open()
	assert_false(screen._sheet_open)

# ── Counter labels ────────────────────────────────────────────────────────────

func test_named_counter_shows_zero_by_default() -> void:
	screen.open()
	assert_true(screen._lbl_named.text.contains("0"))

func test_named_counter_updates_after_add_soul() -> void:
	SaveManager.add_soul(1)
	screen.open()
	assert_true(screen._lbl_named.text.contains("1"))

func test_hidden_counter_format() -> void:
	screen.open()
	assert_true(screen._lbl_hidden.text.contains("0 / 20"))

# ── Grid cell count ───────────────────────────────────────────────────────────

func test_grid_shows_all_souls_no_filter() -> void:
	# 3 named + 1 hidden = 4 cells
	assert_eq(screen._grid.get_child_count(), 4)

func test_cell_nodes_populated_after_rebuild() -> void:
	assert_eq(screen._cell_nodes.size(), 4)

func test_cell_nodes_keyed_by_id() -> void:
	assert_true(screen._cell_nodes.has(1))
	assert_true(screen._cell_nodes.has("h1"))

# ── Cell appearance ───────────────────────────────────────────────────────────

func test_unsaved_soul_cell_shows_question_mark() -> void:
	var cell: Button = screen._cell_nodes[1]
	var lbl: Label = cell.get_child(0)
	assert_eq(lbl.text, "?")

func test_saved_soul_cell_shows_name() -> void:
	SaveManager.add_soul(1)
	screen._rebuild_grid()
	await get_tree().process_frame
	var cell: Button = screen._cell_nodes[1]
	var lbl: Label = cell.get_child(0)
	assert_eq(lbl.text, "Іван".substr(0, 5))

func test_hidden_soul_cell_has_badge() -> void:
	# Hidden cell has: Label (main) + Label (badge ✦) = 2 children
	var cell: Button = screen._cell_nodes["h1"]
	assert_eq(cell.get_child_count(), 2)

func test_named_soul_cell_has_no_badge() -> void:
	var cell: Button = screen._cell_nodes[1]
	assert_eq(cell.get_child_count(), 1)

# ── _passes_filter ────────────────────────────────────────────────────────────

func test_passes_filter_with_no_filters() -> void:
	assert_true(screen._passes_filter(TEST_NAMED[0], false))

func test_passes_filter_circle_match() -> void:
	screen._filter_circle = 1
	assert_true(screen._passes_filter(TEST_NAMED[0], false))  # circle=1

func test_passes_filter_circle_mismatch() -> void:
	screen._filter_circle = 2
	assert_false(screen._passes_filter(TEST_NAMED[0], false))  # circle=1

func test_passes_filter_type_match() -> void:
	screen._filter_type = "innocent"
	assert_true(screen._passes_filter(TEST_NAMED[0], false))  # type=innocent

func test_passes_filter_type_mismatch() -> void:
	screen._filter_type = "innocent"
	assert_false(screen._passes_filter(TEST_NAMED[1], false))  # type=broken

# ── Filter actions ────────────────────────────────────────────────────────────

func test_circle_tabs_count() -> void:
	# 1 "Всі" + 10 numbered = 11
	assert_eq(screen._circle_tabs.size(), 11)

func test_type_btns_count() -> void:
	assert_eq(screen._type_btns.size(), 4)

func test_circle_tab_zero_active_initially() -> void:
	assert_eq(screen._circle_tabs[0].modulate, Color.WHITE)

func test_on_circle_tab_updates_filter_state() -> void:
	screen._on_circle_tab(2)
	assert_eq(screen._filter_circle, 2)

func test_on_type_btn_updates_filter_state() -> void:
	screen._on_type_btn("innocent")
	assert_eq(screen._filter_type, "innocent")

func test_on_missing_toggle_flips_flag() -> void:
	assert_false(screen._filter_missing)
	screen._on_missing_toggle()
	assert_true(screen._filter_missing)

func test_on_missing_toggle_twice_restores_flag() -> void:
	screen._on_missing_toggle()
	screen._on_missing_toggle()
	assert_false(screen._filter_missing)

func test_circle_filter_reduces_cell_count() -> void:
	screen._on_circle_tab(1)
	await get_tree().process_frame
	# Only circle-1 souls: Іван, Петро = 2
	assert_eq(screen._grid.get_child_count(), 2)

func test_type_filter_reduces_cell_count() -> void:
	screen._on_type_btn("innocent")
	await get_tree().process_frame
	# Only innocent: Іван = 1
	assert_eq(screen._grid.get_child_count(), 1)

func test_missing_filter_hides_saved_soul() -> void:
	SaveManager.add_soul(1)
	screen._on_missing_toggle()
	await get_tree().process_frame
	assert_false(screen._cell_nodes.has(1))

func test_missing_filter_keeps_unsaved_soul() -> void:
	SaveManager.add_soul(1)
	screen._on_missing_toggle()
	await get_tree().process_frame
	# Ids 2, 3 are unsaved, h1 is unsaved → still visible
	assert_true(screen._cell_nodes.has(2))

# ── Detail sheet ──────────────────────────────────────────────────────────────

func test_sheet_closed_by_default() -> void:
	assert_false(screen._sheet_open)

func test_show_sheet_sets_open_flag() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	assert_true(screen._sheet_open)

func test_show_sheet_sets_name() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	assert_eq(screen._sheet_name.text, "Іван")

func test_show_sheet_sets_age() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	assert_eq(screen._sheet_age.text, "25 років")

func test_show_sheet_sets_location_named() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	assert_true(screen._sheet_loc.text.contains("Коло 1"))
	assert_true(screen._sheet_loc.text.contains("Рівень 1"))

func test_show_sheet_sets_location_hidden() -> void:
	screen._show_sheet(TEST_HIDDEN[0], true)
	assert_true(screen._sheet_loc.text.contains("Прихована"))

func test_show_sheet_not_found_sets_name() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])
	assert_eq(screen._sheet_name.text, "Душа не знайдена")

func test_show_sheet_not_found_sets_open_flag() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])
	assert_true(screen._sheet_open)

func test_close_sheet_instant_clears_flag() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	screen._close_sheet_instant()
	assert_false(screen._sheet_open)

func test_close_sheet_instant_hides_sheet() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	screen._close_sheet_instant()
	assert_false(screen._sheet.visible)

# ── Completion label ───────────────────────────────────────────────────────────

func test_completion_label_hidden_initially() -> void:
	assert_false(screen._completion_lbl.visible)

# ── Notifications ─────────────────────────────────────────────────────────────

func test_notify_soul_added_refreshes_named_counter() -> void:
	screen.open()
	await get_tree().process_frame
	SaveManager.add_soul(1)
	screen.notify_soul_added(1)
	assert_true(screen._lbl_named.text.contains("1"))

# ── Sheet content ─────────────────────────────────────────────────────────────

func test_show_sheet_displays_story_text() -> void:
	screen._show_sheet(TEST_NAMED[0], false)
	assert_eq(screen._sheet_text.text, "Тест")

func test_show_sheet_sin_shown_for_named_with_sin() -> void:
	screen._show_sheet(TEST_NAMED[1], false)  # sin="greed"
	assert_true(screen._sheet_extra.text.contains("greed"))
	assert_true(screen._sheet_extra.visible)

func test_show_sheet_extra_hidden_when_sin_is_none() -> void:
	screen._show_sheet(TEST_NAMED[0], false)  # sin="none" → extra hidden
	assert_false(screen._sheet_extra.visible)

func test_show_sheet_reward_shown_for_hidden_soul() -> void:
	screen._show_sheet(TEST_HIDDEN[0], true)
	assert_true(screen._sheet_extra.text.contains("Додаткове життя"))
	assert_true(screen._sheet_extra.visible)

func test_show_sheet_not_found_hint_text() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])
	assert_true(screen._sheet_text.text.contains("Продовжуй"))

func test_show_sheet_not_found_hides_age() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])
	assert_false(screen._sheet_age.visible)

func test_show_sheet_not_found_hides_separator() -> void:
	screen._show_sheet_not_found(TEST_NAMED[0])
	assert_false(screen._sheet_sep.visible)

# ── Cell press flow ───────────────────────────────────────────────────────────

func test_cell_press_opens_not_found_when_unsaved() -> void:
	# soul id=1 is unsaved by default
	var cell: Button = screen._cell_nodes[1]
	cell.pressed.emit()
	assert_true(screen._sheet_open)
	assert_eq(screen._sheet_name.text, "Душа не знайдена")

func test_cell_press_opens_sheet_for_saved_soul() -> void:
	SaveManager.add_soul(1)
	screen._rebuild_grid()
	await get_tree().process_frame
	var cell: Button = screen._cell_nodes[1]
	cell.pressed.emit()
	assert_true(screen._sheet_open)
	assert_eq(screen._sheet_name.text, "Іван")

# ── Notifications ──────────────────────────────────────────────────────────────

func test_notify_hidden_soul_added_refreshes_counter() -> void:
	screen.open()
	SaveManager.add_hidden_soul("h1")
	screen.notify_hidden_soul_added("h1")
	assert_true(screen._lbl_hidden.text.contains("1"))

# ── Completion label ───────────────────────────────────────────────────────────

func test_completion_label_shown_at_100_souls() -> void:
	for i in range(1, 101):
		SaveManager.add_soul(i)
	screen.notify_soul_added(1)
	assert_true(screen._completion_lbl.visible)

func test_lbl_named_turns_gold_at_100_souls() -> void:
	for i in range(1, 101):
		SaveManager.add_soul(i)
	screen.open()
	assert_eq(screen._lbl_named.get_theme_color("font_color"), Color("#FFD700"))

# ── Filter button highlight ────────────────────────────────────────────────────

func test_circle_tab_one_active_after_switch() -> void:
	screen._on_circle_tab(1)
	assert_eq(screen._circle_tabs[1].modulate, Color.WHITE)

func test_circle_tab_all_dimmed_after_switch_to_one() -> void:
	screen._on_circle_tab(1)
	assert_ne(screen._circle_tabs[0].modulate, Color.WHITE)

func test_type_btn_broken_active_after_switch() -> void:
	screen._on_type_btn("broken")
	assert_eq(screen._type_btns["broken"].modulate, Color.WHITE)

func test_type_btn_all_dimmed_after_switch_to_broken() -> void:
	screen._on_type_btn("broken")
	assert_ne(screen._type_btns["all"].modulate, Color.WHITE)

func test_missing_btn_white_when_active() -> void:
	screen._on_missing_toggle()
	assert_eq(screen._btn_missing.modulate, Color.WHITE)

func test_missing_btn_dimmed_when_inactive() -> void:
	assert_ne(screen._btn_missing.modulate, Color.WHITE)

# ── Real config integration ────────────────────────────────────────────────────

func test_real_config_loads_100_named_souls() -> void:
	var real: Node = preload("res://scripts/ui/CollectionScreen.gd").new()
	add_child_autofree(real)
	assert_eq(real._named_souls.size(), 100)

func test_real_config_loads_20_hidden_souls() -> void:
	var real: Node = preload("res://scripts/ui/CollectionScreen.gd").new()
	add_child_autofree(real)
	assert_eq(real._hidden_souls.size(), 20)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_close_emits_signal() -> void:
	# TODO: signal emitted inside tween callback — cannot test synchronously
	pass

func test_escape_key_closes_sheet_not_screen() -> void:
	# TODO: requires InputEvent simulation for "ui_cancel"
	pass
