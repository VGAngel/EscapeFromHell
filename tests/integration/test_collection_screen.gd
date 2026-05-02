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
	# Pin layout to narrow so existing assertions (_sheet_open,
	# _sheet_*.text) stay deterministic regardless of test viewport size.
	# Wide-layout routing has its own dedicated tests below.
	screen._force_layout = "narrow"
	if SaveManager:
		SaveManager._reset()
	screen._named_souls  = TEST_NAMED.duplicate(true)
	screen._hidden_souls = TEST_HIDDEN.duplicate(true)
	screen._filter_circle  = 0
	screen._filter_type    = "all"
	screen._filter_missing = false
	screen._apply_layout_mode()
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
	# Cells now show the FULL name (no more substr to 5 chars), with
	# autowrap + dynamic font size handling overflow inside the cell.
	SaveManager.add_soul(1)
	screen._rebuild_grid()
	await get_tree().process_frame
	var cell: Button = screen._cell_nodes[1]
	var lbl: Label = cell.get_child(0)
	assert_eq(lbl.text, "Іван")

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

# Soul id 100 ("Безіменний") stores age as the string "?" rather than an
# int. Earlier `"%d років" % age` would crash on a string. Sheet must
# render it gracefully.
func test_show_sheet_handles_string_age_question_mark() -> void:
	var anon: Dictionary = {
		"id": 100, "name": "Безіменний", "circle": 10, "type": "sleeping",
		"age": "?", "level": 95, "sin": "unknown", "full_story": "тест",
	}
	screen._show_sheet(anon, false)
	assert_true(screen._sheet_age.text.contains("?"),
		"age label should contain '?' when soul.age is the string '?'")

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

func test_completion_label_shown_when_pool_complete() -> void:
	# Save IDs up to the dynamic pool target so this test stays valid as
	# the souls_collection.json grows beyond 100.
	var target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	for i in range(1, target + 1):
		SaveManager.add_soul(i)
	screen.notify_soul_added(1)
	assert_true(screen._completion_lbl.visible)

func test_lbl_named_turns_gold_when_pool_complete() -> void:
	var target: int = SaveManager.get_named_souls_target() if SaveManager else 100
	for i in range(1, target + 1):
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

func test_real_config_loads_named_souls_matching_target() -> void:
	# Pool size is now dynamic — assert it matches the JSON's declared
	# total_named via SaveManager.get_named_souls_target().
	var real: Node = preload("res://scripts/ui/CollectionScreen.gd").new()
	add_child_autofree(real)
	var expected: int = SaveManager.get_named_souls_target() if SaveManager else 100
	assert_eq(real._named_souls.size(), expected)

func test_real_config_loads_hidden_souls_matching_target() -> void:
	var real: Node = preload("res://scripts/ui/CollectionScreen.gd").new()
	add_child_autofree(real)
	var expected: int = SaveManager.get_hidden_souls_target() if SaveManager else 20
	assert_eq(real._hidden_souls.size(), expected)

# ── Wide layout (split view: grid + side panel) ───────────────────────────────

func test_side_panel_hidden_in_narrow_mode() -> void:
	screen._force_layout = "narrow"
	screen._apply_layout_mode()
	assert_false(screen._side_panel.visible)

func test_side_panel_visible_in_wide_mode() -> void:
	screen._force_layout = "wide"
	screen._apply_layout_mode()
	assert_true(screen._side_panel.visible)

func test_show_detail_in_wide_mode_does_not_open_sheet() -> void:
	screen._force_layout = "wide"
	screen._apply_layout_mode()
	SaveManager.add_soul(1)
	screen._show_detail(TEST_NAMED[0], false)
	assert_false(screen._sheet_open,
		"sheet must stay closed when wide-layout side panel is the target")

func test_show_detail_in_wide_mode_populates_side_panel() -> void:
	screen._force_layout = "wide"
	screen._apply_layout_mode()
	screen._show_detail(TEST_NAMED[0], false)
	assert_eq(screen._side_name.text, "Іван")
	assert_true(screen._side_text.text.contains("Тест"))

