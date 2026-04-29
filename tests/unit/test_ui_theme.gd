extends GutTest

# Tests for UITheme + Palette — the global theme builder.
#
# Verifies:
#   • all expected variations exist with the right base type
#   • size constants form an ascending scale
#   • Palette colours flow into the theme as expected
#   • the autoload-style builder doesn't crash standalone

const UIThemeScript := preload("res://scripts/ui/UITheme.gd")
const PaletteScript := preload("res://scripts/ui/Palette.gd")

var theme_node: Node
var t: Theme

func before_each() -> void:
	theme_node = UIThemeScript.new()
	add_child_autofree(theme_node)
	t = theme_node.build_theme()

# ── Label variations ──────────────────────────────────────────────────────────

func test_label_variants_inherit_from_label() -> void:
	for variation_name in [
		"DisplayLabel", "TitleLabel", "SectionLabel",
		"BodyLabel", "ValueLabel", "CaptionLabel", "MutedLabel",
	]:
		assert_eq(t.get_type_variation_base(variation_name), "Label",
				"%s should inherit from Label" % variation_name)
		assert_true(t.has_color("font_color", variation_name),
				"%s should have font_color" % variation_name)
		assert_true(t.has_font_size("font_size", variation_name),
				"%s should have font_size" % variation_name)

func test_default_label_uses_palette_text_primary() -> void:
	assert_eq(t.get_color("font_color", "Label"), PaletteScript.TEXT_PRIMARY)

func test_section_label_is_gold() -> void:
	assert_eq(t.get_color("font_color", "SectionLabel"), PaletteScript.GOLD)

# ── Button variations ─────────────────────────────────────────────────────────

func test_button_variants_inherit_from_button() -> void:
	for name in ["PrimaryButton", "SecondaryButton", "DangerButton", "IconButton"]:
		assert_eq(t.get_type_variation_base(name), "Button",
				"%s should inherit from Button" % name)
		for state in ["normal", "hover", "pressed", "focus"]:
			assert_true(t.has_stylebox(state, name),
					"%s should have %s stylebox" % [name, state])

func test_icon_button_uses_empty_stylebox() -> void:
	var sb: StyleBox = t.get_stylebox("normal", "IconButton")
	assert_true(sb is StyleBoxEmpty,
			"IconButton.normal should be StyleBoxEmpty for transparent look")

func test_primary_button_text_is_orange_accent() -> void:
	assert_eq(t.get_color("font_color", "PrimaryButton"),
			PaletteScript.ACCENT_ORANGE)

# ── Panel + separator ─────────────────────────────────────────────────────────

func test_dark_panel_inherits_from_panel_container() -> void:
	assert_eq(t.get_type_variation_base("DarkPanel"), "PanelContainer")
	assert_true(t.has_stylebox("panel", "DarkPanel"))

func test_gold_separator_inherits_from_hseparator() -> void:
	assert_eq(t.get_type_variation_base("GoldSeparator"), "HSeparator")
	assert_true(t.has_stylebox("separator", "GoldSeparator"))

# ── Size scale ────────────────────────────────────────────────────────────────

func test_size_constants_form_ascending_scale() -> void:
	assert_lt(theme_node.SIZE_CAPTION, theme_node.SIZE_BODY)
	assert_lt(theme_node.SIZE_BODY,    theme_node.SIZE_SECTION)
	assert_lt(theme_node.SIZE_SECTION, theme_node.SIZE_TITLE)
	assert_lt(theme_node.SIZE_TITLE,   theme_node.SIZE_DISPLAY)

func test_default_label_uses_size_body() -> void:
	assert_eq(t.get_font_size("font_size", "Label"), theme_node.SIZE_BODY)

# ── Display-font typography polish (outline on hero variations) ───────────────

func test_display_label_has_outline() -> void:
	# DisplayLabel + TitleLabel get an outline_size constant so the
	# default sans font reads as a "display" cut without a separate
	# font asset.
	assert_true(t.has_constant("outline_size", "DisplayLabel"),
			"DisplayLabel should ship an outline_size constant")
	assert_gt(t.get_constant("outline_size", "DisplayLabel"), 0)
	assert_true(t.has_constant("outline_size", "TitleLabel"))

func test_body_label_has_no_outline() -> void:
	# Body-tier text stays clean — outline would muddy small sizes.
	assert_false(t.has_constant("outline_size", "BodyLabel"),
			"BodyLabel should not have an outline")
	assert_false(t.has_constant("outline_size", "CaptionLabel"))

# ── Palette sanity ────────────────────────────────────────────────────────────

func test_palette_colours_are_distinct() -> void:
	# Sanity check — easy to break by accidental const-renaming.
	assert_ne(PaletteScript.GOLD, PaletteScript.HELL_RED)
	assert_ne(PaletteScript.TEXT_PRIMARY, PaletteScript.TEXT_MUTED)
	assert_ne(PaletteScript.BG_DARK, PaletteScript.BG_PANEL)

# ── Idempotency ───────────────────────────────────────────────────────────────

func test_build_theme_is_pure() -> void:
	var t1: Theme = theme_node.build_theme()
	var t2: Theme = theme_node.build_theme()
	# Different Theme instances but same content for a key entry.
	assert_eq(t1.get_color("font_color", "Label"),
			t2.get_color("font_color", "Label"))
	assert_ne(t1, t2, "should return a fresh Theme each call")
