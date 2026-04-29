extends CanvasLayer

# Attach to a CanvasLayer (layer = 10) added as child of Level.tscn.
# Open/close via toggle() or connect to HUD.pause_requested.
#
# Signals
signal resumed
signal settings_requested
signal collection_requested
signal statistics_requested

# ── Constants ─────────────────────────────────────────────────────────────────
const FADE_DURATION  := 0.2
const SIN_COLORS := [
	Color("#FFFFFF"),
	Color("#FFAA00"),
	Color("#FF4400"),
	Color("#AA0000"),
]
const SIN_THRESHOLDS := [0, 30, 60, 85]

# ── UI Nodes (built in code) ──────────────────────────────────────────────────
var _root:          ColorRect   = null
var _panel:         PanelContainer = null

var _lbl_title:     Label       = null
var _lbl_level:     Label       = null
var _lbl_souls:     Label       = null
var _sin_bar_bg:    ColorRect   = null
var _sin_bar:       ColorRect   = null
var _lbl_sin_pct:   Label       = null

var _btn_resume:    Button      = null
var _btn_collection: Button     = null
var _btn_statistics: Button     = null
var _btn_settings:  Button      = null
var _btn_menu:      Button      = null

# Confirmation sub-panel
var _confirm_panel:  PanelContainer = null
var _lbl_exit_title: Label      = null
var _lbl_exit_msg:   Label      = null
var _btn_exit_yes:   Button      = null
var _btn_exit_no:    Button      = null

# ── State ─────────────────────────────────────────────────────────────────────
var _visible_flag: bool = false
var _tween:        Tween = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	_confirm_panel.visible = false
	# Live refresh on language switch from Settings.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	# Re-apply all the dynamic strings; build-once labels are reset below.
	if _lbl_title:
		_lbl_title.text = _t("pause.title", {}, "ПАУЗА")
	if _btn_resume:
		_btn_resume.text = _t("pause.resume", {}, "Продовжити")
	if _btn_collection:
		_btn_collection.text = _t("pause.collection", {}, "Врятовані Душі")
	if _btn_statistics:
		_btn_statistics.text = _t("pause.statistics", {}, "📊  Статистика")
	if _btn_settings:
		_btn_settings.text = _t("pause.settings", {}, "Налаштування")
	if _btn_menu:
		_btn_menu.text = _t("pause.main_menu", {}, "Головне Меню")
	if _lbl_exit_title:
		_lbl_exit_title.text = _t("pause.exit_title", {}, "Вийти з рівня?")
	if _lbl_exit_msg:
		_lbl_exit_msg.text = _t(
				"pause.exit_message", {},
				"Зібрані душі збережені.\nДуша в руках — буде втрачена.")
	if _btn_exit_yes:
		_btn_exit_yes.text = _t("pause.exit_yes", {}, "Вийти")
	if _btn_exit_no:
		_btn_exit_no.text = _t("pause.exit_no", {}, "Залишитись")
	# Stat labels refresh every time the screen opens; safe to re-run now too.
	if _visible_flag:
		_refresh_stats()

# ── Public ────────────────────────────────────────────────────────────────────

func toggle() -> void:
	if _visible_flag:
		close()
	else:
		open()

func open() -> void:
	if _visible_flag:
		return
	_visible_flag = true
	get_tree().paused = true
	_refresh_stats()
	_confirm_panel.visible = false
	visible = true
	_animate_in()
	if SoundManager:
		SoundManager.play_sfx("ui", "pause_open")

func close() -> void:
	if not _visible_flag:
		return
	_visible_flag = false
	get_tree().paused = false
	_animate_out()
	resumed.emit()
	if SoundManager:
		SoundManager.play_sfx("ui", "pause_close")

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _visible_flag:
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirm_panel.visible:
			_confirm_panel.visible = false
		else:
			close()
		get_viewport().set_input_as_handled()

# ── Stats refresh ─────────────────────────────────────────────────────────────

func _refresh_stats() -> void:
	var circle := GameManager.current_circle if GameManager else 1
	var level  := GameManager.current_level_id if GameManager else 1
	_lbl_level.text = _t("pause.level_format",
			{"circle": circle, "level": level}, "Коло %d • Рівень %d" % [circle, level])

	var souls := SaveManager.get_total_souls() if SaveManager else 0
	_lbl_souls.text = _t("pause.souls_format",
			{"found": souls}, "👻 %d / 100" % souls)

	var sin_val := SaveManager.get_sin() if SaveManager else 0.0
	_set_sin(sin_val)

func _set_sin(value: float) -> void:
	var ratio := clampf(value / 100.0, 0.0, 1.0)
	_sin_bar.size.x = 220.0 * ratio
	_sin_bar.color = _sin_color(value)
	_lbl_sin_pct.text = _t("pause.sin_format",
			{"pct": int(value)}, "%.0f%%" % value)


