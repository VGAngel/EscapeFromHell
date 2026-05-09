extends CanvasLayer

# Seed dialog — shown from MainMenu "Seed" button.
# Player types any string; it gets hashed to an int that XORs with
# level_id in LevelGenerator, making every room layout reproducible
# when the same seed is shared between players.
#
# Empty seed → default deterministic-per-level behaviour (no XOR).

signal closed

const FADE_DURATION := 0.3

var _root:      ColorRect = null
var _edit:      LineEdit  = null
var _lbl_info:  Label     = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	# Live re-render the dynamic info label on language switch.
	# Static labels (title, button) re-render next time the dialog opens.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	if _edit:
		_update_info(_edit.text)

# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.seed"))
	return "Зерно світу"

func open() -> void:
	visible = true
	_refresh()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)
	if _edit:
		_edit.grab_focus()

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

# ── Actions ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not SaveManager:
		return
	var current: String = SaveManager.get_world_seed_str()
	if _edit:
		_edit.text = current
	_update_info(current)

func _apply() -> void:
	if not SaveManager or not _edit:
		return
	var value: String = _edit.text.strip_edges()
	SaveManager.set_world_seed_str(value)
	_update_info(value)
	close()

func _randomize_seed() -> void:
	var chars := "abcdefghijklmnopqrstuvwxyz0123456789"
	var result := ""
	for _i in 8:
		result += chars[randi() % chars.length()]
	if _edit:
		_edit.text = result
	_update_info(result)

func _clear_seed() -> void:
	if _edit:
		_edit.text = ""
	_update_info("")

func _update_info(value: String) -> void:
	if not _lbl_info:
		return
	if value.is_empty():
		_lbl_info.text = _t("seed.info_auto", {},
				"Авторежим: кожен рівень має унікальне розміщення на основі його ID.")
	else:
		_lbl_info.text = _t("seed.info_format",
				{"seed": value, "hash": hash(value)},
				"Seed «%s» → hash %d. Поділіться seed зі іншим гравцем — отримаєте однакові рівні." % [value, hash(value)])


# Loc.t() with fallback so headless tests / boot without Loc still render.
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

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.05, 0.04, 0.08, 0.97)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# CenterContainer fills the screen and re-centers the card automatically
	# whenever the viewport size changes (resolution switch).
	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(centerer)

	# Centred card
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.10, 0.08, 0.14)
	card_style.border_width_left   = 1
	card_style.border_width_right  = 1
	card_style.border_width_top    = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.40, 0.32, 0.58)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		card_style.set("corner_radius_" + corner, 14)
	card_style.content_margin_left   = 20.0
	card_style.content_margin_right  = 20.0
	card_style.content_margin_top    = 20.0
	card_style.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", card_style)
	centerer.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	# Title row
	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)

	var title := Label.new()
	title.text = _t("seed.title", {}, "🌱 Seed рівня")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	hdr.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(36, 36)
	btn_close.add_theme_font_size_override("font_size", 24)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		btn_close.add_theme_stylebox_override(state, empty)
	btn_close.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

	# Input row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = _t("seed.placeholder", {},
			"Введіть seed або залиште порожнім…")
	_edit.add_theme_font_size_override("font_size", 22)
	_edit.text_submitted.connect(func(_ignored: String) -> void: _apply())
	row.add_child(_edit)

	var btn_rand := _action_btn("🎲", Color(0.15, 0.15, 0.24))
	btn_rand.tooltip_text = _t("seed.tt_random", {}, "Випадковий seed")
	btn_rand.pressed.connect(_randomize_seed)
	row.add_child(btn_rand)

	var btn_clear := _action_btn("✕", Color(0.20, 0.10, 0.10))
	btn_clear.tooltip_text = _t("seed.tt_clear", {}, "Скинути (авторежим)")
	btn_clear.pressed.connect(_clear_seed)
	row.add_child(btn_clear)

	# Info label
	_lbl_info = Label.new()
	_lbl_info.add_theme_font_size_override("font_size", 18)
	_lbl_info.add_theme_color_override("font_color", Color(0.55, 0.53, 0.62))
	_lbl_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_info.text = _t("seed.info_auto", {},
			"Авторежим: кожен рівень має унікальне розміщення на основі його ID.")
	vbox.add_child(_lbl_info)

	# Apply button
	var btn_apply := Button.new()
	btn_apply.text = _t("seed.btn_apply", {}, "Застосувати")
	btn_apply.custom_minimum_size = Vector2(0, 52)
	btn_apply.add_theme_font_size_override("font_size", 24)
	btn_apply.add_theme_color_override("font_color", Color(0.90, 0.80, 1.00))
	var apply_style := StyleBoxFlat.new()
	apply_style.bg_color = Color(0.22, 0.16, 0.34)
	apply_style.border_width_left   = 1; apply_style.border_width_right  = 1
	apply_style.border_width_top    = 1; apply_style.border_width_bottom = 1
	apply_style.border_color = Color(0.55, 0.38, 0.78)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		apply_style.set("corner_radius_" + corner, 10)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn_apply.add_theme_stylebox_override(state, apply_style)
	btn_apply.pressed.connect(_apply)
	vbox.add_child(btn_apply)

func _action_btn(icon: String, bg: Color) -> Button:
	var btn := Button.new()
	btn.text = icon
	btn.custom_minimum_size = Vector2(44, 44)
	btn.add_theme_font_size_override("font_size", 24)
	btn.focus_mode = Control.FOCUS_NONE
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s.set("corner_radius_" + corner, 8)
	for state in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(state, s)
	return btn
