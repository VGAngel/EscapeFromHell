extends CanvasLayer

# Accessed from MainMenu via BtnDonate.
# Reads donation tiers from AdsManager (which loads monetization_config.json).
# Actual prices come from Google Play Console — not stored locally.
# Purchases go through AdsManager.purchase_donate(sku).

signal closed

# ── Tier metadata (icon + copy, price shown by billing) ──────────────────────
const TIER_META := {
	"donate_1":  { "icon": "🕯",  "name": "Свічка",   "desc": "Маленький вогник у темряві" },
	"donate_3":  { "icon": "📿",  "name": "Чотки",    "desc": "Молитва за розробника" },
	"donate_5":  { "icon": "✝",   "name": "Хрест",    "desc": "Благословення проекту" },
	"donate_10": { "icon": "👼",  "name": "Ангел",    "desc": "Ти справжній ангел" },
}

const FADE_DURATION := 0.3

# ── State ─────────────────────────────────────────────────────────────────────
var _thank_timer: float = 0.0
var _showing_thanks: bool = false

# ── UI refs ───────────────────────────────────────────────────────────────────
var _root:        ColorRect = null
var _cards_box:   VBoxContainer = null
var _lbl_thanks:  Label = null

# ── Init ──────────────────────────────────────────────────────────────────────

# Loc.t() with explicit fallback so headless tests / boot without the
# autoload still render correctly.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	# Use the global `Loc` autoload directly so this resolves correctly
	# from outside the active scene tree (unit tests, scene transitions).
	# The previous get_node_or_null("/root/Loc") form errored "Can't
	# use get_node() with absolute paths from outside the active scene
	# tree" on detached instances and returned null → fell through to
	# the raw key string.
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key


func _ready() -> void:
	layer   = 10
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	if AdsManager and AdsManager.has_signal("donate_purchased"):
		AdsManager.donate_purchased.connect(_on_donate_purchased)
	# Live re-render on language switch — re-set tracked label texts.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	# Title and tagline are rebuilt next time we open from a fresh
	# state — for now, just refresh the dynamic thank-you message and
	# any "Підтримати" buttons we pushed into _cards_box.
	if _lbl_thanks and _showing_thanks:
		_lbl_thanks.text = _t("donate.thanks", {},
				"Дякуємо ❤\nТвоя підтримка\nдуже важлива")
	for card in _cards_box.get_children():
		for btn in card.find_children("", "Button", true, false):
			btn.text = _t("donate.btn_support", {}, "Підтримати")

# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.donate"))
	return "Підтримати"

func open() -> void:
	visible = true
	_lbl_thanks.visible = false
	_showing_thanks = false
	_rebuild_cards()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit()
	)

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _showing_thanks:
		_thank_timer -= delta
		if _thank_timer <= 0.0:
			_showing_thanks = false
			_lbl_thanks.visible = false
			_rebuild_cards()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ── Cards ─────────────────────────────────────────────────────────────────────

func _rebuild_cards() -> void:
	for child in _cards_box.get_children():
		child.queue_free()

	var tiers: Array = AdsManager.get_donate_tiers() if AdsManager else []
	if tiers.is_empty():
		# Fallback: show all known tiers even without AdsManager
		for sku in TIER_META.keys():
			_cards_box.add_child(_make_card(sku))
		return

	for tier in tiers:
		var sku: String = tier.get("sku", "")
		if sku != "":
			_cards_box.add_child(_make_card(sku))

func _make_card(sku: String) -> Control:
	var meta: Dictionary = TIER_META.get(sku, {
		"icon": "🙏", "name": sku, "desc": ""
	})
	var icon: String = meta["icon"]
	var tier_name: String = meta["name"]
	var desc: String = meta["desc"]

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 76)

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.10, 0.09, 0.15)
	style.border_color = Color(0.38, 0.28, 0.52)
	for side in ["left","right","top","bottom"]:
		style.set("border_width_" + side, 1)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, 10)
	style.content_margin_left   = 16.0
	style.content_margin_right  = 12.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# Icon
	var lbl_icon := Label.new()
	lbl_icon.text = icon
	lbl_icon.add_theme_font_size_override("font_size", 42)
	lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_icon.custom_minimum_size = Vector2(40, 0)
	lbl_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(lbl_icon)

	# Name + description
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	hbox.add_child(vbox)

	var lbl_name := Label.new()
	lbl_name.text = tier_name
	lbl_name.add_theme_font_size_override("font_size", 24)
	lbl_name.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	vbox.add_child(lbl_name)

	var lbl_desc := Label.new()
	lbl_desc.text = desc
	lbl_desc.add_theme_font_size_override("font_size", 18)
	lbl_desc.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	vbox.add_child(lbl_desc)

	# Buy button
	var btn := _make_buy_btn(sku)
	hbox.add_child(btn)

	return card

