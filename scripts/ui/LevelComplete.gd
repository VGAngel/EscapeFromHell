extends CanvasLayer

# Attach to a CanvasLayer (layer = 10) inside Level.tscn.
# Show via show_results(stats) called by GameManager after level_completed signal.
#
# Expected stats Dictionary keys (from GameManager.complete_level):
#   level_id, circle, souls_found, souls_total, deaths,
#   sin_delta, sin_total, light_earned, time_seconds, stars

signal next_level_pressed
signal hub_pressed

# ── Constants ─────────────────────────────────────────────────────────────────
const FADE_DURATION      := 0.5
const STAR_DELAY         := 0.3
const STAT_DELAY         := 0.2
const STAR_FILLED        := "★"
const STAR_EMPTY         := "☆"

# ── Nodes ─────────────────────────────────────────────────────────────────────
var _root:         ColorRect      = null
var _panel:        PanelContainer = null
var _vbox:         VBoxContainer  = null

var _lbl_title:    Label          = null
var _lbl_subtitle: Label          = null
var _stars_row:    HBoxContainer  = null

var _stat_souls:   Label          = null
var _stat_deaths:  Label          = null
var _stat_sin:     Label          = null
var _stat_light:   Label          = null
var _stat_time:    Label          = null
var _stat_best:    Label          = null
var _new_best_badge: Label        = null

var _btn_hub:      Button         = null
var _btn_next:     Button         = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_build_ui()
	_root.modulate.a = 0.0
	visible    = false

# ── Public ────────────────────────────────────────────────────────────────────

func show_results(stats: Dictionary) -> void:
	visible = true
	_fill_static(stats)
	_animate_in(stats)

# ── Fill data ─────────────────────────────────────────────────────────────────

func _fill_static(stats: Dictionary) -> void:
	var circle:  int   = stats.get("circle",      1)
	var level:   int   = stats.get("level_id",    1)
	var found:   int   = stats.get("souls_found",  0)
	var total:   int   = stats.get("souls_total",  0)
	var deaths:  int   = stats.get("deaths",       0)
	var sin_d:   float = stats.get("sin_delta",    0.0)
	var sin_t:   float = stats.get("sin_total",    0.0)
	var light:   int   = stats.get("light_earned", 0)
	_lbl_subtitle.text = "Коло %d • Рівень %d" % [circle, level]

	# Stars — hidden until animation
	var star_labels: Array = _stars_row.get_children()
	for i in star_labels.size():
		star_labels[i].text = STAR_EMPTY
		star_labels[i].modulate.a = 0.4

	# Stats — hidden until animation
	_stat_souls.text  = "👻  Душі:    %d / %d" % [found, total]
	_stat_deaths.text = "💀  Смерті:  %d"      % deaths
	var sin_sign: String = "+" if sin_d >= 0.0 else ""
	_stat_sin.text    = "😈  Гріх:    %s%.0f%%  →  %.0f%%" % [sin_sign, sin_d, sin_t]
	_stat_light.text  = "💡  +%d Світла" % light

	# Time + previous best (if any)
	var elapsed: float = stats.get("time_seconds", 0.0)
	_stat_time.text    = "⏱  Час:     %s" % _format_time(elapsed)

	var prev_best: Dictionary = stats.get("previous_best", {})
	var new_best:  Dictionary = stats.get("new_best", {})
	if prev_best.is_empty():
		_stat_best.text = "🏆  Рекорд:   —"
	else:
		var pb_time:  float = float(prev_best.get("time", 0.0))
		var pb_stars: int   = int(prev_best.get("stars", 0))
		_stat_best.text = "🏆  Рекорд:   %s   %s" % [_format_time(pb_time), _stars_str(pb_stars)]

	if _new_best_badge:
		_new_best_badge.visible = not new_best.is_empty()

	for node in [_stat_souls, _stat_deaths, _stat_time, _stat_best, _stat_sin, _stat_light]:
		node.modulate.a = 0.0

	_btn_hub.modulate.a  = 0.0
	_btn_next.modulate.a = 0.0

func _format_time(seconds: float) -> String:
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]

func _stars_str(n: int) -> String:
	var out := ""
	for i in 3:
		out += STAR_FILLED if i < n else STAR_EMPTY
	return out

# ── Animation sequence ────────────────────────────────────────────────────────

func _animate_in(stats: Dictionary) -> void:
	var stars: int = stats.get("stars", 1)

	# 1. Fade in overlay + panel
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

	# 2. Stars appear one by one
	var star_labels: Array = _stars_row.get_children()
	for i in 3:
		var filled: bool = i < stars
		tw.tween_interval(STAR_DELAY)
		tw.tween_callback(_reveal_star.bind(star_labels[i], filled))

	# 3. Stats slide in
	var stat_nodes := [_stat_souls, _stat_deaths, _stat_time, _stat_best, _stat_sin, _stat_light]
	for node in stat_nodes:
		tw.tween_interval(STAT_DELAY)
		tw.tween_property(node, "modulate:a", 1.0, 0.25)

	# 4. Buttons appear
	tw.tween_interval(0.15)
	tw.tween_property(_btn_hub,  "modulate:a", 1.0, 0.2)
	tw.tween_property(_btn_next, "modulate:a", 1.0, 0.2)

func _reveal_star(lbl: Label, filled: bool) -> void:
	lbl.text = STAR_FILLED if filled else STAR_EMPTY
	lbl.modulate.a = 1.0 if filled else 0.35
	if filled:
		var tw := create_tween()
		tw.tween_property(lbl, "scale", Vector2(1.4, 1.4), 0.12)
		tw.tween_property(lbl, "scale", Vector2.ONE, 0.12)

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_hub_pressed() -> void:
	hub_pressed.emit()
	GameManager.load_hub()

