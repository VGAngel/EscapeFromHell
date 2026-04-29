extends CanvasLayer

# Accessible from: main menu, pause, level complete.
# Call open() / close() from outside.
# Call notify_soul_added(soul_id) when a new soul is collected mid-game.

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const SOULS_PATH    := "res://souls_collection.json"
const FADE_DURATION := 0.35
const COLS          := 6
const CELL_SIZE     := Vector2(100, 100)
const CELL_GAP      := 8
const DETAIL_W      := 320

# ── Soul data ─────────────────────────────────────────────────────────────────
var _named_souls:  Array = []
var _hidden_souls: Array = []

# ── Filter state ──────────────────────────────────────────────────────────────
var _filter_circle:  int    = 0
var _filter_type:    String = "all"
var _filter_missing: bool   = false

# ── Cell node map: soul_id (int or String) → Button ──────────────────────────
var _cell_nodes: Dictionary = {}

# ── UI roots ──────────────────────────────────────────────────────────────────
var _root:       ColorRect       = null

# Header
var _lbl_named:  Label           = null
var _lbl_hidden: Label           = null
# Per-circle progress strip — populated in _build_circle_progress, refreshed
# from _refresh_counters whenever SaveManager state changes.
var _circle_progress_box: HBoxContainer = null

# Filters – row 1: circle scroll tabs
var _circle_scroll: ScrollContainer = null
var _circle_row:    HBoxContainer   = null
var _circle_tabs:   Array           = []   # Array[Button], index 0 = "Всі"

# Filters – row 2: type buttons + missing toggle
var _type_btns:    Dictionary    = {}
var _btn_missing:  Button        = null

# Grid
var _grid_scroll:  ScrollContainer = null
var _grid:         GridContainer   = null

# Detail bottom sheet
var _sheet:        PanelContainer  = null
var _sheet_tween:  Tween           = null
var _sheet_name:   Label           = null
var _sheet_age:    Label           = null
var _sheet_loc:    Label           = null
var _sheet_sep:    HSeparator      = null
var _sheet_text:   Label           = null
var _sheet_extra:  Label           = null
var _sheet_open:   bool            = false

# Completion overlay
var _completion_lbl: Label         = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_souls()
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	# Live-refresh on language switch — full rebuild via open() if visible.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	if visible:
		_refresh_counters()
		_rebuild_grid()


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func _load_souls() -> void:
	var file := FileAccess.open(SOULS_PATH, FileAccess.READ)
	if not file:
		push_warning("CollectionScreen: souls_collection.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return
	_named_souls  = parsed.get("named_souls",  [])
	_hidden_souls = parsed.get("hidden_souls", [])

# ── Public API ────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.collection"))
	return "Врятовані душі"

func open() -> void:
	visible = true
	_cell_nodes.clear()
	_refresh_counters()
	_rebuild_grid()
	_close_sheet_instant()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit()
	)

# Called by GameManager when a new soul is collected during a level.
func notify_soul_added(soul_id: int) -> void:
	_refresh_counters()
	# Animate the matching cell if visible
	if _cell_nodes.has(soul_id):
		_animate_new_soul_cell(_cell_nodes[soul_id])
	# 100/100 completion
	if SaveManager and SaveManager.get_total_souls() >= 100:
		_animate_completion()

func notify_hidden_soul_added(soul_id: String) -> void:
	_refresh_counters()
	if _cell_nodes.has(soul_id):
		_animate_new_soul_cell(_cell_nodes[soul_id])

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _sheet_open:
			_close_sheet()
		else:
			close()
		get_viewport().set_input_as_handled()

# ── Counters ──────────────────────────────────────────────────────────────────

func _refresh_counters() -> void:
	var named:  int = SaveManager.get_total_souls()        if SaveManager else 0
	var hidden: int = SaveManager.get_total_hidden_souls() if SaveManager else 0
	_lbl_named.text  = _t("collection.counter_named", {"saved": named}, "%d / 100" % named)
	_lbl_hidden.text = _t("collection.counter_hidden", {"saved": hidden}, "✦ %d / 20" % hidden)
	_lbl_named.add_theme_color_override("font_color",
		Color("#FFD700") if named >= 100 else Color(0.82, 0.80, 0.86))
	_refresh_circle_progress()

