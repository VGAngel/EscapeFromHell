extends CanvasLayer

# Accessible from: main menu, pause menu.
# Persists settings to user://settings.json on every change.
# Call open() / close() from outside.

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const SAVE_PATH     := "user://settings.json"
const FADE_DURATION := 0.25

# Audio bus indices (must match Project > Audio Bus Layout)
const BUS_MASTER := "Master"
const BUS_MUSIC  := "Music"
const BUS_SFX    := "SFX"

# Resolution presets: logical (base) size used by the stretch viewport
const RESOLUTIONS := {
	"fhd": Vector2i(1080, 1920),
	"hd":  Vector2i(720,  1280),
}

# ── Defaults ──────────────────────────────────────────────────────────────────
const DEFAULTS := {
	"volume_master":    80,
	"volume_music":     60,
	"volume_sfx":       90,
	"mute_all":         false,
	"language":         "uk",
	"vsync":            true,
	"resolution":       "fhd",
}

# ── State ─────────────────────────────────────────────────────────────────────
var _data: Dictionary = {}
var _active_tab: int  = 0

# ── UI roots ──────────────────────────────────────────────────────────────────
var _root:          ColorRect      = null
var _panel:         PanelContainer = null

# Tab bar
var _tab_btns:      Array          = []   # Array[Button]
var _tab_pages:     Array          = []   # Array[Control]

# Sound tab widgets
var _sl_master:     HSlider        = null
var _sl_music:      HSlider        = null
var _sl_sfx:        HSlider        = null
var _lbl_master:    Label          = null
var _lbl_music:     Label          = null
var _lbl_sfx:       Label          = null
var _toggle_mute:   Button         = null

# Language tab widgets
var _lang_btns:     Dictionary     = {}   # code → Button

# Graphics tab widgets
var _toggle_vsync:       Button         = null
var _resolution_btns:    Dictionary     = {}   # preset → Button

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_build_ui()
	_apply_all()
	_root.modulate.a = 0.0
	visible    = false

# ── Persist ───────────────────────────────────────────────────────────────────

func _load() -> void:
	_data = DEFAULTS.duplicate()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		for key in parsed:
			_data[key] = parsed[key]

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("SettingsScreen: cannot write " + SAVE_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()

# ── Public ────────────────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_refresh_widgets()
	_switch_tab(0)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit()
	)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ── Apply all settings on startup ─────────────────────────────────────────────

func _apply_all() -> void:
	_apply_volume(BUS_MASTER, _data.get("volume_master", 80))
	_apply_volume(BUS_MUSIC,  _data.get("volume_music",  60))
	_apply_volume(BUS_SFX,    _data.get("volume_sfx",    90))
	_apply_mute(_data.get("mute_all", false))
	_apply_vsync(_data.get("vsync", true))
	_apply_resolution(_data.get("resolution", "fhd"))

# ── Volume helpers ────────────────────────────────────────────────────────────

func _apply_volume(bus_name: String, pct: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(clampf(pct / 100.0, 0.0, 1.0))
	AudioServer.set_bus_volume_db(idx, db)

func _apply_mute(muted: bool) -> void:
	var idx := AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)

func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)

func _apply_resolution(preset: String) -> void:
	var size: Vector2i = RESOLUTIONS.get(preset, RESOLUTIONS["fhd"])
	get_tree().get_root().content_scale_size = size

# ── Widget callbacks ──────────────────────────────────────────────────────────

func _on_master_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_master"] = pct
	_lbl_master.text = "%d%%" % pct
	_apply_volume(BUS_MASTER, pct)
	_save()

func _on_music_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_music"] = pct
	_lbl_music.text = "%d%%" % pct
	_apply_volume(BUS_MUSIC, pct)
	_save()

func _on_sfx_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_sfx"] = pct
	_lbl_sfx.text = "%d%%" % pct
	_apply_volume(BUS_SFX, pct)
	_save()

func _on_mute_pressed() -> void:
	var muted: bool = not _data.get("mute_all", false)
	_data["mute_all"] = muted
	_apply_mute(muted)
	_update_toggle(_toggle_mute, muted)
	_save()

func _on_language_pressed(code: String) -> void:
	_data["language"] = code
	for c in _lang_btns:
		_update_toggle(_lang_btns[c], c == code)
	_save()
	# TODO: hook into Loc autoload when implemented
	# Loc.set_language(code)

func _on_vsync_pressed() -> void:
	var enabled: bool = not _data.get("vsync", true)
	_data["vsync"] = enabled
	_apply_vsync(enabled)
	_update_toggle(_toggle_vsync, enabled)
	_save()

func _on_resolution_pressed(preset: String) -> void:
	_data["resolution"] = preset
	_apply_resolution(preset)
	for p in _resolution_btns:
		_style_choice_btn(_resolution_btns[p], p == preset)
	_save()

# ── Refresh widgets from _data ────────────────────────────────────────────────

