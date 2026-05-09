extends CanvasLayer

# Attach to a CanvasLayer (layer = 10) inside Level.tscn.
# Show via show_results(stats) called by GameManager after level_completed
# signal.
#
# Expected stats Dictionary keys (from GameManager.complete_level):
#   level_id, circle, souls_found, souls_total, deaths,
#   sin_delta, sin_total, light_earned, time_seconds, stars
#
# UI layout (panel, stars row, stats VBox, buttons) is fully declared in
# scenes/ui/LevelComplete.tscn — open that file to retheme. This script
# only fills label text, animates the reveal sequence, and wires button
# signals.

signal next_level_pressed
signal hub_pressed

const FADE_DURATION      := 0.5
const STAR_DELAY         := 0.3
const STAT_DELAY         := 0.2
const STAR_FILLED        := "★"
const STAR_EMPTY         := "☆"

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _root:         ColorRect = $Backdrop
@onready var _lbl_title:    Label     = $Backdrop/Centerer/Panel/VBox/Title
@onready var _lbl_subtitle: Label     = $Backdrop/Centerer/Panel/VBox/Subtitle
@onready var _stars_row:    HBoxContainer = $Backdrop/Centerer/Panel/VBox/Stars
@onready var _stat_souls:   Label     = $Backdrop/Centerer/Panel/VBox/Stats/Souls
@onready var _stat_deaths:  Label     = $Backdrop/Centerer/Panel/VBox/Stats/Deaths
@onready var _stat_time:    Label     = $Backdrop/Centerer/Panel/VBox/Stats/Time
@onready var _stat_best:    Label     = $Backdrop/Centerer/Panel/VBox/Stats/Best
@onready var _stat_sin:     Label     = $Backdrop/Centerer/Panel/VBox/Stats/Sin
@onready var _stat_light:   Label     = $Backdrop/Centerer/Panel/VBox/Stats/Light
@onready var _new_best_badge: Label   = $Backdrop/Centerer/Panel/VBox/Stats/NewBestBadge
@onready var _btn_hub:      Button    = $Backdrop/Centerer/Panel/VBox/Buttons/HubButton
@onready var _btn_next:     Button    = $Backdrop/Centerer/Panel/VBox/Buttons/NextButton

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	_lbl_title.text = _t("level_complete.title_done", {}, "РІВЕНЬ ПРОЙДЕНО")
	_new_best_badge.text = _t(
			"level_complete.new_best_badge", {}, "✨ НОВИЙ РЕКОРД ✨")
	_btn_hub.text  = _t("level_complete.go_to_hub",  {}, "Хаб Раю")
	_btn_next.text = _t("level_complete.next_level", {}, "Далі →")
	_btn_hub.pressed.connect(_on_hub_pressed)
	_btn_next.pressed.connect(_on_next_pressed)
	_root.modulate.a = 0.0
	visible    = false
	# Live refresh on language switch.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	# Static labels (built once) need a manual reset.
	_lbl_title.text = _t("level_complete.title_done", {}, "РІВЕНЬ ПРОЙДЕНО")
	_new_best_badge.text = _t(
			"level_complete.new_best_badge", {}, "✨ НОВИЙ РЕКОРД ✨")
	_btn_hub.text  = _t("level_complete.go_to_hub",  {}, "Хаб Раю")
	_btn_next.text = _t("level_complete.next_level", {}, "Далі →")
	# Stat labels are re-rendered on every show_results() call, so no
	# extra refresh needed here — the next open will pick up the new
	# language.


# Loc.t() with explicit fallback so the screen renders correctly when
# Loc is missing (early boot, headless tests).
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

# ── Public ────────────────────────────────────────────────────────────────────

func show_results(stats: Dictionary) -> void:
	visible = true
	_fill_static(stats)
	_animate_in(stats)

# ── Fill data ─────────────────────────────────────────────────────────────────