# Helper — Loc.t() with a guaranteed fallback so headless tests / boot
# scenarios without the autoload still render correctly.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func _sin_color(val: float) -> Color:
	var col := SIN_COLORS[0]
	for i in SIN_THRESHOLDS.size():
		if val >= SIN_THRESHOLDS[i]:
			col = SIN_COLORS[i]
	return col

# ── Animation ─────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func _animate_out() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	_tween.tween_callback(func() -> void: visible = false)

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_resume_pressed() -> void:
	close()

func _on_collection_pressed() -> void:
	collection_requested.emit()

func _on_statistics_pressed() -> void:
	statistics_requested.emit()

func _on_settings_pressed() -> void:
	settings_requested.emit()

func _on_menu_pressed() -> void:
	_confirm_panel.visible = true

func _on_exit_yes_pressed() -> void:
	_confirm_panel.visible = false
	get_tree().paused = false
	_visible_flag = false
	visible = false
	GameManager.load_main_menu()

func _on_exit_no_pressed() -> void:
	_confirm_panel.visible = false

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dim overlay
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.55)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	# Force ALWAYS so children remain interactive while get_tree().paused = true.
	# CanvasLayer already sets this in _ready, but applying it here too removes
	# any chance of an inherited-mode regression from a future scene refactor.
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	# CenterContainer fills the screen and re-centers its child whenever
	# the viewport size changes (resolution switch, orientation change).
	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	centerer.process_mode = Node.PROCESS_MODE_ALWAYS
	_root.add_child(centerer)

	# Central panel — sized for 1080×1920 portrait (≈70% width).
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(760, 0)
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var style := StyleBoxFlat.new()
	style.bg_color        = Color(0.08, 0.06, 0.10, 0.96)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color    = Color(0.35, 0.28, 0.45)
	style.corner_radius_top_left    = 16
	style.corner_radius_top_right   = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left   = 40.0
	style.content_margin_right  = 40.0
	style.content_margin_top    = 44.0
	style.content_margin_bottom = 44.0
	_panel.add_theme_stylebox_override("panel", style)
	centerer.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	_panel.add_child(vbox)

	# Title — DisplayLabel variation (48 px gold + outline).
	_lbl_title = Label.new()
	_lbl_title.theme_type_variation = "DisplayLabel"
	_lbl_title.text = _t("pause.title", {}, "ПАУЗА")
	_lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_lbl_title)

	_add_separator(vbox)

	# Stats
	_lbl_level = _make_stat_label("")
	vbox.add_child(_lbl_level)

	_lbl_souls = _make_stat_label("")
	vbox.add_child(_lbl_souls)

	# Mini sin bar
	var sin_row := HBoxContainer.new()
	sin_row.add_theme_constant_override("separation", 8)
	vbox.add_child(sin_row)

	var sin_lbl := Label.new()
	sin_lbl.theme_type_variation = "TitleLabel"
	sin_lbl.text = "😈"
	sin_row.add_child(sin_lbl)

	_sin_bar_bg = ColorRect.new()
	_sin_bar_bg.custom_minimum_size = Vector2(220, 14)
	_sin_bar_bg.color = Color(0.15, 0.15, 0.15)
	_sin_bar_bg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sin_row.add_child(_sin_bar_bg)

	_sin_bar = ColorRect.new()
	_sin_bar.position = Vector2.ZERO
	_sin_bar.size = Vector2(0, 14)
	_sin_bar.color = Color.WHITE
	_sin_bar_bg.add_child(_sin_bar)

	_lbl_sin_pct = Label.new()
	_lbl_sin_pct.theme_type_variation = "SectionLabel"
	_lbl_sin_pct.text = "0%"
	_lbl_sin_pct.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sin_row.add_child(_lbl_sin_pct)

	_add_separator(vbox)

	# Buttons
	_btn_resume = _make_button(_t("pause.resume", {}, "Продовжити"), true)
	_btn_resume.pressed.connect(_on_resume_pressed)
	vbox.add_child(_btn_resume)

	_btn_collection = _make_button(_t("pause.collection", {}, "Врятовані Душі"), false)
	_btn_collection.pressed.connect(_on_collection_pressed)
	vbox.add_child(_btn_collection)

	_btn_statistics = _make_button(_t("pause.statistics", {}, "📊  Статистика"), false)
	_btn_statistics.pressed.connect(_on_statistics_pressed)
	vbox.add_child(_btn_statistics)

	_btn_settings = _make_button(_t("pause.settings", {}, "Налаштування"), false)
	_btn_settings.pressed.connect(_on_settings_pressed)
	vbox.add_child(_btn_settings)

	_btn_menu = _make_button(_t("pause.main_menu", {}, "Головне Меню"), false, true)
	_btn_menu.pressed.connect(_on_menu_pressed)
	vbox.add_child(_btn_menu)

	_build_confirm_panel()

