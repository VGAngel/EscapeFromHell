extends GutTest

# Covers MainMenu._apply_banner_space — the layout has to reserve room at
# the bottom for the ad banner when ads are active, and reclaim that space
# once "no_ads" is purchased.
#
# Expected values are what _apply_banner_space() produces in a 1080×1920
# viewport (content_scale_size) with no-ads baseline (banner_h = 0):
#   VersionLabel: offset_top = -50, offset_bottom = -20 (anchored to bottom)
#   ButtonsContainer: anchored at viewport center with symmetric offsets
#     (-485 / +485) that exactly fit 9 × 90 px buttons + 8 × 20 px gaps.
#     With a banner present the container shifts up by banner_h / 2 so its
#     visual midpoint stays above the banner.
# If the _apply_banner_space formula changes, update here too.

const VERSION_TOP_DEFAULT:    float = -50.0
const VERSION_BOTTOM_DEFAULT: float = -20.0
const BUTTONS_TOP_DEFAULT:    float = -485.0
const BUTTONS_BOTTOM_DEFAULT: float =  485.0
const BANNER_PX:              int   = 60

const MainMenuScene := preload("res://scenes/ui/MainMenu.tscn")

func before_each() -> void:
	if SaveManager:
		SaveManager._reset()

func _make_menu() -> Control:
	var menu: Control = MainMenuScene.instantiate() as Control
	add_child_autofree(menu)
	return menu

# ── Banner present ────────────────────────────────────────────────────────────

func test_version_label_shifted_up_by_banner_height_when_ads_active() -> void:
	AdsManager._ads_removed = false
	var menu: Control = _make_menu()
	var lbl: Label = menu.get_node("VersionLabel") as Label
	assert_almost_eq(lbl.offset_top,    VERSION_TOP_DEFAULT    - BANNER_PX, 0.5)
	assert_almost_eq(lbl.offset_bottom, VERSION_BOTTOM_DEFAULT - BANNER_PX, 0.5)

func test_buttons_container_shifted_up_by_banner_height_when_ads_active() -> void:
	AdsManager._ads_removed = false
	var menu: Control = _make_menu()
	var buttons: Control = menu.get_node("ButtonsContainer") as Control
	# Both edges shift up by banner_h / 2 so the container stays the same
	# height — only its center moves above the banner.
	assert_almost_eq(buttons.offset_top,    BUTTONS_TOP_DEFAULT    - BANNER_PX * 0.5, 0.5)
	assert_almost_eq(buttons.offset_bottom, BUTTONS_BOTTOM_DEFAULT - BANNER_PX * 0.5, 0.5)

# ── Ads removed ───────────────────────────────────────────────────────────────

func test_version_label_full_position_after_no_ads() -> void:
	AdsManager._ads_removed = true
	var menu: Control = _make_menu()
	var lbl: Label = menu.get_node("VersionLabel") as Label
	assert_almost_eq(lbl.offset_top,    VERSION_TOP_DEFAULT,    0.5)
	assert_almost_eq(lbl.offset_bottom, VERSION_BOTTOM_DEFAULT, 0.5)

func test_buttons_container_full_position_after_no_ads() -> void:
	AdsManager._ads_removed = true
	var menu: Control = _make_menu()
	var buttons: Control = menu.get_node("ButtonsContainer") as Control
	assert_almost_eq(buttons.offset_top,    BUTTONS_TOP_DEFAULT,    0.5)
	assert_almost_eq(buttons.offset_bottom, BUTTONS_BOTTOM_DEFAULT, 0.5)

# ── Reactive reflow on purchase ───────────────────────────────────────────────

func test_version_label_reflows_after_purchase_signal() -> void:
	AdsManager._ads_removed = false
	var menu: Control = _make_menu()
	var lbl: Label = menu.get_node("VersionLabel") as Label
	# Sanity: starts shifted up.
	assert_almost_eq(lbl.offset_top, VERSION_TOP_DEFAULT - BANNER_PX, 0.5)
	# Simulate purchase completion.
	AdsManager._ads_removed = true
	AdsManager.no_ads_purchased.emit()
	assert_almost_eq(lbl.offset_top, VERSION_TOP_DEFAULT, 0.5,
		"MainMenu should restore the default offset when the banner goes away")
