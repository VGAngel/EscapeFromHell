extends GutTest

# Integration tests for UpgradesScreen.gd (CanvasLayer).
# After instantiation, injects lightweight test categories and rebuilds cards
# so tests don't depend on the real upgrades_config.json content.
#
# NOTE: _rebuild_cards uses queue_free() which is deferred — every test that
# calls _switch_category() must await get_tree().process_frame before checking
# card children.

const TEST_CATEGORIES := [
	{
		"id": "test_cat",
		"name": "Тест",
		"upgrades": [
			{"id": "cheap_up", "name": "Дешевий", "description": "Тест", "cost": 5,  "max_level": 1},
			{"id": "multi_up", "name": "Мульті",  "description": "Тест", "cost": 10, "max_level": 3},
		]
	},
	{
		"id": "test_cat_2",
		"name": "Тест 2",
		"upgrades": [
			{"id": "other_up", "name": "Інший", "description": "Тест", "cost": 20, "max_level": 1},
		]
	},
]

var screen: Node

func before_each() -> void:
	screen = preload("res://scripts/ui/UpgradesScreen.gd").new()
	add_child_autofree(screen)
	if SaveManager:
		SaveManager._reset()
	screen._categories = TEST_CATEGORIES.duplicate(true)
	screen._switch_category(0)
	await get_tree().process_frame  # let queue_free flush old cards

# Helper: get buy button from card at index
func _card_btn(card_idx: int) -> Button:
	var card: PanelContainer = screen._cards_box.get_child(card_idx)
	var hbox: HBoxContainer  = card.get_child(0)
	return hbox.get_child(hbox.get_child_count() - 1) as Button

# Helper: get level dots row from card at index (multi-level upgrades only)
func _dots_row(card_idx: int) -> HBoxContainer:
	var card: PanelContainer = screen._cards_box.get_child(card_idx)
	var hbox: HBoxContainer  = card.get_child(0)
	var info: VBoxContainer  = hbox.get_child(0)
	return info.get_child(2) as HBoxContainer  # name, desc, dots_row

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	# _ready() sets visible = false
	assert_false(screen.visible)

func test_open_shows_screen() -> void:
	screen.open()
	assert_true(screen.visible)

func test_close_signal_declared() -> void:
	assert_true(screen.has_signal("closed"))

# ── Currency display ──────────────────────────────────────────────────────────

func test_currency_label_shows_light_on_open() -> void:
	SaveManager.add_light(150)
	screen.open()
	assert_true(screen._lbl_currency.text.contains("150"))

func test_currency_label_zero_by_default() -> void:
	screen.open()
	assert_true(screen._lbl_currency.text.contains("0"))

# ── Category tabs ─────────────────────────────────────────────────────────────

func test_first_category_active_after_switch() -> void:
	assert_eq(screen._cat_tabs[0].modulate, Color.WHITE)

func test_switching_category_dims_previous_tab() -> void:
	screen._switch_category(1)
	assert_ne(screen._cat_tabs[0].modulate, Color.WHITE)

func test_switching_category_highlights_new_tab() -> void:
	screen._switch_category(1)
	assert_eq(screen._cat_tabs[1].modulate, Color.WHITE)

func test_switching_category_updates_active_index() -> void:
	screen._switch_category(1)
	assert_eq(screen._active_cat, 1)

func test_switching_to_cat_1_rebuilds_one_card() -> void:
	screen._switch_category(1)
	await get_tree().process_frame
	assert_eq(screen._cards_box.get_child_count(), 1)

func test_switching_to_cat_0_has_two_cards() -> void:
	# already on cat 0 from before_each
	assert_eq(screen._cards_box.get_child_count(), 2)

# ── Upgrade cards — button states ─────────────────────────────────────────────

func test_unaffordable_upgrade_button_disabled() -> void:
	# light=0, cheap_up costs 5 → disabled
	var btn: Button = _card_btn(0)
	assert_true(btn.disabled)

func test_affordable_upgrade_shows_buy_button() -> void:
	SaveManager.add_light(50)
	screen._switch_category(0)
	await get_tree().process_frame
	var btn: Button = _card_btn(0)
	assert_false(btn.disabled)
	assert_true(btn.text.contains("Купити"))

func test_maxed_upgrade_shows_max_label() -> void:
	SaveManager.set_upgrade_level("cheap_up", 1)  # max_level=1 → maxed
	screen._switch_category(0)
	await get_tree().process_frame
	var btn: Button = _card_btn(0)
	assert_eq(btn.text, "МАКС")
	assert_true(btn.disabled)

func test_partially_leveled_upgrade_shows_buy_button() -> void:
	SaveManager.add_light(100)
	SaveManager.set_upgrade_level("multi_up", 1)  # cur=1, max=3 → not maxed
	screen._switch_category(0)
	await get_tree().process_frame
	var btn: Button = _card_btn(1)
	assert_false(btn.disabled)

# ── Level dots ────────────────────────────────────────────────────────────────

func test_level_dots_count_matches_max_level() -> void:
	var dots: HBoxContainer = _dots_row(1)  # multi_up has max_level=3
	assert_eq(dots.get_child_count(), 3)

func test_level_dots_all_inactive_at_level_zero() -> void:
	var dots: HBoxContainer = _dots_row(1)
	for i in 3:
		assert_eq(dots.get_child(i).color, Color(0.28, 0.26, 0.35))

func test_level_dots_reflect_current_level_two() -> void:
	SaveManager.set_upgrade_level("multi_up", 2)
	screen._switch_category(0)
	await get_tree().process_frame
	var dots: HBoxContainer = _dots_row(1)
	assert_eq(dots.get_child(0).color, Color("#88DD88"))
	assert_eq(dots.get_child(1).color, Color("#88DD88"))
	assert_eq(dots.get_child(2).color, Color(0.28, 0.26, 0.35))

# ── Purchase flow ─────────────────────────────────────────────────────────────

func test_buy_button_spends_light() -> void:
	SaveManager.add_light(100)
	screen._switch_category(0)
	await get_tree().process_frame
	_card_btn(0).pressed.emit()  # cheap_up cost=5
	assert_eq(SaveManager.get_light(), 95)

func test_buy_button_increments_upgrade_level() -> void:
	SaveManager.add_light(100)
	screen._switch_category(0)
	await get_tree().process_frame
	_card_btn(0).pressed.emit()
	assert_eq(SaveManager.get_upgrade_level("cheap_up"), 1)

func test_buy_button_rebuilds_cards_to_maxed() -> void:
	SaveManager.add_light(100)
	screen._switch_category(0)
	await get_tree().process_frame
	_card_btn(0).pressed.emit()  # cheap_up max_level=1 → now maxed
	await get_tree().process_frame
	var btn: Button = _card_btn(0)
	assert_eq(btn.text, "МАКС")

func test_buy_with_insufficient_light_does_not_spend() -> void:
	SaveManager.add_light(3)  # cheap_up costs 5
	screen._on_buy("cheap_up", 5, 0, 1)
	assert_eq(SaveManager.get_light(), 3)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_currency_flashes_red_on_failed_purchase() -> void:
	# TODO: async tween — _flash_currency animates _lbl_currency color
	pass

func test_escape_key_closes_screen() -> void:
	# TODO: requires InputEvent simulation for "ui_cancel"
	pass
