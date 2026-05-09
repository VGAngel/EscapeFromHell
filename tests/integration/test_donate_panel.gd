extends GutTest

# Integration tests for DonatePanel.gd (CanvasLayer).
# AdsManager.get_donate_tiers() returns [] in test mode → fallback builds
# one card per TIER_META key (4 cards total).

var dp: Node

func before_each() -> void:
	dp = preload("res://scripts/ui/DonatePanel.gd").new()
	add_child_autofree(dp)

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	assert_false(dp.visible)

func test_open_shows_panel() -> void:
	dp.open()
	assert_true(dp.visible)

func test_close_signal_declared() -> void:
	assert_true(dp.has_signal("closed"))

func test_open_hides_thanks_label() -> void:
	dp._show_thanks()
	dp.open()
	assert_false(dp._lbl_thanks.visible)

# ── Tier cards (fallback path — AdsManager.get_donate_tiers() == []) ──────────

func test_tier_cards_built_on_open() -> void:
	dp.open()
	await get_tree().process_frame
	assert_eq(dp._cards_box.get_child_count(), 4)

func test_tier_card_has_icon_label() -> void:
	dp.open()
	await get_tree().process_frame
	var hbox: HBoxContainer = dp._cards_box.get_child(0).get_child(0)
	var icon_lbl: Label = hbox.get_child(0)
	assert_true(icon_lbl.text.length() > 0)

func test_tier_card_has_name_label() -> void:
	dp.open()
	await get_tree().process_frame
	var hbox: HBoxContainer = dp._cards_box.get_child(0).get_child(0)
	var vbox: VBoxContainer = hbox.get_child(1)
	var name_lbl: Label = vbox.get_child(0)
	assert_true(name_lbl.text.length() > 0)

func test_first_card_icon_matches_tier_meta() -> void:
	dp.open()
	await get_tree().process_frame
	# Keys order: donate_1, donate_3, donate_5, donate_10
	var hbox: HBoxContainer = dp._cards_box.get_child(0).get_child(0)
	var icon_lbl: Label = hbox.get_child(0)
	assert_eq(icon_lbl.text, dp.TIER_META["donate_1"]["icon"])

func test_first_card_name_matches_tier_meta() -> void:
	dp.open()
	await get_tree().process_frame
	var hbox: HBoxContainer = dp._cards_box.get_child(0).get_child(0)
	var name_lbl: Label = hbox.get_child(1).get_child(0)
	assert_eq(name_lbl.text, dp.TIER_META["donate_1"]["name"])

func test_card_buy_button_exists() -> void:
	dp.open()
	await get_tree().process_frame
	var hbox: HBoxContainer = dp._cards_box.get_child(0).get_child(0)
	var btn: Button = hbox.get_child(hbox.get_child_count() - 1)
	assert_true(btn is Button)
	assert_eq(btn.text, "Підтримати")

func test_four_tier_meta_entries() -> void:
	assert_eq(dp.TIER_META.size(), 4)

# ── Thanks label ──────────────────────────────────────────────────────────────

func test_thanks_label_hidden_initially() -> void:
	assert_false(dp._lbl_thanks.visible)

func test_show_thanks_makes_label_visible() -> void:
	dp._show_thanks()
	assert_true(dp._lbl_thanks.visible)

func test_show_thanks_sets_showing_flag() -> void:
	dp._show_thanks()
	assert_true(dp._showing_thanks)

func test_show_thanks_sets_timer() -> void:
	dp._show_thanks()
	assert_almost_eq(dp._thank_timer, 3.5, 0.01)

func test_show_thanks_sets_correct_text() -> void:
	dp._show_thanks()
	assert_true(dp._lbl_thanks.text.contains("Дякуємо"))

func test_on_donate_purchased_triggers_thanks() -> void:
	dp._on_donate_purchased("donate_1")
	assert_true(dp._showing_thanks)
	assert_true(dp._lbl_thanks.visible)

# ── TODO ──────────────────────────────────────────────────────────────────────

func test_buy_button_calls_ads_manager_iap() -> void:
	# TODO: requires AdsManager mock — purchase_donate() triggers platform billing
	pending("not yet implemented")

func test_thanks_label_fades_out() -> void:
	# TODO: requires process frame simulation to decrement _thank_timer
	pending("not yet implemented")

func test_escape_key_closes_panel() -> void:
	# TODO: requires InputEvent simulation for "ui_cancel"
	pending("not yet implemented")