func _on_next_pressed() -> void:
	next_level_pressed.emit()
	GameManager.load_next_level()

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dim overlay
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.67)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# CenterContainer fills the screen and auto-centers the panel inside it.
	# This keeps the panel itself centered (PanelContainer + PRESET_CENTER
	# only anchors its top-left corner to the screen midpoint, leaving the
	# panel offset down-right of center).
	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(centerer)

	_panel = PanelContainer.new()
	# Sized for readability across phones / desktops. CenterContainer keeps
	# this floating in the visual middle regardless of viewport size.
	_panel.custom_minimum_size = Vector2(640, 560)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.09, 0.97)
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.55, 0.48, 0.22)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, 20)
	style.content_margin_left   = 44.0
	style.content_margin_right  = 44.0
	style.content_margin_top    = 44.0
	style.content_margin_bottom = 44.0
	_panel.add_theme_stylebox_override("panel", style)
	centerer.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 22)
	_panel.add_child(_vbox)

	_build_header()
	_add_separator()
	_build_stars()
	_add_separator()
	_build_stats()
	_add_separator()
	_build_buttons()

func _build_header() -> void:
	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = "TitleLabel"
	_lbl_title.text = "РІВЕНЬ ПРОЙДЕНО"
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_lbl_title)

	_lbl_subtitle = Label.new()
	_lbl_subtitle.theme_type_variation = "MutedLabel"
	_lbl_subtitle.text = ""
	_lbl_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(_lbl_subtitle)

func _build_stars() -> void:
	_stars_row = HBoxContainer.new()
	_stars_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_stars_row.add_theme_constant_override("separation", 16)
	_vbox.add_child(_stars_row)

	for _i in 3:
		var lbl := Label.new()
		lbl.text = STAR_EMPTY
		# Stars are pictographic — use big DisplayLabel size for impact.
		lbl.add_theme_font_size_override("font_size", 56)
		lbl.add_theme_color_override("font_color", Color("#FFD700"))
		lbl.pivot_offset = Vector2(28, 28)
		_stars_row.add_child(lbl)

func _build_stats() -> void:
	var stat_vbox := VBoxContainer.new()
	stat_vbox.add_theme_constant_override("separation", 12)
	_vbox.add_child(stat_vbox)

	_stat_souls  = _make_stat_label("")
	_stat_deaths = _make_stat_label("")
	_stat_time   = _make_stat_label("")
	_stat_best   = _make_stat_label("")
	_stat_sin    = _make_stat_label("")
	_stat_light  = _make_stat_label("")

	_stat_light.add_theme_color_override("font_color", Color("#FFD060"))
	_stat_best.add_theme_color_override("font_color",  Color("#FFD700"))

	for lbl in [_stat_souls, _stat_deaths, _stat_time, _stat_best, _stat_sin, _stat_light]:
		stat_vbox.add_child(lbl)

	# "NEW BEST!" badge sits next to the stars row, hidden by default.
	_new_best_badge = Label.new()
	_new_best_badge.theme_type_variation = "BodyLabel"
	_new_best_badge.text = "✨ НОВИЙ РЕКОРД ✨"
	_new_best_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Override BodyLabel grey with celebratory gold + outline.
	_new_best_badge.add_theme_color_override("font_color", Color("#FFD700"))
	_new_best_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_new_best_badge.add_theme_constant_override("outline_size", 4)
	_new_best_badge.visible = false
	stat_vbox.add_child(_new_best_badge)

func _build_buttons() -> void:
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	_vbox.add_child(btn_row)

	_btn_hub  = _make_button("Хаб Раю",  false)
	_btn_next = _make_button("Далі →",   true)
	_btn_hub.custom_minimum_size  = Vector2(220, 64)
	_btn_next.custom_minimum_size = Vector2(220, 64)

	_btn_hub.pressed.connect(_on_hub_pressed)
	_btn_next.pressed.connect(_on_next_pressed)

	btn_row.add_child(_btn_hub)
	btn_row.add_child(_btn_next)

# ── UI helpers ────────────────────────────────────────────────────────────────

func _make_stat_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = "BodyLabel"
	lbl.text = text
	# BodyLabel ships TEXT_SECONDARY by default — close to the previous tone.
	return lbl

func _make_button(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(220, 64)
	# Default Button theme size is SIZE_BODY (18); LevelComplete previously
	# used 22 — keep the slightly larger feel for the win-screen CTAs.
	btn.add_theme_font_size_override("font_size", 22)

	var normal := StyleBoxFlat.new()
	var hover  := StyleBoxFlat.new()
	var press  := StyleBoxFlat.new()
	for s in [normal, hover, press]:
		s.corner_radius_top_left    = 10
		s.corner_radius_top_right   = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10

	if primary:
		normal.bg_color = Color(0.22, 0.19, 0.32)
		hover.bg_color  = Color(0.32, 0.28, 0.46)
		press.bg_color  = Color(0.16, 0.14, 0.24)
		btn.add_theme_color_override("font_color", Color("#E8DEFF"))
	else:
		normal.bg_color = Color(0.13, 0.12, 0.16)
		hover.bg_color  = Color(0.20, 0.18, 0.24)
		press.bg_color  = Color(0.09, 0.08, 0.12)
		btn.add_theme_color_override("font_color", Color(0.75, 0.73, 0.78))

	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", press)
	btn.add_theme_stylebox_override("focus",   normal)
	return btn

func _add_separator() -> void:
	var sep := HSeparator.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.32, 0.27, 0.18)
	s.content_margin_top    = 1.0
	s.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", s)
	_vbox.add_child(sep)