func _fill_static(stats: Dictionary) -> void:
	var circle:  int   = stats.get("circle",      1)
	var level:   int   = stats.get("level_id",    1)
	var found:   int   = stats.get("souls_found",  0)
	var total:   int   = stats.get("souls_total",  0)
	var deaths:  int   = stats.get("deaths",       0)
	var sin_d:   float = stats.get("sin_delta",    0.0)
	var sin_t:   float = stats.get("sin_total",    0.0)
	var light:   int   = stats.get("light_earned", 0)
	_lbl_subtitle.text = _t("level_complete.subtitle_format",
			{"circle": circle, "level": level},
			"Коло %d • Рівень %d" % [circle, level])

	# Stars — hidden until animation
	var star_labels: Array = _stars_row.get_children()
	for i in star_labels.size():
		star_labels[i].text = STAR_EMPTY
		star_labels[i].modulate.a = 0.4

	# Stats — hidden until animation
	_stat_souls.text  = _t("level_complete.souls_format",
			{"found": found, "total": total},
			"👻  Душі:    %d / %d" % [found, total])
	_stat_deaths.text = _t("level_complete.deaths_format",
			{"n": deaths},
			"💀  Смерті:  %d" % deaths)
	var sin_sign: String = "+" if sin_d >= 0.0 else ""
	_stat_sin.text    = _t("level_complete.sin_change_format",
			{"sign": sin_sign, "delta": "%.0f" % sin_d, "total": "%.0f" % sin_t},
			"😈  Гріх:    %s%.0f%%  →  %.0f%%" % [sin_sign, sin_d, sin_t])
	_stat_light.text  = _t("level_complete.light_format",
			{"n": light}, "💡  +%d Світла" % light)

	# Time + previous best (if any)
	var elapsed: float = stats.get("time_seconds", 0.0)
	_stat_time.text    = _t("level_complete.time_format",
			{"time": _format_time(elapsed)},
			"⏱  Час:     %s" % _format_time(elapsed))

	var prev_best: Dictionary = stats.get("previous_best", {})
	var new_best:  Dictionary = stats.get("new_best", {})
	if prev_best.is_empty():
		_stat_best.text = _t("level_complete.best_none", {}, "🏆  Рекорд:   —")
	else:
		var pb_time:  float = float(prev_best.get("time", 0.0))
		var pb_stars: int   = int(prev_best.get("stars", 0))
		_stat_best.text = _t("level_complete.best_format",
				{"time": _format_time(pb_time), "stars": _stars_str(pb_stars)},
				"🏆  Рекорд:   %s   %s" % [_format_time(pb_time), _stars_str(pb_stars)])

	_new_best_badge.visible = not new_best.is_empty()

	for node in [_stat_souls, _stat_deaths, _stat_time, _stat_best, _stat_sin, _stat_light]:
		node.modulate.a = 0.0

	_btn_hub.modulate.a  = 0.0
	_btn_next.modulate.a = 0.0

func _format_time(seconds: float) -> String:
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]

func _stars_str(n: int) -> String:
	var out := ""
	for i in 3:
		out += STAR_FILLED if i < n else STAR_EMPTY
	return out

# ── Animation sequence ────────────────────────────────────────────────────────

func _animate_in(stats: Dictionary) -> void:
	var stars: int = stats.get("stars", 1)

	# 1. Fade in overlay + panel
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

	# 2. Stars appear one by one
	var star_labels: Array = _stars_row.get_children()
	for i in 3:
		var filled: bool = i < stars
		tw.tween_interval(STAR_DELAY)
		tw.tween_callback(_reveal_star.bind(star_labels[i], filled))

	# 3. Stats slide in
	var stat_nodes := [_stat_souls, _stat_deaths, _stat_time, _stat_best, _stat_sin, _stat_light]
	for node in stat_nodes:
		tw.tween_interval(STAT_DELAY)
		tw.tween_property(node, "modulate:a", 1.0, 0.25)

	# 4. Buttons appear
	tw.tween_interval(0.15)
	tw.tween_property(_btn_hub,  "modulate:a", 1.0, 0.2)
	tw.tween_property(_btn_next, "modulate:a", 1.0, 0.2)

func _reveal_star(lbl: Label, filled: bool) -> void:
	lbl.text = STAR_FILLED if filled else STAR_EMPTY
	lbl.modulate.a = 1.0 if filled else 0.35
	if filled:
		var tw := create_tween()
		tw.tween_property(lbl, "scale", Vector2(1.4, 1.4), 0.12)
		tw.tween_property(lbl, "scale", Vector2.ONE, 0.12)

# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_hub_pressed() -> void:
	hub_pressed.emit()
	GameManager.load_hub()

func _on_next_pressed() -> void:
	next_level_pressed.emit()
	GameManager.load_next_level()