## Compute per-circle (1..10) counts from the loaded named/hidden lists and
## the SaveManager's saved IDs, then refresh the inline progress strip so
## the player can see "Circle 3: 7/10 ✦1/2" at a glance.
func _refresh_circle_progress() -> void:
	if not _circle_progress_box:
		return
	for child in _circle_progress_box.get_children():
		child.queue_free()

	var saved_ids:  Array = SaveManager.get_saved_soul_ids()  if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids() if SaveManager else []

	# Build per-circle totals + found counts in one pass each.
	var per_circle_total:    Dictionary = {}   # circle → named total
	var per_circle_found:    Dictionary = {}   # circle → named found
	var per_circle_h_total:  Dictionary = {}   # circle → hidden total
	var per_circle_h_found:  Dictionary = {}   # circle → hidden found
	for soul in _named_souls:
		var c: int = int(soul.get("circle", 0))
		if c <= 0:
			continue
		per_circle_total[c] = int(per_circle_total.get(c, 0)) + 1
		if int(soul.get("id", 0)) in saved_ids:
			per_circle_found[c] = int(per_circle_found.get(c, 0)) + 1
	for soul in _hidden_souls:
		var c: int = int(soul.get("circle", 0))
		if c <= 0:
			continue
		per_circle_h_total[c] = int(per_circle_h_total.get(c, 0)) + 1
		if str(soul.get("id", "")) in hidden_ids:
			per_circle_h_found[c] = int(per_circle_h_found.get(c, 0)) + 1

	# Render 10 cells (1..10), one per circle. Filled circles glow gold.
	for c in range(1, 11):
		var total:    int = int(per_circle_total.get(c, 0))
		var found:    int = int(per_circle_found.get(c, 0))
		var h_total:  int = int(per_circle_h_total.get(c, 0))
		var h_found:  int = int(per_circle_h_found.get(c, 0))
		_circle_progress_box.add_child(
			_make_circle_cell(c, found, total, h_found, h_total)
		)

func _make_circle_cell(circle: int, found: int, total: int,
		h_found: int, h_total: int) -> Control:
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var head := Label.new()
	head.text = _t("collection.circle_short", {"n": circle}, "К%d" % circle)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color",
		Color(0.55, 0.52, 0.62) if total == 0 else Color(0.85, 0.82, 0.90))
	v.add_child(head)

	var counts := Label.new()
	counts.text = "%d/%d" % [found, total]
	counts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	counts.add_theme_font_size_override("font_size", 22)
	var done: bool = total > 0 and found >= total
	counts.add_theme_color_override("font_color",
		Color("#FFD700") if done else Color(0.92, 0.90, 0.96))
	v.add_child(counts)

	if h_total > 0:
		var hidden_lbl := Label.new()
		hidden_lbl.text = "✦ %d/%d" % [h_found, h_total]
		hidden_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hidden_lbl.add_theme_font_size_override("font_size", 16)
		hidden_lbl.add_theme_color_override("font_color",
			Color("#FFE066") if h_found >= h_total else Color("#A07820"))
		v.add_child(hidden_lbl)
	return v

# ── Grid ──────────────────────────────────────────────────────────────────────

func _rebuild_grid() -> void:
	if not _grid:
		return
	_cell_nodes.clear()
	for child in _grid.get_children():
		child.queue_free()

	var saved_ids:  Array = SaveManager.get_saved_soul_ids()   if SaveManager else []
	var hidden_ids: Array = SaveManager.get_hidden_soul_ids()  if SaveManager else []

	for soul in _named_souls:
		if not _passes_filter(soul, false):
			continue
		var id: int   = soul.get("id", 0)
		var saved: bool = id in saved_ids
		if _filter_missing and saved:
			continue
		var cell := _make_cell(soul, false, saved)
		_grid.add_child(cell)
		_cell_nodes[id] = cell

	for soul in _hidden_souls:
		if not _passes_filter(soul, true):
			continue
		var id: String = str(soul.get("id", ""))
		var saved: bool = id in hidden_ids
		if _filter_missing and saved:
			continue
		var cell := _make_cell(soul, true, saved)
		_grid.add_child(cell)
		_cell_nodes[id] = cell