func test_show_detail_in_wide_mode_hides_placeholder() -> void:
	screen._force_layout = "wide"
	screen._apply_layout_mode()
	screen._show_detail(TEST_NAMED[0], false)
	assert_false(screen._side_placeholder.visible)

func test_open_resets_side_panel_to_placeholder() -> void:
	screen._force_layout = "wide"
	screen._apply_layout_mode()
	screen._show_detail(TEST_NAMED[0], false)
	screen.open()
	assert_true(screen._side_placeholder.visible)
	assert_false(screen._side_name.visible)

func test_show_detail_in_narrow_mode_opens_sheet() -> void:
	screen._force_layout = "narrow"
	screen._apply_layout_mode()
	screen._show_detail(TEST_NAMED[0], false)
	assert_true(screen._sheet_open)

# ── Per-type stats (J) ────────────────────────────────────────────────────────

func test_type_stats_strip_built() -> void:
	assert_not_null(screen._lbl_type_stats,
		"type stats label should exist")

func test_type_stats_format_contains_innocent_count() -> void:
	# TEST_NAMED has: 1 innocent + 1 broken + 1 sleeping.
	# With nothing saved: "🔥 0/1  •  💀 0/1  •  😴 0/1"
	screen._refresh_counters()
	assert_true(screen._lbl_type_stats.text.contains("0/1"),
		"stats should show 0/1 per category before any saves")
	assert_true(screen._lbl_type_stats.text.contains("🔥"))
	assert_true(screen._lbl_type_stats.text.contains("💀"))
	assert_true(screen._lbl_type_stats.text.contains("😴"))

func test_type_stats_updates_after_saving_innocent_soul() -> void:
	SaveManager.add_soul(1)  # id=1 is innocent in TEST_NAMED
	screen._refresh_counters()
	assert_true(screen._lbl_type_stats.text.contains("🔥 1/1"),
		"innocent counter should advance after saving an innocent soul")

func test_type_stats_skips_zero_total_categories() -> void:
	# Stub a list with only innocent souls — broken/sleeping should
	# not appear in the strip at all.
	screen._named_souls = [
		{
			"id": 11, "name": "А", "circle": 1, "type": "innocent",
			"age": 1, "level": 1, "sin": "none", "full_story": "",
		},
	]
	screen._refresh_counters()
	assert_false(screen._lbl_type_stats.text.contains("💀"),
		"broken icon should be omitted when no broken souls exist")
	assert_false(screen._lbl_type_stats.text.contains("😴"),
		"sleeping icon should be omitted when no sleeping souls exist")

# ── Hidden in per-type strip + grand-total counter ────────────────────────────

func test_type_stats_includes_hidden_marker() -> void:
	# Hidden souls now appear as a "✦ X/Y" entry alongside the type icons.
	# TEST_HIDDEN has 1 entry, none saved — expect "✦ 0/1".
	screen._refresh_counters()
	assert_true(screen._lbl_type_stats.text.contains("✦ 0/1"),
		"hidden tier should render as ✦ X/Y in the per-type strip")

func test_grand_total_label_exists() -> void:
	assert_not_null(screen._lbl_total,
		"grand total label should be built in the header")

func test_grand_total_combines_named_and_hidden_targets() -> void:
	# 3 named + 1 hidden in TEST data → target = 4. With nothing saved,
	# label should mention "0" and "4".
	screen._refresh_counters()
	assert_true(screen._lbl_total.text.contains("0"),
		"grand total label should show the saved count")
	assert_true(screen._lbl_total.text.contains("4"),
		"grand total label should show named+hidden combined target")

func test_grand_total_advances_after_saving() -> void:
	SaveManager.add_soul(1)
	SaveManager.add_hidden_soul("h1")
	screen._refresh_counters()
	assert_true(screen._lbl_total.text.contains("2"),
		"grand total should reflect both named and hidden saves")

# ── Hidden souls survive the type filter ──────────────────────────────────────

