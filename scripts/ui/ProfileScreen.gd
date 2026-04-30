extends CanvasLayer

# Profile selection overlay — shown from MainMenu "Профіль" button.
# Displays all 3 save slots with play / delete actions.
# Emits `closed` when dismissed; caller refreshes its state.

signal closed

const FADE_DURATION := 0.3

var _root:       ColorRect    = null
var _slots_box:  VBoxContainer = null
var _confirm_slot:  int = -1   # slot awaiting delete confirmation (-1 = none)
var _creating_slot: int = -1   # slot in name-entry mode (-1 = none)
var _name_buffer:   String = ""

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	# Live-refresh on language switch — open() rebuilds cards each time
	# so we just need to redraw when the screen is currently visible.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	# Cards are rebuilt by `_refresh()` — same path used after delete/create.
	if visible:
		_refresh()


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.profile"))
	return "Профілі"

func open() -> void:
	visible = true
	_confirm_slot  = -1
	_creating_slot = -1
	_name_buffer   = ""
	_refresh()
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

# ── Data ──────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not _slots_box:
		return
	for child in _slots_box.get_children():
		child.queue_free()

	var slots: Array = SaveManager.get_all_slots() if SaveManager else []
	for i in 3:
		var info: Dictionary = slots[i] if i < slots.size() else {"slot": i, "exists": false}
		_slots_box.add_child(_make_slot_card(info))

# ── Slot actions ──────────────────────────────────────────────────────────────

## Pick an existing profile and close.
func _select_slot(slot: int) -> void:
	if SaveManager:
		SaveManager.load_slot(slot)
	close()

## Switch a card to "enter your name" mode.
func _begin_create(slot: int) -> void:
	_creating_slot = slot
	_name_buffer   = ""
	_refresh()

## Confirm new-profile creation: load the slot, persist the name, close.
func _confirm_create(slot: int) -> void:
	if SaveManager:
		SaveManager.load_slot(slot)
		var nm: String = _name_buffer.strip_edges()
		if nm.is_empty():
			nm = "Профіль %d" % (slot + 1)
		if SaveManager.has_method("set_profile_name"):
			SaveManager.set_profile_name(nm)
	close()

func _cancel_create() -> void:
	_creating_slot = -1
	_name_buffer   = ""
	_refresh()

func _request_delete(slot: int) -> void:
	if _confirm_slot == slot:
		if SaveManager:
			SaveManager.delete_slot(slot)
		_confirm_slot = -1
		_refresh()
	else:
		_confirm_slot = slot
		_refresh()

# ── Card builder ──────────────────────────────────────────────────────────────