func _refresh_widgets() -> void:
	var vm: int  = _data.get("volume_master", 80)
	var vmu: int = _data.get("volume_music",  60)
	var vs: int  = _data.get("volume_sfx",    90)
	var muted: bool = _data.get("mute_all", false)
	var lang: String = _data.get("language", "uk")
	var vsync: bool  = _data.get("vsync", true)
	var res: String  = _data.get("resolution", "fhd")

	_sl_master.value = vm;  _lbl_master.text = "%d%%" % vm
	_sl_music.value  = vmu; _lbl_music.text  = "%d%%" % vmu
	_sl_sfx.value    = vs;  _lbl_sfx.text    = "%d%%" % vs
	_update_toggle(_toggle_mute, muted)

	for code in _lang_btns:
		_update_toggle(_lang_btns[code], code == lang)

	_update_toggle(_toggle_vsync, vsync)

	for preset in _resolution_btns:
		_style_choice_btn(_resolution_btns[preset], preset == res)

# ── Tab switching ─────────────────────────────────────────────────────────────

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	for i in _tab_btns.size():
		_tab_btns[i].modulate = Color.WHITE if i == idx else Color(0.55, 0.53, 0.62)
	for i in _tab_pages.size():
		_tab_pages[i].visible = i == idx

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0, 0, 0, 0.60)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(460, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.11, 0.97)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.30, 0.27, 0.40)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, 16)
	style.content_margin_left   = 0.0
	style.content_margin_right  = 0.0
	style.content_margin_top    = 0.0
	style.content_margin_bottom = 24.0
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	_panel.add_child(vbox)

	_build_title_bar(vbox)
	_build_tab_bar(vbox)
	_build_pages(vbox)

func _build_title_bar(parent: VBoxContainer) -> void:
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 52
	hdr.add_theme_constant_override("separation", 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  20)
	margin.add_theme_constant_override("margin_right",  8)
	margin.add_theme_constant_override("margin_top",    0)
	margin.add_theme_constant_override("margin_bottom", 0)
	parent.add_child(margin)
	margin.add_child(hdr)

	var title := Label.new()
	title.text = "Налаштування"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.95))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(44, 44)
	btn_close.add_theme_font_size_override("font_size", 27)
	var empty := StyleBoxEmpty.new()
	for state in ["normal","hover","pressed","focus"]:
		btn_close.add_theme_stylebox_override(state, empty)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_tab_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.custom_minimum_size.y = 44
	bar.add_theme_constant_override("separation", 2)
	parent.add_child(bar)

	var tabs := [["🔊", "Звук"], ["🌐", "Мова"], ["🖥", "Графіка"]]
	for i in tabs.size():
		var btn := Button.new()
		btn.text = "%s  %s" % [tabs[i][0], tabs[i][1]]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 44
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 20)

		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.12, 0.11, 0.16)
		n.border_width_bottom = 2
		n.border_color = Color(0.0, 0.0, 0.0, 0.0)
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = Color(0.18, 0.16, 0.22)
		btn.add_theme_stylebox_override("normal",  n)
		btn.add_theme_stylebox_override("hover",   h)
		btn.add_theme_stylebox_override("pressed", n)
		btn.add_theme_stylebox_override("focus",   n)
		btn.add_theme_color_override("font_color", Color(0.82, 0.80, 0.88))

		var idx := i
		btn.pressed.connect(func() -> void: _switch_tab(idx))
		bar.add_child(btn)
		_tab_btns.append(btn)

func _build_pages(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top",   18)
	margin.add_theme_constant_override("margin_bottom", 0)
	parent.add_child(margin)

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 240)
	margin.add_child(stack)

	var page_sound    := _build_page_sound()
	var page_language := _build_page_language()
	var page_graphics := _build_page_graphics()

	for page in [page_sound, page_language, page_graphics]:
		page.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(page)
		_tab_pages.append(page)

# ── Sound page ────────────────────────────────────────────────────────────────

func _build_page_sound() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	_sl_master = _add_slider_row(vbox, "Загальна гучність", 80)
	_lbl_master = _get_value_label(vbox)
	_sl_master.value_changed.connect(_on_master_changed)

	_sl_music = _add_slider_row(vbox, "Музика", 60)
	_lbl_music = _get_value_label(vbox)
	_sl_music.value_changed.connect(_on_music_changed)

	_sl_sfx = _add_slider_row(vbox, "Звукові ефекти", 90)
	_lbl_sfx = _get_value_label(vbox)
	_sl_sfx.value_changed.connect(_on_sfx_changed)

	_toggle_mute = _add_toggle_row(vbox, "Вимкнути звук повністю", false)
	_toggle_mute.pressed.connect(_on_mute_pressed)

	return vbox

func _add_slider_row(parent: VBoxContainer, label_text: String, default_val: int) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size.x = 160
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.78, 0.85))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step      = 1
	sl.value     = default_val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_slider(sl)
	row.add_child(sl)

	# value label is added as next sibling — grabbed by _get_value_label
	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % default_val
	val_lbl.custom_minimum_size.x = 38
	val_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 20)
	val_lbl.add_theme_color_override("font_color", Color(0.65, 0.63, 0.72))
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val_lbl)

	return sl

