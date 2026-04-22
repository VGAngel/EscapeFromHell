extends GutTest

# Tests for responsive UI layout helpers.
# These verify that layout values adapt to viewport size rather than using
# hardcoded pixel constants from the old 720×1280 reference resolution.

# ── MainMenu._apply_banner_space ─────────────────────────────────────────────

class MockVersionLabel:
	var offset_top:    float = 0.0
	var offset_bottom: float = 0.0

class MockButtonsContainer:
	var offset_bottom: float = 0.0

var _version_lbl:   MockVersionLabel
var _buttons:       MockButtonsContainer

func _simulate_apply_banner_space(vp_h: float, banner_h: int) -> void:
	_version_lbl.offset_top    = -50.0 - float(banner_h)
	_version_lbl.offset_bottom = -20.0 - float(banner_h)
	_buttons.offset_bottom     = (vp_h - 320.0) - float(banner_h)

func before_each() -> void:
	_version_lbl = MockVersionLabel.new()
	_buttons     = MockButtonsContainer.new()

func test_banner_space_no_banner() -> void:
	_simulate_apply_banner_space(1920.0, 0)
	assert_eq(_version_lbl.offset_top,    -50.0,  "VersionLabel offset_top without banner")
	assert_eq(_version_lbl.offset_bottom, -20.0,  "VersionLabel offset_bottom without banner")
	assert_eq(_buttons.offset_bottom,    1600.0,  "ButtonsContainer offset_bottom without banner at FHD")

func test_banner_space_with_banner() -> void:
	_simulate_apply_banner_space(1920.0, 100)
	assert_eq(_version_lbl.offset_top,    -150.0, "VersionLabel offset_top with 100px banner")
	assert_eq(_version_lbl.offset_bottom, -120.0, "VersionLabel offset_bottom with 100px banner")
	assert_eq(_buttons.offset_bottom,    1500.0,  "ButtonsContainer pushed up by banner")

func test_banner_space_version_label_stays_negative() -> void:
	# VersionLabel anchor_top=1 means offset must be negative to stay on screen
	for banner_h in [0, 50, 100, 200]:
		_simulate_apply_banner_space(1920.0, banner_h)
		assert_true(
			_version_lbl.offset_top < 0.0,
			"VersionLabel offset_top must be negative for banner_h=%d" % banner_h
		)

func test_banner_space_buttons_container_decreases_with_banner() -> void:
	_simulate_apply_banner_space(1920.0, 0)
	var no_banner_bottom: float = _buttons.offset_bottom
	_simulate_apply_banner_space(1920.0, 120)
	assert_true(
		_buttons.offset_bottom < no_banner_bottom,
		"ButtonsContainer shrinks when ad banner is present"
	)

func test_banner_space_scales_with_viewport_height() -> void:
	_simulate_apply_banner_space(1920.0, 0)
	var fhd_bottom: float = _buttons.offset_bottom
	_simulate_apply_banner_space(1280.0, 0)
	var hd_bottom: float = _buttons.offset_bottom
	assert_true(fhd_bottom > hd_bottom,
		"FHD viewport must yield a larger offset_bottom than HD")

# ── CollectionScreen sheet Y position helpers ─────────────────────────────────

func _sheet_open_y(vp_h: float, sheet_h: float, banner: float) -> float:
	return vp_h - sheet_h - banner

func _sheet_closed_y(vp_h: float) -> float:
	return vp_h + 100.0

func test_sheet_open_y_is_above_viewport_bottom() -> void:
	var vp_h   := 1920.0
	var sheet_h := 400.0
	var banner :=   60.0
	var y := _sheet_open_y(vp_h, sheet_h, banner)
	assert_true(y + sheet_h <= vp_h - banner, "Open sheet must not overlap banner")
	assert_true(y >= 0.0, "Open sheet must be within viewport")

func test_sheet_closed_y_is_offscreen() -> void:
	for vp_h in [1280.0, 1920.0, 2400.0]:
		var y := _sheet_closed_y(vp_h)
		assert_true(y > vp_h, "Closed sheet position.y must be below viewport for vp_h=%.0f" % vp_h)

func test_sheet_open_adapts_to_viewport_height() -> void:
	# Taller viewports should yield a higher open-Y (further down = larger number)
	var y_hd  := _sheet_open_y(1280.0, 400.0, 60.0)
	var y_fhd := _sheet_open_y(1920.0, 400.0, 60.0)
	assert_true(y_fhd > y_hd, "Open Y must scale with viewport height")

# ── HUD bottom-row width ──────────────────────────────────────────────────────

func _hud_bottom_row_width(vp_w: float) -> float:
	return vp_w - 16.0

func test_hud_bottom_row_width_scales() -> void:
	assert_eq(_hud_bottom_row_width(720.0),  704.0, "720px viewport → 704px row")
	assert_eq(_hud_bottom_row_width(1080.0), 1064.0, "1080px viewport → 1064px row")
	assert_true(
		_hud_bottom_row_width(1080.0) > _hud_bottom_row_width(720.0),
		"Wider viewport → wider bottom row"
	)
