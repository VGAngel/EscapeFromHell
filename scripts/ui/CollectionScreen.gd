extends CanvasLayer

# Accessible from: main menu, pause, level complete.
# Call open() / close() from outside.
# Loads soul data from souls_collection.json at startup.

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const SOULS_PATH    := "res://souls_collection.json"
const FADE_DURATION := 0.35
const COLS          := 8
const CELL_SIZE     := Vector2(60, 60)
const CELL_GAP      := 4

# ── Soul data ─────────────────────────────────────────────────────────────────
var _named_souls:  Array = []   # Array[Dictionary]
var _hidden_souls: Array = []   # Array[Dictionary]

# ── Filter state ──────────────────────────────────────────────────────────────
var _filter_circle:    int    = 0     # 0 = all
var _filter_type:      String = "all"
var _filter_missing:   bool   = false
var _selected_soul:    Dictionary = {}

# ── UI roots ──────────────────────────────────────────────────────────────────
var _root:          ColorRect      = null
var _panel:         PanelContainer = null

# Header
var _lbl_title:     Label          = null
var _lbl_named:     Label          = null
var _lbl_hidden:    Label          = null

# Filter bar
var _filter_bar:    HBoxContainer  = null
var _circle_tabs:   Array          = []   # Array[Button]
var _type_btns:     Dictionary     = {}   # type_string → Button
var _btn_missing:   Button         = null

# Grid + scroll
var _scroll:        ScrollContainer = null
var _grid:          GridContainer   = null

# Detail panel
var _detail:        VBoxContainer  = null
var _detail_name:   Label          = null
var _detail_age:    Label          = null
var _detail_loc:    Label          = null
var _detail_sep:    HSeparator     = null
var _detail_text:   Label          = null
var _detail_extra:  Label          = null  # sin or reward

# Close button
var _btn_close:     Button         = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_load_souls()
	_build_ui()
	modulate.a = 0.0
	visible    = false

