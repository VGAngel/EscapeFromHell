extends Control

# Final-screen shown after level 100 completes. Reads the ending id from
# GameManager.pending_ending (set by _trigger_ending) and displays the
# matching title + epitaph from the local endings table. Any of the six
# endings can be shown — the id drives both text and accent colour.

# Accent colour per ending — the only piece that doesn't go through Loc.
# Title/description are pulled from `endings.{id}_title` / `endings.{id}_desc`
# at render time so they follow the active language.
const ENDING_COLORS := {
	"saint":    Color("#FFD700"),
	"redeemed": Color("#CCCCFF"),
	"bound":    Color("#A088C8"),
	"fallen":   Color("#CC3322"),
	"traitor":  Color("#884466"),
	"rebel":    Color("#66EECC"),
}

# UA fallback strings for headless tests / boot before Loc is up.
const FALLBACK_UA := {
	"saint":    {"title": "Прощення",    "desc": "Ти повернувся. Не таким як пішов — кращим."},
	"redeemed": {"title": "Другий шанс", "desc": "Ти отримав те чого просив. Нове життя. Без пам'яті про те що зробив для цього."},
	"bound":    {"title": "Між світами", "desc": "Ні пекло ні рай. Ти знаєш чому."},
	"fallen":   {"title": "Новий Демон", "desc": "Люцифер сміється. Ти врятував їх. Але загубив себе."},
	"traitor":  {"title": "Угода",       "desc": "Ти залишився. Але не так як планував."},
	"rebel":    {"title": "Третій шлях", "desc": "Ніхто не чекав цього. Навіть Він."},
}

const FADE_DURATION := 1.2

var _ending_id: String = "saint"

func _ready() -> void:
	if GameManager:
		_ending_id = GameManager.pending_ending if GameManager.pending_ending != "" else "saint"
		GameManager.pending_ending = ""
	_build_ui()
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func _build_ui() -> void:
	var id: String = _ending_id if ENDING_COLORS.has(_ending_id) else "saint"
	var accent: Color = ENDING_COLORS.get(id, Color.WHITE)
	var fallback: Dictionary = FALLBACK_UA.get(id, {"title": "", "desc": ""})
	var title_text: String = _t(
			"endings." + id + "_title", {}, fallback.get("title", ""))
	var desc_text: String = _t(
			"endings." + id + "_desc", {}, fallback.get("desc", ""))

	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.04, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# CenterContainer fills the screen and re-centers its child whenever
	# the viewport size changes (resolution switch).
	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(centerer)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	vbox.custom_minimum_size = Vector2(560, 0)
	centerer.add_child(vbox)

	var lbl_pre := Label.new()
	lbl_pre.text = _t("endings.preheader", {}, "— Кінцівка —")
	lbl_pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_pre.add_theme_font_size_override("font_size", 13)
	lbl_pre.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	vbox.add_child(lbl_pre)

	var lbl_title := Label.new()
	lbl_title.text = title_text
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 42)
	lbl_title.add_theme_color_override("font_color", accent)
	vbox.add_child(lbl_title)

	var lbl_desc := Label.new()
	lbl_desc.text = desc_text
	lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_desc.add_theme_font_size_override("font_size", 15)
	lbl_desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.90))
	lbl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl_desc.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(lbl_desc)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 30
	vbox.add_child(spacer)

	var btn := Button.new()
	btn.text = _t("endings.btn_main_menu", {}, "У головне меню")
	btn.custom_minimum_size = Vector2(240, 52)
	btn.add_theme_font_size_override("font_size", 15)
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.12, 0.10, 0.16)
	n.border_color = Color(0.45, 0.35, 0.60)
	n.border_width_left   = 1
	n.border_width_right  = 1
	n.border_width_top    = 1
	n.border_width_bottom = 1
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		n.set("corner_radius_" + corner, 10)
	for state in ["normal","hover","pressed","focus"]:
		btn.add_theme_stylebox_override(state, n)
	btn.add_theme_color_override("font_color", Color(0.90, 0.88, 0.96))
	btn.pressed.connect(_on_menu_pressed)
	vbox.add_child(btn)

func _on_menu_pressed() -> void:
	if GameManager:
		GameManager.load_main_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