func _passes_filter(soul: Dictionary, _is_hidden: bool) -> bool:
	if _filter_circle > 0 and soul.get("circle", 0) != _filter_circle:
		return false
	if _filter_type != "all" and soul.get("type", "") != _filter_type:
		return false
	return true

func _make_cell(soul: Dictionary, is_hidden: bool, saved: bool) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = CELL_SIZE
	btn.clip_contents = true
	btn.focus_mode    = Control.FOCUS_NONE

	var normal := StyleBoxFlat.new()
	var hover  := StyleBoxFlat.new()
	_style_cell(normal, is_hidden, saved, false)
	_style_cell(hover,  is_hidden, saved, true)
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hover)
	btn.add_theme_stylebox_override("pressed", normal)
	btn.add_theme_stylebox_override("focus",   normal)

	# Main label
	var lbl := Label.new()
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if saved:
		lbl.text = soul.get("name", "?").substr(0, 5)
		lbl.add_theme_color_override("font_color",
			Color("#FFD700") if is_hidden else Color(0.88, 0.86, 0.92))
	else:
		lbl.text = _t("collection.not_found_label", {}, "?")
		lbl.add_theme_color_override("font_color",
			Color(0.55, 0.48, 0.22) if is_hidden else Color(0.32, 0.30, 0.38))

	btn.add_child(lbl)

	# Hidden badge ✦
	if is_hidden:
		var badge := Label.new()
		badge.text = "✦"
		badge.add_theme_font_size_override("font_size", 20)
		badge.add_theme_color_override("font_color",
			Color("#FFD700") if saved else Color(0.45, 0.38, 0.12))
		badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		badge.position = Vector2(-18, 2)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(badge)

	btn.pressed.connect(_on_cell_pressed.bind(soul, is_hidden, saved))
	return btn

func _style_cell(s: StyleBoxFlat, is_hidden: bool, saved: bool, hovered: bool) -> void:
	if is_hidden:
		s.bg_color     = Color(0.22, 0.16, 0.06) if (saved and hovered) else \
						 (Color(0.18, 0.13, 0.05) if saved else Color(0.10, 0.08, 0.04))
		s.border_color = Color("#FFD700") if hovered else Color("#A07820")
	else:
		s.bg_color     = Color(0.26, 0.24, 0.32) if (saved and hovered) else \
						 (Color(0.18, 0.16, 0.22) if saved else Color(0.10, 0.09, 0.13))
		s.border_color = Color(0.65, 0.60, 0.78) if hovered else \
						 (Color(0.42, 0.38, 0.52) if saved else Color(0.22, 0.20, 0.28))
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left    = 6
	s.corner_radius_top_right   = 6
	s.corner_radius_bottom_left = 6
	s.corner_radius_bottom_right = 6

# ── Cell animation (new soul) ─────────────────────────────────────────────────

func _animate_new_soul_cell(cell: Control) -> void:
	var tw := create_tween()
	tw.tween_property(cell, "scale", Vector2(1.35, 1.35), 0.12)
	tw.tween_property(cell, "scale", Vector2.ONE,         0.18)
	# Flash white overlay
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.55)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(flash)
	var ftw := create_tween()
	ftw.tween_property(flash, "modulate:a", 0.0, 0.4)
	ftw.tween_callback(flash.queue_free)

# ── 100/100 completion ────────────────────────────────────────────────────────

func _animate_completion() -> void:
	if not _completion_lbl:
		return
	_completion_lbl.visible = true
	_completion_lbl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_completion_lbl, "modulate:a", 1.0, 0.6)
	tw.tween_interval(3.0)
	tw.tween_property(_completion_lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func() -> void: _completion_lbl.visible = false)

	# Warm glow all saved cells
	for id in _cell_nodes:
		var cell: Control = _cell_nodes[id]
		var gtw := create_tween()
		gtw.tween_property(cell, "modulate", Color(1.3, 1.1, 0.7), 1.2)
		gtw.tween_property(cell, "modulate", Color.WHITE, 1.8)

# ── Detail bottom sheet ───────────────────────────────────────────────────────

func _on_cell_pressed(soul: Dictionary, is_hidden: bool, saved: bool) -> void:
	if saved:
		_show_sheet(soul, is_hidden)
	else:
		_show_sheet_not_found(soul)