func _make_buy_btn(sku: String) -> Button:
	var btn := Button.new()
	btn.text = _t("donate.btn_support", {}, "Підтримати")
	btn.custom_minimum_size = Vector2(100, 48)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 20)

	var s := StyleBoxFlat.new()
	s.bg_color     = Color(0.18, 0.12, 0.28)
	s.border_color = Color(0.52, 0.36, 0.72)
	for side in ["left","right","top","bottom"]:
		s.set("border_width_" + side, 1)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		s.set("corner_radius_" + corner, 8)

	var h := s.duplicate() as StyleBoxFlat
	h.bg_color     = Color(0.26, 0.18, 0.38)
	h.border_color = Color(0.70, 0.50, 0.90)

	btn.add_theme_stylebox_override("normal",   s)
	btn.add_theme_stylebox_override("focus",    s)
	btn.add_theme_stylebox_override("pressed",  s)
	btn.add_theme_stylebox_override("hover",    h)
	btn.add_theme_stylebox_override("disabled", s)
	btn.add_theme_color_override("font_color", Color(0.86, 0.78, 1.00))

	btn.pressed.connect(func() -> void: _on_tier_pressed(sku))
	return btn

# ── Purchase ──────────────────────────────────────────────────────────────────

func _on_tier_pressed(sku: String) -> void:
	if AdsManager and AdsManager.has_method("purchase_donate"):
		AdsManager.purchase_donate(sku)
	# Buttons are replaced by thanks overlay once AdsManager fires donate_purchased

func _on_donate_purchased(_sku: String) -> void:
	_show_thanks()

func _show_thanks() -> void:
	_showing_thanks  = true
	_thank_timer     = 3.5
	_lbl_thanks.text = _t("donate.thanks", {},
			"Дякуємо ❤\nТвоя підтримка\nдуже важлива")
	_lbl_thanks.visible = true

	# Clear cards to make thanks label prominent
	for child in _cards_box.get_children():
		child.queue_free()

	var tw := create_tween()
	tw.tween_property(_lbl_thanks, "modulate:a", 1.0, 0.4)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.0, 0.0, 0.0, 0.72)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Sheet panel — bottom sheet style, anchored center-ish
	var sheet := PanelContainer.new()
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_top    = -520.0
	sheet.offset_bottom = -60.0   # above ad banner
	sheet.offset_left   = 24.0
	sheet.offset_right  = -24.0

	var sheet_style := StyleBoxFlat.new()
	sheet_style.bg_color     = Color(0.07, 0.06, 0.11)
	sheet_style.border_color = Color(0.38, 0.28, 0.52)
	for side in ["left","right","top","bottom"]:
		sheet_style.set("border_width_" + side, 1)
	sheet_style.corner_radius_top_left  = 18
	sheet_style.corner_radius_top_right = 18
	sheet_style.content_margin_left   = 0.0
	sheet_style.content_margin_right  = 0.0
	sheet_style.content_margin_top    = 0.0
	sheet_style.content_margin_bottom = 0.0
	sheet.add_theme_stylebox_override("panel", sheet_style)
	_root.add_child(sheet)

	var outer := VBoxContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 0)
	sheet.add_child(outer)

	_build_header(outer)
	_build_intro(outer)
	_build_cards_area(outer)
	_build_thanks_label(outer)

func _build_header(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  10)
	margin.add_theme_constant_override("margin_top",    10)
	margin.add_theme_constant_override("margin_bottom",  6)
	parent.add_child(margin)

	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 44
	margin.add_child(hdr)

	var title := Label.new()
	title.text = _t("donate.title", {}, "Пожертвувати")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(44, 44)
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.add_theme_font_size_override("font_size", 27)
	var empty := StyleBoxEmpty.new()
	for state in ["normal","hover","pressed","focus"]:
		btn_close.add_theme_stylebox_override(state, empty)
	btn_close.add_theme_color_override("font_color", Color(0.50, 0.47, 0.58))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_intro(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   16)
	margin.add_theme_constant_override("margin_right",  16)
	margin.add_theme_constant_override("margin_top",     0)
	margin.add_theme_constant_override("margin_bottom", 12)
	parent.add_child(margin)

	var lbl := Label.new()
	lbl.text = _t("donate.tagline", {},
			"Гра безкоштовна і завжди такою залишиться.\nЯкщо хочеш підтримати розробника — це тут.")
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.58, 0.55, 0.66))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	margin.add_child(lbl)

func _build_cards_area(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",   12)
	margin.add_theme_constant_override("margin_right",  12)
	margin.add_theme_constant_override("margin_top",     4)
	margin.add_theme_constant_override("margin_bottom", 12)
	scroll.add_child(margin)

	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	margin.add_child(_cards_box)

func _build_thanks_label(parent: VBoxContainer) -> void:
	_lbl_thanks = Label.new()
	_lbl_thanks.text = ""
	_lbl_thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_thanks.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_lbl_thanks.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	_lbl_thanks.add_theme_font_size_override("font_size", 33)
	_lbl_thanks.add_theme_color_override("font_color", Color("#FFD700"))
	_lbl_thanks.modulate.a = 0.0
	_lbl_thanks.visible    = false
	parent.add_child(_lbl_thanks)
