extends CanvasLayer

# Accessed from Hub via BtnUpgrades.
# Loads upgrades_config.json, shows 6 category tabs,
# each with upgrade cards — Buy / Max / Locked states.

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const CONFIG_PATH   := "res://upgrades_config.json"
const FADE_DURATION := 0.3

# ── Data ──────────────────────────────────────────────────────────────────────
var _categories: Array = []   # raw from JSON

# ── UI ────────────────────────────────────────────────────────────────────────
var _root:          ColorRect        = null
var _lbl_currency:  Label            = null

# Category tab bar
var _cat_tabs:      Array            = []   # Array[Button]
var _active_cat:    int              = 0

# Cards container
var _cards_scroll:  ScrollContainer  = null
var _cards_box:     VBoxContainer    = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_load_config()
	_build_ui()
	_root.modulate.a = 0.0
	visible    = false

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("UpgradesScreen: upgrades_config.json not found")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_categories = parsed.get("categories", [])

# ── Public ────────────────────────────────────────────────────────────────────

func open() -> void:
	visible = true
	_refresh_currency()
	_switch_category(0)
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

# ── Currency ──────────────────────────────────────────────────────────────────

func _refresh_currency() -> void:
	var light: int = SaveManager.get_light() if SaveManager else 0
	_lbl_currency.text = "💡 %d" % light

# ── Category switching ────────────────────────────────────────────────────────

func _switch_category(idx: int) -> void:
	_active_cat = idx
	for i in _cat_tabs.size():
		_cat_tabs[i].modulate = Color.WHITE if i == idx else Color(0.55, 0.52, 0.62)
	_rebuild_cards(idx)

# ── Cards ─────────────────────────────────────────────────────────────────────

func _rebuild_cards(cat_idx: int) -> void:
	for child in _cards_box.get_children():
		child.queue_free()

	if cat_idx >= _categories.size():
		return

	var category: Dictionary = _categories[cat_idx]
	for upgrade in category.get("upgrades", []):
		_cards_box.add_child(_make_card(upgrade))

func _make_card(upgrade: Dictionary) -> Control:
	var id:        String = upgrade.get("id",          "")
	var upgrade_name: String = upgrade.get("name",        "")
	var desc:      String = upgrade.get("description", "")
	var cost:      int    = upgrade.get("cost",         0)
	var max_level: int    = upgrade.get("max_level",    1)
	var cur_level: int    = SaveManager.get_upgrade_level(id) if SaveManager else 0
	var light:     int    = SaveManager.get_light()           if SaveManager else 0
	var maxed:     bool   = cur_level >= max_level
	var can_buy:   bool   = not maxed and light >= cost

	# Card container — bumped contrast vs the screen's dark root so
	# cards read clearly. Old values (bg 0.12/0.10/0.16 on root
	# 0.05/0.04/0.08) only had ~0.07 lightness delta and the border
	# was muted purple — the entire upgrade list looked "smudged".
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 150)

	var style := StyleBoxFlat.new()
	# Brighter bg + warmer tint so each card pops off the dark menu.
	style.bg_color = Color(0.18, 0.14, 0.22) if not maxed else Color(0.13, 0.18, 0.14)
	# 2 px border in stronger purple/green so the card boundary is
	# unambiguous even on small phones.
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_color = (
			Color(0.62, 0.48, 0.86) if not maxed else Color(0.42, 0.78, 0.42))
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 12)
	style.content_margin_left   = 22.0
	style.content_margin_right  = 22.0
	style.content_margin_top    = 16.0
	style.content_margin_bottom = 16.0
	# Soft drop shadow so each card reads as elevated above the
	# scroll bg — same treatment HeroCard got.
	style.shadow_color  = Color(0.0, 0.0, 0.0, 0.4)
	style.shadow_size   = 5
	style.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	card.add_child(hbox)

	# Left: name + desc + level dots
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 8)
	hbox.add_child(info)

	var lbl_name := Label.new()
	lbl_name.theme_type_variation = "SectionLabel"
	lbl_name.text = upgrade_name
	# Override gold from SectionLabel — bright white-purple for unmaxed,
	# bright green for maxed, both with a subtle outline for legibility.
	lbl_name.add_theme_color_override("font_color",
		Color("#88FF88") if maxed else Color(1.0, 0.98, 1.0))
	lbl_name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	lbl_name.add_theme_constant_override("outline_size", 3)
	info.add_child(lbl_name)

	# Description — was using BodyLabel (TEXT_SECONDARY) which read OK
	# on the lighter card bg before but now needs explicit brightness
	# bump + outline so the text doesn't smudge into the bg.
	var lbl_desc := Label.new()
	lbl_desc.theme_type_variation = "BodyLabel"
	lbl_desc.text = desc
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_desc.add_theme_color_override("font_color", Color(0.92, 0.88, 0.96))
	lbl_desc.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	lbl_desc.add_theme_constant_override("outline_size", 2)
	info.add_child(lbl_desc)

	# Level dots (for multi-level upgrades)
	if max_level > 1:
		var dots_row := HBoxContainer.new()
		dots_row.add_theme_constant_override("separation", 6)
		info.add_child(dots_row)
		for i in max_level:
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(18, 18)
			# Bright green for filled, brighter empty so the level
			# indicator is unambiguous at-a-glance.
			dot.color = (
					Color("#A0FF80") if i < cur_level
					else Color(0.42, 0.38, 0.50))
			dots_row.add_child(dot)

	# Right: buy button
	var btn := _make_buy_btn(id, cost, cur_level, max_level, can_buy, maxed)
	hbox.add_child(btn)

	return card