func _show_sheet(soul: Dictionary, is_hidden: bool) -> void:
	_sheet_name.text = soul.get("name", "?")
	_sheet_name.add_theme_color_override("font_color",
		Color("#FFD700") if is_hidden else Color(0.92, 0.90, 0.96))

	_sheet_age.text    = "%d років" % soul.get("age", 0)
	_sheet_age.visible = true

	var circle: int = soul.get("circle", 1)
	var level:  int = soul.get("level",  0)
	_sheet_loc.text = _t("collection.detail_location_hidden", {"circle": circle}, "Коло %d • Прихована" % circle) if is_hidden else \
					  _t("collection.detail_location_common", {"circle": circle, "level": level}, "Коло %d • Рівень %d" % [circle, level])
	_sheet_loc.visible = true
	_sheet_sep.visible = true

	var story: String = soul.get("full_story", soul.get("epitaph", ""))
	_sheet_text.text    = story
	_sheet_text.visible = true

	if is_hidden:
		var reward: String = soul.get("reward", "")
		_sheet_extra.text    = _t("collection.detail_reward_format", {"reward": reward}, "Нагорода: %s" % reward) if reward else ""
		_sheet_extra.add_theme_color_override("font_color", Color("#FFD700"))
	else:
		var sin_val: String = soul.get("sin", "none")
		_sheet_extra.text = _t("collection.detail_sin_format", {"sin": sin_val}, "Гріх: %s" % sin_val) if sin_val != "none" else ""
		_sheet_extra.add_theme_color_override("font_color", Color(0.65, 0.60, 0.72))
	_sheet_extra.visible = _sheet_extra.text != ""

	_open_sheet()

func _show_sheet_not_found(_soul: Dictionary) -> void:
	_sheet_name.text = _t("collection.detail_not_found", {}, "Душа не знайдена")
	_sheet_name.add_theme_color_override("font_color", Color(0.48, 0.46, 0.54))
	_sheet_age.visible  = false
	_sheet_loc.visible  = false
	_sheet_sep.visible  = false
	_sheet_text.text    = "Продовжуй шукати в цьому Колі"
	_sheet_text.visible = true
	_sheet_extra.visible = false
	_open_sheet()

func _open_sheet() -> void:
	_sheet_open = true
	_sheet.visible = true
	if _sheet_tween:
		_sheet_tween.kill()
	_sheet_tween = create_tween()
	var sa: Node = get_node_or_null("/root/SafeArea")
	var banner: float = float(sa.bottom_reserved) if sa else 60.0
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet_tween.tween_property(_sheet, "position:y",
		vp_h - _sheet.size.y - banner, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)

func _close_sheet() -> void:
	if not _sheet_open:
		return
	_sheet_open = false
	if _sheet_tween:
		_sheet_tween.kill()
	_sheet_tween = create_tween()
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet_tween.tween_property(_sheet, "position:y", vp_h + 100.0, 0.18)
	_sheet_tween.tween_callback(func() -> void: _sheet.visible = false)

func _close_sheet_instant() -> void:
	_sheet_open = false
	if not _sheet:
		return
	var vp_h: float = get_viewport().get_visible_rect().size.y
	_sheet.position.y = vp_h + 100.0
	_sheet.visible = false

# ── Filter callbacks ──────────────────────────────────────────────────────────

func _on_circle_tab(circle: int) -> void:
	_filter_circle = circle
	_update_circle_tabs()
	_close_sheet_instant()
	_rebuild_grid()

func _update_circle_tabs() -> void:
	for i in _circle_tabs.size():
		var active: bool = (i == 0 and _filter_circle == 0) or (i > 0 and _filter_circle == i)
		_circle_tabs[i].modulate = Color.WHITE if active else Color(0.55, 0.53, 0.60)

func _on_type_btn(t: String) -> void:
	_filter_type = t
	for key in _type_btns:
		_type_btns[key].modulate = Color.WHITE if key == t else Color(0.55, 0.53, 0.60)
	_close_sheet_instant()
	_rebuild_grid()