func _load_souls() -> void:
	var file := FileAccess.open(SOULS_PATH, FileAccess.READ)
	if not file:
		push_warning("CollectionScreen: souls_collection.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.read_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_named_souls  = parsed.get("named_souls",  [])
	_hidden_souls = parsed.get("hidden_souls", [])

# ── Public ────────────────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_refresh_counters()
	_rebuild_grid()
	_clear_detail()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
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

# ── Counters ──────────────────────────────────────────────────────────────────

func _refresh_counters() -> void:
	var named:  int = SaveManager.get_total_souls()         if SaveManager else 0
	var hidden: int = SaveManager.get_total_hidden_souls()  if SaveManager else 0
	_lbl_named.text  = "%d / 100" % named
	_lbl_hidden.text = "✦ %d / 20" % hidden
	if named >= 100:
		_lbl_named.add_theme_color_override("font_color", Color("#FFD700"))

# ── Grid ──────────────────────────────────────────────────────────────────────

func _rebuild_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	var saved_ids:  Array = SaveManager.get_saved_soul_ids()        if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids()       if SaveManager else []

	var all_souls: Array = []
	for s in _named_souls:
		all_souls.append({"data": s, "is_hidden": false})
	for s in _hidden_souls:
		all_souls.append({"data": s, "is_hidden": true})

	for entry in all_souls:
		var soul: Dictionary = entry["data"]
		var is_hidden: bool  = entry["is_hidden"]

		# Filters
		var circle: int = soul.get("circle", 0)
		if _filter_circle > 0 and circle != _filter_circle:
			continue
		var stype: String = soul.get("type", "innocent")
		if _filter_type != "all" and stype != _filter_type:
			continue

		var id: int      = soul.get("id", 0)
		var saved: bool  = (id in saved_ids) if not is_hidden else (str(id) in hidden_ids)

		if _filter_missing and saved:
			continue

		_grid.add_child(_make_cell(soul, is_hidden, saved))

func _make_cell(soul: Dictionary, is_hidden: bool, saved: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.clip_contents       = true
	btn.focus_mode          = Control.FOCUS_NONE

	# Style
	var normal := StyleBoxFlat.new()
	var hover  := StyleBoxFlat.new()
	if is_hidden:
		normal.bg_color   = Color(0.18, 0.14, 0.06) if saved else Color(0.10, 0.08, 0.04)
		normal.border_color = Color("#B8860B")
		hover.bg_color    = Color(0.28, 0.22, 0.08)
		hover.border_color = Color("#FFD700")
	else:
		normal.bg_color   = Color(0.16, 0.15, 0.20) if saved else Color(0.09, 0.09, 0.12)
		normal.border_color = Color(0.40, 0.37, 0.48) if saved else Color(0.22, 0.20, 0.28)
		hover.bg_color    = Color(0.24, 0.22, 0.30)
		hover.border_color = Color(0.70, 0.65, 0.80)
	for s in [normal, hover]:
		s.border_width_left   = 1
		s.border_width_right  = 1
		s.border_width_top    = 1
		s.border_width_bottom = 1
		s.corner_radius_top_left    = 6
		s.corner_radius_top_right   = 6
		s.corner_radius_bottom_left = 6
		s.corner_radius_bottom_right = 6
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus",   normal)

	# Content label
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if saved:
		var name: String = soul.get("name", "?")
		lbl.text = name.substr(0, 6)
		lbl.add_theme_color_override("font_color",
			Color("#FFD700") if is_hidden else Color(0.88, 0.86, 0.92))
		if is_hidden:
			var badge := Label.new()
			badge.text = "✦"
			badge.add_theme_font_size_override("font_size", 9)
			badge.add_theme_color_override("font_color", Color("#FFD700"))
			badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			badge.position = Vector2(-12, 2)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(badge)
	else:
		lbl.text = "?"
		lbl.add_theme_color_override("font_color",
			Color(0.60, 0.55, 0.30) if is_hidden else Color(0.35, 0.33, 0.40))

	btn.add_child(lbl)
	btn.pressed.connect(_on_cell_pressed.bind(soul, is_hidden, saved))
	return btn

# ── Detail panel ──────────────────────────────────────────────────────────────

func _on_cell_pressed(soul: Dictionary, is_hidden: bool, saved: bool) -> void:
	_selected_soul = soul
	if saved:
		_show_detail(soul, is_hidden)
	else:
		_show_not_found(soul, is_hidden)

func _show_detail(soul: Dictionary, is_hidden: bool) -> void:
	var name:   String = soul.get("name",   "?")
	var age:    int    = soul.get("age",     0)
	var circle: int    = soul.get("circle",  1)
	var level:  int    = soul.get("level",   0)

	_detail_name.text = name
	_detail_name.add_theme_color_override("font_color",
		Color("#FFD700") if is_hidden else Color(0.92, 0.90, 0.96))

	_detail_age.text = "%d років" % age
	_detail_age.visible = true

	if is_hidden:
		_detail_loc.text = "Коло %d • Прихована" % circle
	else:
		_detail_loc.text = "Коло %d • Рівень %d" % [circle, level]
	_detail_loc.visible = true
	_detail_sep.visible = true

	var story_key: String = "full_story" if is_hidden else "epitaph"
	_detail_text.text = soul.get(story_key, soul.get("epitaph", ""))
	_detail_text.visible = true

	if is_hidden:
		var reward: String = soul.get("reward", "")
		_detail_extra.text = "Нагорода: %s" % reward if reward else ""
		_detail_extra.add_theme_color_override("font_color", Color("#FFD700"))
	else:
		var sin_val: String = soul.get("sin", "none")
		_detail_extra.text = "Гріх: %s" % sin_val if sin_val != "none" else ""
		_detail_extra.add_theme_color_override("font_color", Color(0.70, 0.65, 0.75))
	_detail_extra.visible = _detail_extra.text != ""

func _show_not_found(soul: Dictionary, is_hidden: bool) -> void:
	_detail_name.text = "Душа не знайдена"
	_detail_name.add_theme_color_override("font_color", Color(0.50, 0.48, 0.55))
	_detail_age.visible  = false
	_detail_loc.visible  = false
	_detail_sep.visible  = false
	_detail_text.text    = "Продовжуй шукати в цьому Колі"
	_detail_text.visible = true
	_detail_extra.visible = false

func _clear_detail() -> void:
	_detail_name.text     = ""
	_detail_age.visible   = false
	_detail_loc.visible   = false
	_detail_sep.visible   = false
	_detail_text.visible  = false
	_detail_extra.visible = false

# ── Filter callbacks ──────────────────────────────────────────────────────────

func _on_circle_tab(circle: int) -> void:
	_filter_circle = circle
	_update_circle_tabs()
	_rebuild_grid()
	_clear_detail()

func _update_circle_tabs() -> void:
	for i in _circle_tabs.size():
		var active: bool = (i == 0 and _filter_circle == 0) or (i > 0 and _filter_circle == i)
		_circle_tabs[i].modulate = Color.WHITE if active else Color(0.6, 0.6, 0.6)

func _on_type_btn(type: String) -> void:
	_filter_type = type
	for t in _type_btns:
		_type_btns[t].modulate = Color.WHITE if t == type else Color(0.6, 0.6, 0.6)
	_rebuild_grid()
	_clear_detail()

func _on_missing_toggle() -> void:
	_filter_missing = not _filter_missing
	_btn_missing.modulate = Color.WHITE if _filter_missing else Color(0.6, 0.6, 0.6)
	_rebuild_grid()
	_clear_detail()

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen background
	_root = ColorRect.new()
	_root.color = Color(0.05, 0.04, 0.07, 0.97)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	_root.add_child(main_vbox)

	_build_header(main_vbox)
	_build_filter_bar(main_vbox)
	_build_body(main_vbox)

func _build_header(parent: VBoxContainer) -> void:
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 64
	hdr.add_theme_constant_override("separation", 12)
	var pad := StyleBoxFlat.new()
	pad.bg_color = Color(0.08, 0.07, 0.11)
	pad.content_margin_left   = 16.0
	pad.content_margin_right  = 16.0
	pad.content_margin_top    = 8.0
	pad.content_margin_bottom = 8.0
	parent.add_child(hdr)

	_lbl_title = Label.new()
	_lbl_title.text = "Врятовані Душі"
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.add_theme_font_size_override("font_size", 22)
	_lbl_title.add_theme_color_override("font_color", Color("#FFD700"))
	_lbl_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_title)

	_lbl_named = Label.new()
	_lbl_named.text = "0 / 100"
	_lbl_named.add_theme_font_size_override("font_size", 15)
	_lbl_named.add_theme_color_override("font_color", Color(0.80, 0.78, 0.84))
	_lbl_named.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_named)

	_lbl_hidden = Label.new()
	_lbl_hidden.text = "✦ 0 / 20"
	_lbl_hidden.add_theme_font_size_override("font_size", 14)
	_lbl_hidden.add_theme_color_override("font_color", Color("#B8860B"))
	_lbl_hidden.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_hidden)

	_btn_close = Button.new()
	_btn_close.text = "✕"
	_btn_close.custom_minimum_size = Vector2(40, 40)
	_btn_close.add_theme_font_size_override("font_size", 18)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0, 0, 0, 0)
	_btn_close.add_theme_stylebox_override("normal", cs)
	_btn_close.add_theme_color_override("font_color", Color(0.65, 0.62, 0.70))
	_btn_close.pressed.connect(close)
	hdr.add_child(_btn_close)

