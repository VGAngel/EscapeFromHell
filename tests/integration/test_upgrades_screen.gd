extends GutTest

# Integration tests for UpgradesScreen.gd (CanvasLayer).

var screen: Node

func before_each() -> void:
	# TODO: instantiate UpgradesScreen, inject upgrades_config data, build UI
	pass

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	# TODO: assert screen.visible == false
	pass

func test_open_shows_screen() -> void:
	# TODO: call screen.open(), assert visible == true
	pass

func test_close_emits_signal() -> void:
	# TODO: watch "closed", close(), assert received
	pass

# ── Currency display ──────────────────────────────────────────────────────────

func test_currency_label_shows_current_light() -> void:
	# TODO: set SaveManager light = 150, open, assert label shows "💡 150"
	pass

func test_currency_flashes_red_on_failed_purchase() -> void:
	# TODO: try to buy upgrade without enough light,
	# assert _lbl_currency tween to red triggered
	pass

# ── Category tabs ─────────────────────────────────────────────────────────────

func test_first_category_active_on_open() -> void:
	# TODO: open screen, assert _cat_tabs[0].modulate == Color.WHITE
	pass

func test_switching_category_updates_active_tab() -> void:
	# TODO: simulate tab 1 press, assert tab 1 is white and tab 0 is dimmed
	pass

func test_switching_category_rebuilds_cards() -> void:
	# TODO: switch to category 1, assert cards match that category's upgrades
	pass

# ── Upgrade cards ─────────────────────────────────────────────────────────────

func test_maxed_upgrade_shows_max_label() -> void:
	# TODO: set upgrade vitality to max_level, open,
	# assert buy button text == "МАКС"
	pass

func test_affordable_upgrade_shows_buy_button() -> void:
	# TODO: set light >= upgrade cost, open, assert button enabled
	pass

func test_unaffordable_upgrade_button_disabled() -> void:
	# TODO: set light = 0, assert buy button disabled
	pass

func test_level_dots_reflect_current_level() -> void:
	# TODO: set upgrade level to 2 out of 3,
	# assert 2 dots are active color, 1 is inactive
	pass

# ── Purchase flow ─────────────────────────────────────────────────────────────

func test_buy_button_spends_light() -> void:
	# TODO: set light = 100, upgrade costs 30, press buy,
	# assert SaveManager.get_light() == 70
	pass

func test_buy_button_increments_upgrade_level() -> void:
	# TODO: buy upgrade, assert get_upgrade_level() increased by 1
	pass

func test_buy_button_rebuilds_cards() -> void:
	# TODO: buy upgrade, assert card for that upgrade now shows level + 1
	pass

# ── Input ─────────────────────────────────────────────────────────────────────

func test_escape_key_closes_screen() -> void:
	# TODO: open screen, simulate ui_cancel, assert closed
	pass