# Returns the value Label that was just added as last child of the last HBoxContainer
func _get_value_label(parent: VBoxContainer) -> Label:
	var row: HBoxContainer = parent.get_child(parent.get_child_count() - 1)
	return row.get_child(row.get_child_count() - 1) as Label

func _style_slider(sl: HSlider) -> void:
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.70, 0.55, 0.90)
	grabber.corner_radius_top_left    = 6
	grabber.corner_radius_top_right   = 6
	grabber.corner_radius_bottom_left = 6
	grabber.corner_radius_bottom_right = 6
	sl.add_theme_stylebox_override("grabber_area", grabber)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.20, 0.18, 0.26)
	track.content_margin_top    = 3.0
	track.content_margin_bottom = 3.0
	sl.add_theme_stylebox_override("slider", track)

# ── Language page ─────────────────────────────────────────────────────────────

func _build_page_language() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var lbl := Label.new()
	lbl.text = "Мова гри"
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.76))
	vbox.add_child(lbl)

	var langs := [["uk", "🇺🇦  Українська"], ["en", "🇬🇧  English"]]
	for pair in langs:
		var code: String  = pair[0]
		var label: String = pair[1]
		var btn := _make_choice_btn(label, code == _data.get("language", "uk"))
		btn.pressed.connect(_on_language_pressed.bind(code))
		vbox.add_child(btn)
		_lang_btns[code] = btn

	return vbox

# ── Graphics page ─────────────────────────────────────────────────────────────

func _build_page_graphics() -> Control:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)

	_toggle_vsync = _add_toggle_row(vbox, "Вертикальна синхронізація", _data.get("vsync", true))
	_toggle_vsync.pressed.connect(_on_vsync_pressed)

	var res_lbl := Label.new()
	res_lbl.text = "Роздільна здатність"
	res_lbl.add_theme_font_size_override("font_size", 21)
	res_lbl.add_theme_color_override("font_color", Color(0.70, 0.68, 0.76))
	vbox.add_child(res_lbl)

	var current_res: String = _data.get("resolution", "fhd")
	var presets := [["fhd", "FHD  1080×1920"], ["hd", "HD  720×1280"]]
	for pair in presets:
		var preset: String = pair[0]
		var label: String  = pair[1]
		var btn := _make_choice_btn(label, preset == current_res)
		btn.pressed.connect(_on_resolution_pressed.bind(preset))
		vbox.add_child(btn)
		_resolution_btns[preset] = btn

	return vbox

# ── Toggle row ────────────────────────────────────────────────────────────────

func _add_toggle_row(parent: VBoxContainer, label_text: String, active: bool) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 21)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.78, 0.85))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var btn := _make_toggle_btn(active)
	row.add_child(btn)
	return btn

func _make_toggle_btn(active: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(60, 30)
	btn.focus_mode = Control.FOCUS_NONE
	_style_toggle(btn, active)
	return btn

func _update_toggle(btn: Button, active: bool) -> void:
	_style_toggle(btn, active)

func _style_toggle(btn: Button, active: bool) -> void:
	btn.text = "ВКЛ" if active else "ВИКЛ"
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.28, 0.18, 0.42) if active else Color(0.15, 0.14, 0.20)
	s.corner_radius_top_left    = 8
	s.corner_radius_top_right   = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.55, 0.35, 0.75) if active else Color(0.28, 0.26, 0.35)
	for state in ["normal","hover","pressed","focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color",
		Color(0.88, 0.75, 1.00) if active else Color(0.48, 0.46, 0.55))
	btn.add_theme_font_size_override("font_size", 16)

# ── Choice button (language / resolution) ─────────────────────────────────────

func _make_choice_btn(text: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 42)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	_style_choice_btn(btn, active)
	return btn

func _style_choice_btn(btn: Button, active: bool) -> void:
	var n := StyleBoxFlat.new()
	var h := StyleBoxFlat.new()
	n.bg_color = Color(0.22, 0.18, 0.32) if active else Color(0.12, 0.11, 0.16)
	h.bg_color = Color(0.28, 0.24, 0.38)
	n.border_color = Color(0.55, 0.38, 0.78) if active else Color(0.24, 0.22, 0.30)
	h.border_color = Color(0.65, 0.48, 0.88)
	for s in [n, h]:
		s.border_width_left   = 1
		s.border_width_right  = 1
		s.border_width_top    = 1
		s.border_width_bottom = 1
		s.corner_radius_top_left    = 10
		s.corner_radius_top_right   = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", n)
	btn.add_theme_stylebox_override("focus",   n)
	btn.add_theme_color_override("font_color",
		Color(0.92, 0.82, 1.00) if active else Color(0.72, 0.70, 0.78))