func _build_filter_bar(parent: VBoxContainer) -> void:
	_filter_bar = HBoxContainer.new()
	_filter_bar.custom_minimum_size.y = 44
	_filter_bar.add_theme_constant_override("separation", 6)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.07, 0.06, 0.09)
	parent.add_child(_filter_bar)

	# "Всі" circle tab
	var btn_all := _make_filter_btn("Всі")
	btn_all.pressed.connect(_on_circle_tab.bind(0))
	_filter_bar.add_child(btn_all)
	_circle_tabs.append(btn_all)

	# Circle 1–10 tabs
	for c in range(1, 11):
		var btn := _make_filter_btn("Коло %d" % c)
		btn.pressed.connect(_on_circle_tab.bind(c))
		_filter_bar.add_child(btn)
		_circle_tabs.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_filter_bar.add_child(spacer)

	# Type filter buttons
	var types := {"all": "Всі типи", "innocent": "Невинні", "broken": "Зламані", "sleeping": "Сплячі"}
	for key in types:
		var btn := _make_filter_btn(types[key])
		btn.pressed.connect(_on_type_btn.bind(key))
		_filter_bar.add_child(btn)
		_type_btns[key] = btn

	# Missing toggle
	_btn_missing = _make_filter_btn("Не знайдені")
	_btn_missing.pressed.connect(_on_missing_toggle)
	_filter_bar.add_child(_btn_missing)

	_update_circle_tabs()
	_on_type_btn("all")

