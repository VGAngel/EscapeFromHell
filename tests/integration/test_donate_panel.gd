extends GutTest

# Integration tests for DonatePanel.gd (CanvasLayer).

# ── Open / close ──────────────────────────────────────────────────────────────

func test_invisible_by_default() -> void:
	# TODO: instantiate DonatePanel, assert visible == false
	pass

func test_open_shows_panel() -> void:
	# TODO: call open(), assert visible == true
	pass

func test_close_emits_signal() -> void:
	# TODO: watch "closed", call close(), assert received
	pass

# ── Tier cards ────────────────────────────────────────────────────────────────

func test_tier_cards_built_for_each_sku() -> void:
	# TODO: open panel, assert one card exists per entry in TIER_META
	pass

func test_tier_name_displayed_on_card() -> void:
	# TODO: assert card label shows tier_name from TIER_META
	pass

func test_tier_icon_displayed() -> void:
	# TODO: assert icon label shows emoji from TIER_META
	pass

# ── Purchase ──────────────────────────────────────────────────────────────────

func test_buy_button_calls_ads_manager_iap() -> void:
	# TODO: mock AdsManager.purchase_iap(), press buy button,
	# assert AdsManager.purchase_iap() called with correct SKU
	pass

func test_thanks_label_shown_after_purchase() -> void:
	# TODO: simulate successful purchase callback, assert thanks label visible
	pass

func test_thanks_label_fades_out() -> void:
	# TODO: trigger thanks display, wait fade duration,
	# assert thanks label invisible again
	pass

# ── Input ─────────────────────────────────────────────────────────────────────

func test_escape_key_closes_panel() -> void:
	# TODO: open, simulate ui_cancel, assert closed
	pass
