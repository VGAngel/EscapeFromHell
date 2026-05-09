extends CanvasLayer

# Attach to a CanvasLayer (layer = 10) added as child of Level.tscn.
# Open/close via toggle() or connect to HUD.pause_requested.
#
# Layout (panel, buttons, sin bar, confirm popup) lives entirely in
# scenes/ui/PauseScreen.tscn — open that to retheme. This script only
# fills label text, scales the sin bar, and wires button signals.
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
const SIN_BAR_WIDTH  := 220.0

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _root:           ColorRect      = $Backdrop
@onready var _main_panel:     PanelContainer = $Backdrop/MainCenterer/MainPanel
@onready var _lbl_title:      Label          = $Backdrop/MainCenterer/MainPanel/VBox/Title
@onready var _lbl_level:      Label          = $Backdrop/MainCenterer/MainPanel/VBox/LevelLabel
@onready var _lbl_souls:      Label          = $Backdrop/MainCenterer/MainPanel/VBox/SoulsLabel
@onready var _lbl_type_strip: Label          = $Backdrop/MainCenterer/MainPanel/VBox/TypeStrip
@onready var _sin_bar_bg:     ColorRect      = $Backdrop/MainCenterer/MainPanel/VBox/SinRow/SinBarBg
@onready var _sin_bar:        ColorRect      = $Backdrop/MainCenterer/MainPanel/VBox/SinRow/SinBarBg/SinBar
@onready var _lbl_sin_pct:    Label          = $Backdrop/MainCenterer/MainPanel/VBox/SinRow/SinPercent
@onready var _btn_resume:     Button         = $Backdrop/MainCenterer/MainPanel/VBox/ResumeButton
@onready var _btn_collection: Button         = $Backdrop/MainCenterer/MainPanel/VBox/CollectionButton
@onready var _btn_statistics: Button         = $Backdrop/MainCenterer/MainPanel/VBox/StatisticsButton
@onready var _btn_settings:   Button         = $Backdrop/MainCenterer/MainPanel/VBox/SettingsButton
@onready var _btn_menu:       Button         = $Backdrop/MainCenterer/MainPanel/VBox/MenuButton

@onready var _confirm_centerer: CenterContainer = $Backdrop/ConfirmCenterer
@onready var _confirm_panel:    PanelContainer  = $Backdrop/ConfirmCenterer/ConfirmPanel
@onready var _lbl_exit_title:   Label           = $Backdrop/ConfirmCenterer/ConfirmPanel/VBox/ExitTitle
@onready var _lbl_exit_msg:     Label           = $Backdrop/ConfirmCenterer/ConfirmPanel/VBox/ExitMessage
@onready var _btn_exit_yes:     Button          = $Backdrop/ConfirmCenterer/ConfirmPanel/VBox/ExitButtons/ExitYesButton
@onready var _btn_exit_no:      Button          = $Backdrop/ConfirmCenterer/ConfirmPanel/VBox/ExitButtons/ExitNoButton