func _make_slot_card(info: Dictionary) -> Control:
	var slot:   int    = info.get("slot",        0)
	var exists: bool   = info.get("exists",      false)
	var level:  int    = info.get("level",       1)
	var souls:  int    = info.get("total_souls", 0)
	var name_s: String = info.get("name",        "")
	var pending_confirm: bool = (_confirm_slot == slot)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 130)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.14) if not pending_confirm else Color(0.20, 0.06, 0.06)
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.20, 0.20) if pending_confirm else Color(0.35, 0.28, 0.50)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 12)
	style.content_margin_left   = 16.0
	style.content_margin_right  = 16.0
	style.content_margin_top    = 14.0
	style.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(hbox)

	# ── Left: info ────────────────────────────────────────────────────────────
	var info_col := VBoxContainer.new()
	info_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_col.add_theme_constant_override("separation", 5)
	hbox.add_child(info_col)

	var lbl_name := Label.new()
	lbl_name.text = name_s if not name_s.is_empty() else "Профіль %d" % (slot + 1)
	lbl_name.add_theme_font_size_override("font_size", 18)
	lbl_name.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	info_col.add_child(lbl_name)

	if pending_confirm:
		var lbl_warn := Label.new()
		lbl_warn.text = _t("profile.warn_delete", {},
				"⚠ Натисніть «Видалити» ще раз для підтвердження")
		lbl_warn.add_theme_font_size_override("font_size", 12)
		lbl_warn.add_theme_color_override("font_color", Color("#FF7766"))
		lbl_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_col.add_child(lbl_warn)
	elif exists:
		var lbl_prog := Label.new()
		lbl_prog.text = _t("profile.progress_format",
				{"level": level, "souls": souls},
				"Рівень %d  •  Душі: %d" % [level, souls])
		lbl_prog.add_theme_font_size_override("font_size", 13)
		lbl_prog.add_theme_color_override("font_color", Color(0.60, 0.58, 0.68))
		info_col.add_child(lbl_prog)

		if SaveManager and SaveManager.get_slot() == slot:
			var lbl_active := Label.new()
			lbl_active.text = _t("profile.active_marker", {}, "● Активний")
			lbl_active.add_theme_font_size_override("font_size", 12)
			lbl_active.add_theme_color_override("font_color", Color("#88DD88"))
			info_col.add_child(lbl_active)
	else:
		var lbl_empty := Label.new()
		lbl_empty.text = _t("profile.empty_slot", {}, "Порожній слот")
		lbl_empty.add_theme_font_size_override("font_size", 13)
		lbl_empty.add_theme_color_override("font_color", Color(0.40, 0.38, 0.46))
		info_col.add_child(lbl_empty)

	# Empty slot in name-entry mode: replace the info column with a LineEdit
	# row and short Створити/Скасувати buttons.
	if not exists and _creating_slot == slot:
		# Drop the auto-built info column and rebuild in entry mode.
		for child in info_col.get_children():
			child.queue_free()
		var prompt := Label.new()
		prompt.text = _t("profile.name_prompt", {}, "Введіть ім'я:")
		prompt.add_theme_font_size_override("font_size", 13)
		prompt.add_theme_color_override("font_color", Color(0.60, 0.58, 0.68))
		info_col.add_child(prompt)

		var name_edit := LineEdit.new()
		name_edit.placeholder_text = _t("profile.name_placeholder",
				{"n": slot + 1}, "Профіль %d" % (slot + 1))
		name_edit.max_length = 24
		name_edit.text = _name_buffer
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.add_theme_font_size_override("font_size", 16)
		name_edit.text_changed.connect(func(t: String) -> void: _name_buffer = t)
		name_edit.text_submitted.connect(func(_ignored: String) -> void: _confirm_create(slot))
		info_col.add_child(name_edit)
		name_edit.grab_focus.call_deferred()

	# ── Right: action buttons ─────────────────────────────────────────────────
	var btns_col := VBoxContainer.new()
	btns_col.add_theme_constant_override("separation", 6)
	hbox.add_child(btns_col)

	if exists:
		var btn_play := _card_btn(
				_t("profile.btn_play", {}, "Грати"),
				Color(0.22, 0.16, 0.34), Color("#AA88FF"))
		btn_play.pressed.connect(func() -> void: _select_slot(slot))
		btns_col.add_child(btn_play)

		var del_text: String
		if pending_confirm:
			del_text = _t("profile.btn_confirm", {}, "Підтвердити")
		else:
			del_text = _t("profile.btn_delete", {}, "Видалити")
		var btn_del := _card_btn(del_text, Color(0.28, 0.08, 0.08), Color("#FF7766"))
		btn_del.pressed.connect(func() -> void: _request_delete(slot))
		btns_col.add_child(btn_del)
	elif _creating_slot == slot:
		var btn_ok := _card_btn(
				_t("profile.btn_create", {}, "Створити"),
				Color(0.10, 0.18, 0.10), Color("#88DD88"))
		btn_ok.pressed.connect(func() -> void: _confirm_create(slot))
		btns_col.add_child(btn_ok)

		var btn_cancel := _card_btn(
				_t("profile.btn_cancel", {}, "Скасувати"),
				Color(0.10, 0.10, 0.14), Color(0.7, 0.7, 0.7))
		btn_cancel.pressed.connect(_cancel_create)
		btns_col.add_child(btn_cancel)
	else:
		var btn_new := _card_btn("Новий\nПрофіль", Color(0.10, 0.18, 0.10), Color("#88DD88"))
		btn_new.pressed.connect(func() -> void: _begin_create(slot))
		btns_col.add_child(btn_new)

	return card

func _card_btn(text: String, bg: Color, font_color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(100, 48)
	btn.add_theme_font_size_override("font_size", 13)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_color_override("font_color", font_color)

	var s := StyleBoxFlat.new()
	s.bg_color = bg
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s.set("corner_radius_" + corner, 8)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, s)
	return btn

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.05, 0.04, 0.08, 0.97)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	_root.add_child(vbox)

	_build_header(vbox)
	_build_slots_area(vbox)

func _build_header(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",     8)
	margin.add_theme_constant_override("margin_bottom",  8)
	parent.add_child(margin)

	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 48
	margin.add_child(hdr)

	var title := Label.new()
	title.text = _t("profile.title", {}, "Профілі")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(44, 44)
	btn_close.add_theme_font_size_override("font_size", 18)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		btn_close.add_theme_stylebox_override(state, empty)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_slots_area(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 70)
	scroll.add_child(margin)

	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots_box.add_theme_constant_override("separation", 16)
	margin.add_child(_slots_box)
