extends CanvasLayer

# Brief panel shown when the player picks up a named soul — shows the
# name, age, and epitaph over a dimmed background. Auto-dismisses after
# AUTO_HIDE seconds or on input.

const AUTO_HIDE:     float = 3.2
const FADE_DURATION: float = 0.35

var _root:     ColorRect      = null
var _panel:    PanelContainer = null
var _lbl_name: Label          = null
var _lbl_age:  Label          = null
var _lbl_text: Label          = null
var _timer:    float          = 0.0
var _visible:  bool           = false

func _ready() -> void:
	layer = 15
	_build_ui()
	visible = false
	_root.modulate.a = 0.0

func show_soul(data: Dictionary) -> void:
	var soul_name: String = data.get("name", "")
	if soul_name == "":
		return
	var age:     int    = int(data.get("age", 0))
	var epitaph: String = data.get("epitaph", "")

	_lbl_name.text = soul_name
	_lbl_age.text  = "%d років" % age if age > 0 else ""
	_lbl_age.visible = age > 0
	_lbl_text.text = epitaph

	visible = true
	_timer = AUTO_HIDE
	_visible = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func _process(delta: float) -> void:
	if not _visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_hide()

func _unhandled_input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		_hide()
	elif event is InputEventScreenTouch and event.pressed:
		_hide()
	elif event is InputEventMouseButton and event.pressed:
		_hide()

func _hide() -> void:
	if not _visible:
		return
	_visible = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void: visible = false)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# CenterContainer keeps the panel centered and re-centers automatically
	# when the viewport size changes (FHD ↔ HD resolution switch).
	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centerer)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(420, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.06, 0.10, 0.95)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.48, 0.22)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, 14)
	style.content_margin_left   = 24.0
	style.content_margin_right  = 24.0
	style.content_margin_top    = 22.0
	style.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override("panel", style)
	centerer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(vbox)

	var header := Label.new()
	header.text = "Врятована душа"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.62, 0.58, 0.48))
	vbox.add_child(header)

	_lbl_name = Label.new()
	_lbl_name.text = ""
	_lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_name.add_theme_font_size_override("font_size", 24)
	_lbl_name.add_theme_color_override("font_color", Color("#FFD700"))
	vbox.add_child(_lbl_name)

	_lbl_age = Label.new()
	_lbl_age.text = ""
	_lbl_age.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_age.add_theme_font_size_override("font_size", 12)
	_lbl_age.add_theme_color_override("font_color", Color(0.70, 0.68, 0.55))
	vbox.add_child(_lbl_age)

	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.32, 0.27, 0.18)
	sep_style.content_margin_top    = 1.0
	sep_style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	_lbl_text = Label.new()
	_lbl_text.text = ""
	_lbl_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_text.add_theme_font_size_override("font_size", 13)
	_lbl_text.add_theme_color_override("font_color", Color(0.85, 0.82, 0.90))
	_lbl_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_text.custom_minimum_size.x = 370.0
	vbox.add_child(_lbl_text)
