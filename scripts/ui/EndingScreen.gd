extends Control

# Final screen shown after level 100 completes. Reads the ending id from
# GameManager.pending_ending and applies the matching title + epitaph from
# the local endings table.
#
# UI lives in scenes/endings/EndingScreen.tscn — open that file to tweak
# layout, colours, padding. This script only swaps text/colour at runtime
# based on which of the six endings the player triggered.

# Accent colour per ending — applied to the Title label at runtime. Title
# and description text come through Loc.t() so both follow the active
# language; FALLBACK_UA covers headless tests / boot before Loc is up.
const ENDING_COLORS := {
	"saint":    Color("#FFD700"),
	"redeemed": Color("#CCCCFF"),
	"bound":    Color("#A088C8"),
	"fallen":   Color("#CC3322"),
	"traitor":  Color("#884466"),
	"rebel":    Color("#66EECC"),
}

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

@onready var _preheader:   Label  = $Centerer/VBox/Preheader
@onready var _title:       Label  = $Centerer/VBox/Title
@onready var _description: Label  = $Centerer/VBox/Description
@onready var _menu_button: Button = $Centerer/VBox/MenuButton

func _ready() -> void:
	if GameManager:
		_ending_id = GameManager.pending_ending if GameManager.pending_ending != "" else "saint"
		GameManager.pending_ending = ""

	var id: String = _ending_id if ENDING_COLORS.has(_ending_id) else "saint"
	var accent: Color = ENDING_COLORS.get(id, Color.WHITE)
	var fb: Dictionary = FALLBACK_UA.get(id, {"title": "", "desc": ""})

	_preheader.text  = _t("endings.preheader", {}, "— Кінцівка —")
	_title.text      = _t("endings." + id + "_title", {}, fb.get("title", ""))
	_title.add_theme_color_override("font_color", accent)
	_description.text = _t("endings." + id + "_desc", {}, fb.get("desc", ""))
	_menu_button.text = _t("endings.btn_main_menu", {}, "У головне меню")
	_menu_button.pressed.connect(_on_menu_pressed)

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, FADE_DURATION)


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func _on_menu_pressed() -> void:
	if GameManager:
		GameManager.load_main_menu()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