func _build_confirm_panel() -> void:
	# Wrap in its own CenterContainer so the confirm popup also stays centered
	# (and recenters on resolution change) without inheriting PRESET_CENTER bug.
	# IGNORE so this full-screen overlay never absorbs clicks meant for the
	# main panel's buttons behind it. Children still receive input when the
	# confirm panel is shown, because mouse_filter is per-control.
	var confirm_centerer := CenterContainer.new()
	confirm_centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	confirm_centerer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm_centerer.process_mode = Node.PROCESS_MODE_ALWAYS
	confirm_centerer.z_index = 2
	_root.add_child(confirm_centerer)

	_confirm_panel = PanelContainer.new()
	_confirm_panel.custom_minimum_size = Vector2(640, 0)
	_confirm_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.10, 0.05, 0.06, 0.98)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.20, 0.20)
	style.corner_radius_top_left    = 14
	style.corner_radius_top_right   = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.content_margin_left   = 36.0
	style.content_margin_right  = 36.0
	style.content_margin_top    = 36.0
	style.content_margin_bottom = 36.0
	_confirm_panel.add_theme_stylebox_override("panel", style)
	confirm_centerer.add_child(_confirm_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	_confirm_panel.add_child(vbox)

	_lbl_exit_title = Label.new()
	_lbl_exit_title.theme_type_variation = "TitleLabel"
	_lbl_exit_title.text = _t("pause.exit_title", {}, "Вийти з рівня?")
	_lbl_exit_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_exit_title.add_theme_color_override("font_color", Color("#FF6644"))
	vbox.add_child(_lbl_exit_title)

	_lbl_exit_msg = Label.new()
	_lbl_exit_msg.theme_type_variation = "BodyLabel"
	_lbl_exit_msg.text = _t("pause.exit_message", {}, "Зібрані душі збережені.\nДуша в руках — буде втрачена.")
	_lbl_exit_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_exit_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_lbl_exit_msg)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	_btn_exit_yes = _make_button(_t("pause.exit_yes", {}, "Вийти"), false, true)
	_btn_exit_yes.custom_minimum_size = Vector2(240, 90)
	_btn_exit_yes.pressed.connect(_on_exit_yes_pressed)
	btn_row.add_child(_btn_exit_yes)

	_btn_exit_no = _make_button(_t("pause.exit_no", {}, "Залишитись"), true)
	_btn_exit_no.custom_minimum_size = Vector2(240, 90)
	_btn_exit_no.pressed.connect(_on_exit_no_pressed)
	btn_row.add_child(_btn_exit_no)

# ── UI helpers ────────────────────────────────────────────────────────────────

func _make_button(text: String, primary: bool, danger: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(540, 96)
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	# Larger CTA size — kept inline because PauseScreen buttons are
	# physically big touch targets, larger than the standard SIZE_BODY.
	btn.add_theme_font_size_override("font_size", 32)

	var normal := StyleBoxFlat.new()
	var hover  := StyleBoxFlat.new()
	var press  := StyleBoxFlat.new()
	for s in [normal, hover, press]:
		s.corner_radius_top_left    = 10
		s.corner_radius_top_right   = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10

	if danger:
		normal.bg_color = Color(0.30, 0.08, 0.08)
		hover.bg_color  = Color(0.45, 0.12, 0.12)
		press.bg_color  = Color(0.22, 0.05, 0.05)
		btn.add_theme_color_override("font_color", Color("#FF8866"))
	elif primary:
		normal.bg_color = Color(0.20, 0.18, 0.30)
		hover.bg_color  = Color(0.30, 0.26, 0.44)
		press.bg_color  = Color(0.15, 0.13, 0.22)
		btn.add_theme_color_override("font_color", Color("#E8DEFF"))
	else:
		normal.bg_color = Color(0.13, 0.12, 0.16)
		hover.bg_color  = Color(0.20, 0.18, 0.24)
		press.bg_color  = Color(0.09, 0.08, 0.12)
		btn.add_theme_color_override("font_color", Color(0.80, 0.78, 0.82))

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  press)
	btn.add_theme_stylebox_override("focus",    normal)
	return btn

func _make_stat_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.theme_type_variation = "SectionLabel"
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Override gold from SectionLabel — stats want neutral grey, not accent.
	lbl.add_theme_color_override("font_color", Color(0.78, 0.76, 0.80))
	return lbl

func _add_separator(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.30, 0.25, 0.38)
	sep_style.content_margin_top    = 1.0
	sep_style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)