func test_hidden_soul_passes_type_filter_when_specific_type_selected() -> void:
	# Bug fix: previously _passes_filter dropped hidden souls when the
	# type filter wasn't "all" (their type field is missing).
	screen._filter_type = "innocent"
	screen._rebuild_grid()
	await get_tree().process_frame
	assert_true(screen._cell_nodes.has("h1"),
		"hidden soul cell should remain visible under non-'all' type filter")

# ── Sort, search, tooltip ─────────────────────────────────────────────────────

func test_sort_by_name_orders_alphabetically() -> void:
	# TEST_NAMED ids in name order: Іван (1), Марія (2), Петро (3).
	# But sort is alphabetical, so the order should be Іван < Марія < Петро.
	screen._sort_mode = "name"
	var sorted: Array = screen._sort_souls(screen._named_souls)
	assert_eq(String(sorted[0]["name"]), "Іван")
	assert_eq(String(sorted[1]["name"]), "Марія")
	assert_eq(String(sorted[2]["name"]), "Петро")

func test_sort_by_circle_groups_by_circle_then_id() -> void:
	# TEST_NAMED: id=1 c=1, id=2 c=2, id=3 c=1. Expect c=1 first (1, 3),
	# then c=2 (2).
	screen._sort_mode = "circle"
	var sorted: Array = screen._sort_souls(screen._named_souls)
	var ids: Array = []
	for s: Dictionary in sorted:
		ids.append(int(s["id"]))
	assert_eq(ids, [1, 3, 2])

func test_search_query_filters_by_name() -> void:
	screen._search_query = "марі"  # matches Марія only
	screen._rebuild_grid()
	await get_tree().process_frame
	# id=1 (Іван), id=3 (Петро) should be filtered out; id=2 (Марія) stays.
	assert_false(screen._cell_nodes.has(1), "Іван should be filtered out")
	assert_true(screen._cell_nodes.has(2),  "Марія should match the query")
	assert_false(screen._cell_nodes.has(3), "Петро should be filtered out")

func test_search_query_filters_by_epitaph_text() -> void:
	# TEST_NAMED entries have full_story like "Тест 2" — search on "2"
	# should match only that one.
	screen._search_query = "тест 2"
	screen._rebuild_grid()
	await get_tree().process_frame
	assert_true(screen._cell_nodes.has(2),
		"soul whose story contains 'тест 2' should pass the search")

func test_search_empty_query_shows_all() -> void:
	screen._search_query = ""
	screen._rebuild_grid()
	await get_tree().process_frame
	# 3 named + 1 hidden = 4
	assert_eq(screen._cell_nodes.size(), 4)

func test_sort_button_cycles_modes() -> void:
	# Sort button rotates through SORT_MODES. Starting at "id", one
	# press should land on "name".
	screen._sort_mode = "id"
	screen._on_sort_cycle_pressed()
	assert_eq(screen._sort_mode, "name")
	screen._on_sort_cycle_pressed()
	assert_eq(screen._sort_mode, "circle")

func test_saved_cell_has_tooltip_with_epitaph() -> void:
	# Long-press / hover preview is the cell's tooltip_text. For saved
	# souls it must include both the name and the epitaph snippet.
	SaveManager.add_soul(1)
	screen._rebuild_grid()
	await get_tree().process_frame
	var cell: Button = screen._cell_nodes[1]
	assert_true(cell.tooltip_text.contains("Іван"),
		"tooltip should include the soul name")
	assert_true(cell.tooltip_text.contains("Тест"),
		"tooltip should include the epitaph/story text")

func test_unsaved_cell_tooltip_is_generic() -> void:
	# Undiscovered souls keep their secret — tooltip should NOT echo the
	# real name/story.
	var cell: Button = screen._cell_nodes[1]  # id=1 unsaved by default
	assert_false(cell.tooltip_text.contains("Іван"),
		"undiscovered soul tooltip should not leak the name")

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_close_emits_signal() -> void:
	# TODO: signal emitted inside tween callback — cannot test synchronously
	pass

func test_escape_key_closes_sheet_not_screen() -> void:
	# TODO: requires InputEvent simulation for "ui_cancel"
	pass