# ── State ─────────────────────────────────────────────────────────────────────
var _visible_flag: bool = false
var _tween:        Tween = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_localised_text()
	_adapt_button_sizes()
	_btn_resume.pressed.connect(_on_resume_pressed)
	_btn_collection.pressed.connect(_on_collection_pressed)
	_btn_statistics.pressed.connect(_on_statistics_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_menu.pressed.connect(_on_menu_pressed)
	_btn_exit_yes.pressed.connect(_on_exit_yes_pressed)
	_btn_exit_no.pressed.connect(_on_exit_no_pressed)
	_root.modulate.a = 0.0
	visible = false
	_confirm_panel.visible = false
	# Live refresh on language switch from Settings.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


# Adaptive sizing: on narrow viewports (<700 px = phone portrait) the
# panel is constrained, so shrink the touch target and font so all five
# buttons fit. .tscn ships with desktop defaults (540×96 / font 32).
func _adapt_button_sizes() -> void:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	if vp_w >= 700.0:
		return
	for btn: Button in [_btn_resume, _btn_collection, _btn_statistics, _btn_settings, _btn_menu]:
		btn.custom_minimum_size = Vector2(420, 78)
		btn.add_theme_font_size_override("font_size", 26)


func _apply_localised_text() -> void:
	_lbl_title.text       = _t("pause.title", {}, "ПАУЗА")
	_btn_resume.text      = _t("pause.resume",     {}, "Продовжити")
	_btn_collection.text  = _t("pause.collection", {}, "Врятовані Душі")
	_btn_statistics.text  = _t("pause.statistics", {}, "📊  Статистика")
	_btn_settings.text    = _t("pause.settings",   {}, "Налаштування")
	_btn_menu.text        = _t("pause.main_menu",  {}, "Головне Меню")
	_lbl_exit_title.text  = _t("pause.exit_title", {}, "Вийти з рівня?")
	_lbl_exit_msg.text    = _t("pause.exit_message", {},
			"Зібрані душі збережені.\nДуша в руках — буде втрачена.")
	_btn_exit_yes.text    = _t("pause.exit_yes", {}, "Вийти")
	_btn_exit_no.text     = _t("pause.exit_no",  {}, "Залишитись")


func _on_language_changed(_lang: String) -> void:
	_apply_localised_text()
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

	var souls:    int = SaveManager.get_total_souls()         if SaveManager else 0
	var target:   int = SaveManager.get_named_souls_target()  if SaveManager else 100
	var hidden:   int = SaveManager.get_total_hidden_souls()  if SaveManager else 0
	var h_target: int = SaveManager.get_hidden_souls_target() if SaveManager else 20

	# Combined progress line: named + hidden + grand total, all on one
	# row so the player sees full standing without leaving pause.
	_lbl_souls.text = _t("pause.souls_format", {
		"found": souls, "total": target,
		"hidden": hidden, "hidden_total": h_target,
		"grand": souls + hidden, "grand_total": target + h_target,
	}, "👻 %d/%d  •  ✦ %d/%d  •  ∑ %d/%d" % [
		souls, target, hidden, h_target, souls + hidden, target + h_target,
	])

	_refresh_type_strip()

	var sin_val := SaveManager.get_sin() if SaveManager else 0.0
	_set_sin(sin_val)


# Build "🔥 24/40  •  💀 18/35  •  😴 8/25" from the LevelGenerator's
# loaded named-soul list. Categories with zero total are skipped so the
# strip stays compact when the JSON is sparse / under test.
func _refresh_type_strip() -> void:
	if not _lbl_type_strip:
		return
	var lg: Node = get_node_or_null("/root/LevelGenerator")
	if not lg or not lg.has_method("get_named_souls"):
		_lbl_type_strip.text = ""
		return
	var named: Array = lg.get_named_souls()
	var saved_ids: Array = SaveManager.get_saved_soul_ids() if SaveManager else []

	var totals: Dictionary = {"innocent": 0, "broken": 0, "sleeping": 0}
	var saved:  Dictionary = {"innocent": 0, "broken": 0, "sleeping": 0}
	for soul: Dictionary in named:
		var t: String = String(soul.get("type", ""))
		if not totals.has(t):
			continue
		totals[t] = int(totals[t]) + 1
		if int(soul.get("id", 0)) in saved_ids:
			saved[t] = int(saved[t]) + 1

	var icons: Dictionary = {"innocent": "🔥", "broken": "💀", "sleeping": "😴"}
	var parts: PackedStringArray = []
	for k in ["innocent", "broken", "sleeping"]:
		var tot: int = int(totals[k])
		if tot <= 0:
			continue
		parts.append("%s %d/%d" % [icons[k], int(saved[k]), tot])
	_lbl_type_strip.text = "  •  ".join(parts)

func _set_sin(value: float) -> void:
	var ratio := clampf(value / 100.0, 0.0, 1.0)
	_sin_bar.size.x = SIN_BAR_WIDTH * ratio
	_sin_bar.color = _sin_color(value)
	_lbl_sin_pct.text = _t("pause.sin_format",
			{"pct": int(value)}, "%.0f%%" % value)


# Helper — Loc.t() with a guaranteed fallback so headless tests / boot
# scenarios without the autoload still render correctly.
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