func _make_buy_btn(id: String, cost: int, cur_level: int, max_level: int,
		can_buy: bool, maxed: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 96)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)

	var s := StyleBoxFlat.new()
	s.corner_radius_top_left    = 8
	s.corner_radius_top_right   = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8

	if maxed:
		btn.text = "МАКС"
		s.bg_color = Color(0.18, 0.30, 0.18)
		s.border_color = Color(0.42, 0.78, 0.42)
		s.border_width_left = 2; s.border_width_right = 2
		s.border_width_top  = 2; s.border_width_bottom = 2
		btn.add_theme_color_override("font_color", Color("#88FF88"))
		btn.disabled = true
	elif can_buy:
		btn.text = "💡 %d\nКупити" % cost
		# Bright affordable-purple — clearly differentiates from the
		# darker disabled state below. 2 px border for parity with the
		# card's own border weight.
		s.bg_color = Color(0.32, 0.22, 0.48)
		s.border_color = Color(0.82, 0.60, 1.0)
		s.border_width_left   = 2; s.border_width_right  = 2
		s.border_width_top    = 2; s.border_width_bottom = 2
		btn.add_theme_color_override("font_color", Color(1.0, 0.92, 1.0))
		btn.pressed.connect(_on_buy.bind(id, cost, cur_level, max_level))
	else:
		btn.text = "💡 %d" % cost
		s.bg_color = Color(0.12, 0.11, 0.15)
		btn.add_theme_color_override("font_color", Color(0.40, 0.38, 0.46))
		btn.disabled = true

	for state in ["normal","hover","pressed","focus","disabled"]:
		btn.add_theme_stylebox_override(state, s)

	return btn

# ── Buy ───────────────────────────────────────────────────────────────────────

func _on_buy(id: String, cost: int, cur_level: int, _max_level: int) -> void:
	if not SaveManager:
		return
	if not SaveManager.spend_light(cost):
		_flash_currency()
		return
	SaveManager.set_upgrade_level(id, cur_level + 1)
	_refresh_currency()
	_rebuild_cards(_active_cat)

func _flash_currency() -> void:
	var tw := create_tween()
	tw.tween_property(_lbl_currency, "modulate", Color("#FF6644"), 0.1)
	tw.tween_property(_lbl_currency, "modulate", Color.WHITE,      0.3)

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
	_build_cat_tabs(vbox)
	_build_cards_area(vbox)

func _build_header(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   24)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",    14)
	margin.add_theme_constant_override("margin_bottom", 14)
	parent.add_child(margin)

	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 80
	hdr.add_theme_constant_override("separation", 18)
	margin.add_child(hdr)

	# Display + outline from theme — keeps the screen-title weight.
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "Апгрейди"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	_lbl_currency = Label.new()
	_lbl_currency.theme_type_variation = "SectionLabel"
	_lbl_currency.text = "💡 0"
	_lbl_currency.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(_lbl_currency)

	# IconButton variation = empty styleboxes + muted colours.
	var btn_close := Button.new()
	btn_close.theme_type_variation = "IconButton"
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(72, 72)
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_cat_tabs(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 84
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	scroll.add_child(row)

	var lm := Control.new(); lm.custom_minimum_size.x = 16
	row.add_child(lm)

	var cat_icons := ["⚔️", "💪", "👻", "🙏", "🌑", "👁"]
	var cat_names := ["Посох", "Тіло", "Душа", "Молитва", "Хитрість", "Провидіння"]

	for i in _categories.size():
		var cat: Dictionary = _categories[i]
		var icon: String = cat_icons[i] if i < cat_icons.size() else ""
		var cat_label: String = cat.get("name", cat_names[i] if i < cat_names.size() else "")

		var btn := Button.new()
		btn.text = "%s %s" % [icon, cat_label]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 22)

		var n := StyleBoxFlat.new()
		n.bg_color = Color(0.14, 0.12, 0.20)
		n.corner_radius_top_left    = 10
		n.corner_radius_top_right   = 10
		n.corner_radius_bottom_left = 10
		n.corner_radius_bottom_right = 10
		n.content_margin_left   = 20.0
		n.content_margin_right  = 20.0
		n.content_margin_top    = 8.0
		n.content_margin_bottom = 8.0
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = Color(0.22, 0.18, 0.30)
		for state in ["normal","hover","pressed","focus"]:
			btn.add_theme_stylebox_override(state, n if state in ["normal","focus"] else h)
		btn.add_theme_color_override("font_color", Color(0.84, 0.82, 0.90))

		var idx := i
		btn.pressed.connect(func() -> void: _switch_category(idx))
		row.add_child(btn)
		_cat_tabs.append(btn)

	var rm := Control.new(); rm.custom_minimum_size.x = 16
	row.add_child(rm)

func _build_cards_area(parent: VBoxContainer) -> void:
	_cards_scroll = ScrollContainer.new()
	_cards_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_cards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_cards_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   20)
	margin.add_theme_constant_override("margin_right",  20)
	margin.add_theme_constant_override("margin_top",    16)
	margin.add_theme_constant_override("margin_bottom", 110)  # space above ad banner
	_cards_scroll.add_child(margin)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 14)
	margin.add_child(_cards_box)