func _on_missing_toggle() -> void:
	_filter_missing = not _filter_missing
	_btn_missing.modulate = Color.WHITE if _filter_missing else Color(0.55, 0.53, 0.60)
	_close_sheet_instant()
	_rebuild_grid()

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.05, 0.04, 0.07, 0.97)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	_build_header(vbox)
	_build_circle_progress(vbox)
	_build_circle_row(vbox)
	_build_type_row(vbox)
	_build_grid_area(vbox)

func _build_circle_progress(parent: VBoxContainer) -> void:
	# 10 cells in one row, evenly spread, sitting just under the title bar.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top",    4)
	margin.add_theme_constant_override("margin_bottom", 8)
	parent.add_child(margin)
	_circle_progress_box = HBoxContainer.new()
	_circle_progress_box.add_theme_constant_override("separation", 4)
	_circle_progress_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_circle_progress_box)
	_build_sheet()
	_build_completion_label()

func _build_header(parent: VBoxContainer) -> void:
	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 88
	hdr.add_theme_constant_override("separation", 18)

	# Inline padding via MarginContainer
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  24)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top",   12)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(margin)
	margin.add_child(hdr)

	var title := Label.new()
	title.text = _t("collection.title", {}, "Врятовані Душі")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#FFD700"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	_lbl_named = Label.new()
	_lbl_named.text = "0 / 100"
	_lbl_named.add_theme_font_size_override("font_size", 30)
	_lbl_named.add_theme_color_override("font_color", Color(0.80, 0.78, 0.84))
	_lbl_named.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_named)

	_lbl_hidden = Label.new()
	_lbl_hidden.text = "✦ 0 / 20"
	_lbl_hidden.add_theme_font_size_override("font_size", 28)
	_lbl_hidden.add_theme_color_override("font_color", Color("#A07820"))
	_lbl_hidden.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_hidden)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(72, 72)
	btn_close.add_theme_font_size_override("font_size", 38)
	var cs := StyleBoxEmpty.new()
	btn_close.add_theme_stylebox_override("normal", cs)
	btn_close.add_theme_stylebox_override("hover",  cs)
	btn_close.add_theme_color_override("font_color", Color(0.62, 0.60, 0.68))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_circle_row(parent: VBoxContainer) -> void:
	# Horizontally scrollable row of circle tabs
	_circle_scroll = ScrollContainer.new()
	_circle_scroll.custom_minimum_size.y = 64
	_circle_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	_circle_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(_circle_scroll)

	_circle_row = HBoxContainer.new()
	_circle_row.add_theme_constant_override("separation", 5)
	_circle_scroll.add_child(_circle_row)

	# Left margin
	var lm := Control.new()
	lm.custom_minimum_size.x = 10
	_circle_row.add_child(lm)

	var btn_all := _filter_btn(_t("collection.filter_all", {}, "Всі"), true)
	btn_all.pressed.connect(_on_circle_tab.bind(0))
	_circle_row.add_child(btn_all)
	_circle_tabs.append(btn_all)

	for c in range(1, 11):
		var btn := _filter_btn(_t("collection.circle_tab_format", {"n": c}, "Коло %d" % c), false)
		btn.pressed.connect(_on_circle_tab.bind(c))
		_circle_row.add_child(btn)
		_circle_tabs.append(btn)

	# Right margin
	var rm := Control.new()
	rm.custom_minimum_size.x = 10
	_circle_row.add_child(rm)

	_update_circle_tabs()

func _build_type_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 64
	row.add_theme_constant_override("separation", 8)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top",    6)
	margin.add_theme_constant_override("margin_bottom", 6)
	parent.add_child(margin)
	margin.add_child(row)

	var types: Dictionary = {
		"all": "Всі типи",
		"innocent": "Невинні",
		"broken": "Зламані",
		"sleeping": "Сплячі",
	}
	for key in types:
		var btn := _filter_btn(types[key], key == "all")
		btn.pressed.connect(_on_type_btn.bind(key))
		row.add_child(btn)
		_type_btns[key] = btn

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_btn_missing = _filter_btn(_t("collection.filter_not_found", {}, "Не знайдені"), false)
	_btn_missing.pressed.connect(_on_missing_toggle)
	row.add_child(_btn_missing)

	_on_type_btn("all")

