extends Node

# Builds a global Theme on startup and assigns it to the scene root so
# every Control inherits sensible defaults (colors, font sizes, button
# styles). Screens that want a special look use Godot 4's `theme_type_
# variation` instead of per-property overrides.
#
# Available variations:
#   Labels:   DisplayLabel, TitleLabel, SectionLabel, BodyLabel,
#             ValueLabel, CaptionLabel, MutedLabel
#   Buttons:  PrimaryButton, SecondaryButton, DangerButton, IconButton
#   Panels:   DarkPanel
#   Misc:     GoldSeparator (HSeparator)
#
# Usage in a screen:
#   var lbl := Label.new()
#   lbl.theme_type_variation = "SectionLabel"
#   lbl.text = "Прогрес"
#
# That's it — no per-property overrides, no StyleBox-in-code.

const PaletteRef := preload("res://scripts/ui/Palette.gd")

# Standard font-size scale (5 levels — keep in sync with the GDD).
const SIZE_DISPLAY := 48
const SIZE_TITLE   := 32
const SIZE_SECTION := 24
const SIZE_BODY    := 18
const SIZE_CAPTION := 14

var theme: Theme = null

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	theme = build_theme()
	var tree := get_tree()
	if tree and tree.root:
		tree.root.theme = theme


# ── Public — build a fresh Theme (also used by tests) ─────────────────────────

func build_theme() -> Theme:
	var t := Theme.new()
	_add_label_variants(t)
	_add_button_variants(t)
	_add_panel_variants(t)
	_add_separator(t)
	return t


# ── Label variants ────────────────────────────────────────────────────────────

func _add_label_variants(t: Theme) -> void:
	# Default Label — body text colour + size.
	t.set_color("font_color", "Label", PaletteRef.TEXT_PRIMARY)
	t.set_font_size("font_size", "Label", SIZE_BODY)
	# Variations
	_label_variant(t, "DisplayLabel", SIZE_DISPLAY, PaletteRef.TEXT_DISPLAY)
	_label_variant(t, "TitleLabel",   SIZE_TITLE,   PaletteRef.GOLD)
	_label_variant(t, "SectionLabel", SIZE_SECTION, PaletteRef.GOLD)
	_label_variant(t, "BodyLabel",    SIZE_BODY,    PaletteRef.TEXT_SECONDARY)
	_label_variant(t, "ValueLabel",   SIZE_BODY,    PaletteRef.TEXT_DISPLAY)
	_label_variant(t, "CaptionLabel", SIZE_CAPTION, PaletteRef.TEXT_MUTED)
	_label_variant(t, "MutedLabel",   SIZE_BODY,    PaletteRef.TEXT_MUTED)


func _label_variant(t: Theme, variation_name: String, size: int, color: Color) -> void:
	t.set_type_variation(variation_name, "Label")
	t.set_color("font_color", variation_name, color)
	t.set_font_size("font_size", variation_name, size)


# ── Button variants ───────────────────────────────────────────────────────────

func _add_button_variants(t: Theme) -> void:
	# Base Button — neutral panel-style. Most non-CTA buttons inherit this.
	_button_style(t, "Button",
			PaletteRef.BG_PANEL, PaletteRef.BG_PANEL_HOVER, PaletteRef.BG_PANEL_PRESSED,
			PaletteRef.BORDER_NEUTRAL, PaletteRef.BORDER_HOVER, PaletteRef.TEXT_SECONDARY)
	# Variations
	_button_variant(t, "PrimaryButton",
			PaletteRef.BTN_PRIMARY_BG, PaletteRef.BTN_PRIMARY_BG_H, PaletteRef.BTN_PRIMARY_BG_P,
			PaletteRef.BORDER_PRIMARY, PaletteRef.BORDER_PRIMARY_H, PaletteRef.ACCENT_ORANGE)
	_button_variant(t, "SecondaryButton",
			PaletteRef.BG_PANEL, PaletteRef.BG_PANEL_HOVER, PaletteRef.BG_PANEL_PRESSED,
			PaletteRef.BORDER_NEUTRAL, PaletteRef.BORDER_HOVER, PaletteRef.TEXT_SECONDARY)
	_button_variant(t, "DangerButton",
			PaletteRef.BTN_DANGER_BG, PaletteRef.HELL_RED_DIM, PaletteRef.BG_BLACK,
			PaletteRef.HELL_RED_DIM, PaletteRef.HELL_RED, PaletteRef.DANGER)
	_icon_button(t, "IconButton")


# Helper: applies styles to a base type or a variation. For variations
# it also registers the inheritance via set_type_variation.
func _button_variant(t: Theme, name: String,
		bg_n: Color, bg_h: Color, bg_p: Color,
		border_n: Color, border_h: Color, text: Color) -> void:
	t.set_type_variation(name, "Button")
	_button_style(t, name, bg_n, bg_h, bg_p, border_n, border_h, text)


func _button_style(t: Theme, name: String,
		bg_n: Color, bg_h: Color, bg_p: Color,
		border_n: Color, border_h: Color, text: Color) -> void:
	t.set_stylebox("normal",  name, _make_box(bg_n, border_n))
	t.set_stylebox("hover",   name, _make_box(bg_h, border_h))
	t.set_stylebox("pressed", name, _make_box(bg_p, border_n))
	t.set_stylebox("focus",   name, _make_box(bg_n, border_n))
	t.set_color("font_color",       name, text)
	t.set_color("font_hover_color", name, text.lightened(0.15))
	t.set_color("font_pressed_color", name, text.darkened(0.10))
	t.set_font_size("font_size", name, SIZE_BODY)


func _icon_button(t: Theme, name: String) -> void:
	t.set_type_variation(name, "Button")
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(state, name, empty)
	t.set_color("font_color",       name, PaletteRef.TEXT_MUTED)
	t.set_color("font_hover_color", name, PaletteRef.TEXT_PRIMARY)
	t.set_font_size("font_size", name, SIZE_TITLE)


# ── Panels ────────────────────────────────────────────────────────────────────

func _add_panel_variants(t: Theme) -> void:
	var dark := _make_box(PaletteRef.BG_DARKER, PaletteRef.BORDER_NEUTRAL)
	t.set_stylebox("panel", "PanelContainer", dark)
	t.set_type_variation("DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", dark)


# ── Separator ─────────────────────────────────────────────────────────────────

func _add_separator(t: Theme) -> void:
	var sep := StyleBoxFlat.new()
	sep.bg_color = PaletteRef.BORDER_DIM
	sep.content_margin_top = 1.0
	sep.content_margin_bottom = 1.0
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_type_variation("GoldSeparator", "HSeparator")
	t.set_stylebox("separator", "GoldSeparator", sep)


# ── StyleBox factory ──────────────────────────────────────────────────────────

func _make_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left   = 1
	sb.border_width_right  = 1
	sb.border_width_top    = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left    = 10
	sb.corner_radius_top_right   = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left   = 16.0
	sb.content_margin_right  = 16.0
	sb.content_margin_top    = 10.0
	sb.content_margin_bottom = 10.0
	return sb