func _make_filter_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	btn.focus_mode = Control.FOCUS_NONE
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.12, 0.11, 0.15)
	n.corner_radius_top_left    = 6
	n.corner_radius_top_right   = 6
	n.corner_radius_bottom_left = 6
	n.corner_radius_bottom_right = 6
	n.content_margin_left   = 8.0
	n.content_margin_right  = 8.0
	n.content_margin_top    = 4.0
	n.content_margin_bottom = 4.0
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.20, 0.18, 0.26)
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", n)
	btn.add_theme_stylebox_override("focus",   n)
	btn.add_theme_color_override("font_color", Color(0.82, 0.80, 0.86))
	return btn

func _build_body(parent: VBoxContainer) -> void:
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	parent.add_child(body)

	# Left: scrollable grid
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_grid.add_theme_constant_override("v_separation", CELL_GAP)
	_scroll.add_child(_grid)

	# Right: detail panel
	_build_detail_panel(body)

func _build_detail_panel(parent: HBoxContainer) -> void:
	var dp := PanelContainer.new()
	dp.custom_minimum_size = Vector2(220, 0)
	dp.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.11)
	style.border_width_left = 1
	style.border_color = Color(0.22, 0.20, 0.28)
	style.content_margin_left   = 16.0
	style.content_margin_right  = 16.0
	style.content_margin_top    = 20.0
	style.content_margin_bottom = 20.0
	dp.add_theme_stylebox_override("panel", style)
	parent.add_child(dp)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 8)
	dp.add_child(_detail)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 18)
	_detail_name.add_theme_color_override("font_color", Color(0.92, 0.90, 0.96))
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_detail_name)

	_detail_age = Label.new()
	_detail_age.add_theme_font_size_override("font_size", 13)
	_detail_age.add_theme_color_override("font_color", Color(0.60, 0.58, 0.65))
	_detail.add_child(_detail_age)

	_detail_loc = Label.new()
	_detail_loc.add_theme_font_size_override("font_size", 12)
	_detail_loc.add_theme_color_override("font_color", Color(0.55, 0.53, 0.60))
	_detail.add_child(_detail_loc)

	_detail_sep = HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.28, 0.25, 0.35)
	ss.content_margin_top    = 1.0
	ss.content_margin_bottom = 1.0
	_detail_sep.add_theme_stylebox_override("separator", ss)
	_detail.add_child(_detail_sep)

	_detail_text = Label.new()
	_detail_text.add_theme_font_size_override("font_size", 13)
	_detail_text.add_theme_color_override("font_color", Color(0.78, 0.76, 0.82))
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_detail_text)

	_detail_extra = Label.new()
	_detail_extra.add_theme_font_size_override("font_size", 12)
	_detail_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_detail_extra)

	_clear_detail()