func _build_grid_area(parent: VBoxContainer) -> void:
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_grid_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top",   14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_grid_scroll.add_child(margin)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", CELL_GAP)
	_grid.add_theme_constant_override("v_separation", CELL_GAP)
	margin.add_child(_grid)

func _build_sheet() -> void:
	# Slides up from bottom on cell tap
	_sheet = PanelContainer.new()
	_sheet.custom_minimum_size = Vector2(0, 0)
	_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.12, 0.98)
	style.border_width_top = 2
	style.border_color     = Color(0.30, 0.26, 0.40)
	style.corner_radius_top_left  = 22
	style.corner_radius_top_right = 22
	style.content_margin_left   = 30.0
	style.content_margin_right  = 30.0
	style.content_margin_top    = 26.0
	style.content_margin_bottom = 30.0
	_sheet.add_theme_stylebox_override("panel", style)

	# Absolutely positioned — starts off-screen below (position set in _ready after layout settles)
	_sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_root.add_child(_sheet)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_sheet.add_child(vbox)

	# Drag handle
	var handle := ColorRect.new()
	handle.color = Color(0.38, 0.35, 0.48)
	handle.custom_minimum_size = Vector2(64, 6)
	handle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(handle)

	_sheet_name = Label.new()
	_sheet_name.add_theme_font_size_override("font_size", 42)
	_sheet_name.add_theme_color_override("font_color", Color(0.92, 0.90, 0.96))
	_sheet_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sheet_name)

	_sheet_age = Label.new()
	_sheet_age.add_theme_font_size_override("font_size", 28)
	_sheet_age.add_theme_color_override("font_color", Color(0.58, 0.56, 0.64))
	vbox.add_child(_sheet_age)

	_sheet_loc = Label.new()
	_sheet_loc.add_theme_font_size_override("font_size", 26)
	_sheet_loc.add_theme_color_override("font_color", Color(0.52, 0.50, 0.58))
	vbox.add_child(_sheet_loc)

	_sheet_sep = HSeparator.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0.28, 0.24, 0.36)
	ss.content_margin_top = 1.0; ss.content_margin_bottom = 1.0
	_sheet_sep.add_theme_stylebox_override("separator", ss)
	vbox.add_child(_sheet_sep)

	_sheet_text = Label.new()
	_sheet_text.add_theme_font_size_override("font_size", 28)
	_sheet_text.add_theme_color_override("font_color", Color(0.84, 0.82, 0.88))
	_sheet_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sheet_text)

	_sheet_extra = Label.new()
	_sheet_extra.add_theme_font_size_override("font_size", 26)
	_sheet_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sheet_extra)

	# Tap anywhere on sheet to close
	var close_btn := Button.new()
	close_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	var invisible := StyleBoxEmpty.new()
	close_btn.add_theme_stylebox_override("normal", invisible)
	close_btn.add_theme_stylebox_override("hover",  invisible)
	close_btn.pressed.connect(_close_sheet)
	_sheet.add_child(close_btn)

func _build_completion_label() -> void:
	_completion_lbl = Label.new()
	_completion_lbl.text = _t("collection.complete_text", {}, "Всі 100 душ знайдені")
	_completion_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_completion_lbl.add_theme_font_size_override("font_size", 38)
	_completion_lbl.add_theme_color_override("font_color", Color("#FFD700"))
	_completion_lbl.set_anchors_preset(Control.PRESET_CENTER)
	_completion_lbl.position.y = 200
	_completion_lbl.visible = false
	_root.add_child(_completion_lbl)

# ── Filter button factory ─────────────────────────────────────────────────────

func _filter_btn(text: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 26)

	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.14, 0.13, 0.18)
	n.corner_radius_top_left    = 10
	n.corner_radius_top_right   = 10
	n.corner_radius_bottom_left = 10
	n.corner_radius_bottom_right = 10
	n.content_margin_left   = 18.0
	n.content_margin_right  = 18.0
	n.content_margin_top    = 10.0
	n.content_margin_bottom = 10.0

	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = Color(0.22, 0.20, 0.28)

	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", n)
	btn.add_theme_stylebox_override("focus",   n)
	btn.add_theme_color_override("font_color", Color(0.84, 0.82, 0.88))
	btn.modulate = Color.WHITE if active else Color(0.55, 0.53, 0.60)
	return btn
