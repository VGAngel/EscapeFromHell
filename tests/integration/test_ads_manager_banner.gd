extends GutTest

# Covers AdsManager banner-height contract — the value MainMenu uses to
# reserve bottom space so the ad placeholder never overlaps menu content.
#
# Expected: ~60 px while ads are active, exactly 0 once ads are removed.

const BANNER_HEIGHT_PX := 60

func before_each() -> void:
	if SaveManager:
		SaveManager._reset()

# ── Mock mode contract ────────────────────────────────────────────────────────

func test_is_mock_mode_true_in_test_env() -> void:
	assert_true(AdsManager.is_mock_mode(),
		"AdMob + Billing singletons aren't registered in tests, so mock mode " +
		"should engage automatically")

# ── Banner height contract ────────────────────────────────────────────────────

func test_banner_height_matches_config_before_purchase() -> void:
	# Fresh save, no purchases — banner should report the config value.
	if SaveManager:
		SaveManager.set_flag("no_ads_purchased", false)
	# Reload save flag into AdsManager._ads_removed
	AdsManager._ads_removed = false
	assert_eq(AdsManager.get_banner_height(), BANNER_HEIGHT_PX,
		"Banner height must match monetization_config.layout.banner_height_px")

func test_banner_height_is_zero_after_no_ads_purchase() -> void:
	AdsManager._ads_removed = true
	assert_eq(AdsManager.get_banner_height(), 0,
		"Once no_ads is purchased the banner collapses — get_banner_height " +
		"must return 0 so the menu can reclaim the space")

# ── is_ads_removed reflects SaveManager flag ──────────────────────────────────

func test_is_ads_removed_reflects_flag() -> void:
	AdsManager._ads_removed = true
	assert_true(AdsManager.is_ads_removed())
	AdsManager._ads_removed = false
	assert_false(AdsManager.is_ads_removed())
