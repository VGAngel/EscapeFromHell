extends CanvasLayer

# StatisticsScreen — read-only summary of cumulative player metrics.
# Reads SaveManager.data["statistics"] + level_bests + souls. Static
# layout (backdrop, header, scroll, content VBox) lives in the .tscn;
# the dynamic section + line rows are appended into Content at runtime
# by _refresh().
#
# Open via .open() / closes via ✕ button or Esc.

signal closed

const FADE_DURATION := 0.3

# ── Cause-label dictionary so we render Ukrainian labels for the codes
# GameManager.trigger_death("...") emits.
const CAUSE_LABELS := {
	"enemy_hit":     "від ворога",
	"fall":          "від падіння",
	"lava":          "у лаві",
	"spike":         "на шипах",
	"void":          "у безодні",
	"unknown":       "інше",
}

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _root:    ColorRect      = $Backdrop
@onready var _close:   Button         = $Backdrop/VRoot/HeaderMargin/Header/CloseButton
@onready var _vbox:    VBoxContainer  = $Backdrop/VRoot/Scroll/Center/ContentMargin/Content

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_close.pressed.connect(close)
	_root.modulate.a = 0.0
	visible = false

# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.statistics"))
	return "Статистика"

func open() -> void:
	visible = true
	_refresh()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit())

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ── Refresh from SaveManager ─────────────────────────────────────────────────

func _refresh() -> void:
	if not _vbox:
		return
	for child in _vbox.get_children():
		child.queue_free()
	if not SaveManager:
		_vbox.add_child(_make_line("SaveManager недоступний", Color.RED))
		return

	# ── Часи / прогрес ──────────────────────────────────────────────────────
	var play_s: float = float(SaveManager.get_stat("total_play_seconds", 0.0))
	var cleared: int  = int(SaveManager.get_stat("levels_cleared", 0))
	var current: int  = SaveManager.get_current_level()
	_section("⏱  Прогрес")
	_line("Загальний час гри",  _format_hms(play_s))
	_line("Поточний рівень",    str(current))
	_line("Завершено рівнів",    str(cleared))

	# ── Душі ────────────────────────────────────────────────────────────────
	_section("👻  Душі")
	_line("Звичайних врятовано", "%d / %d" % [SaveManager.get_total_souls(),
		SaveManager.get_named_souls_target()])
	_line("Прихованих знайдено", "%d / %d" % [SaveManager.get_total_hidden_souls(),
		SaveManager.get_hidden_souls_target()])

	# ── Смерті ──────────────────────────────────────────────────────────────
	_section("💀  Смерті")
	_line("Загалом",  str(int(SaveManager.get_stat("deaths_total", 0))))
	var causes: Dictionary = SaveManager.get_deaths_by_cause()
	if not causes.is_empty():
		var keys: Array = causes.keys()
		keys.sort()
		for k in keys:
			var label: String = CAUSE_LABELS.get(k, String(k))
			_line("  " + label, str(int(causes[k])))

	# ── Економіка ───────────────────────────────────────────────────────────
	_section("💡  Світло")
	_line("Поточний баланс", str(SaveManager.get_light()))
	_line("Зароблено за все",  str(int(SaveManager.get_stat("light_earned_total", 0))))
	_line("Витрачено за все",  str(int(SaveManager.get_stat("light_spent_total", 0))))

	# ── Найкращий рівень ────────────────────────────────────────────────────
	_section("🏆  Рекорди")
	var best_id: int = -1
	var best_time: float = INF
	var best_stars: int = 0
	for lid in range(1, 101):
		var b: Dictionary = SaveManager.get_level_best(lid)
		if b.is_empty():
			continue
		var s: int = int(b.get("stars", 0))
		var t: float = float(b.get("time", INF))
		# "Best" = max stars, then min time tiebreaker.
		if s > best_stars or (s == best_stars and t < best_time):
			best_stars = s
			best_time  = t
			best_id    = lid
	if best_id < 0:
		_line("Найкращий клір", "—")
	else:
		_line("Найкращий клір", "Рівень %d  %s  %s" % [
			best_id, _format_time(best_time), _stars_str(best_stars),
		])

	# ── Гріх ────────────────────────────────────────────────────────────────
	_section("😈  Гріх")
	_line("Поточний",   "%d%%" % int(SaveManager.get_sin()))

# ── Row helpers ──────────────────────────────────────────────────────────────
# Sections + lines are dynamic per refresh (counts depend on which death
# causes / level bests SaveManager has recorded), so they're built in
# code and appended into the Content VBox declared in the .tscn.

func _section(title: String) -> void:
	# Bumped from theme's 24 px to 32 px — the screen reads as a list of
	# numbers and the player needs to scan section headers fast.
	var lbl := Label.new()
	lbl.theme_type_variation = "SectionLabel"
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 32)
	# Top spacer above each section so the header doesn't crowd the
	# previous row's value.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_vbox.add_child(spacer)
	_vbox.add_child(lbl)
	var sep := HSeparator.new()
	sep.theme_type_variation = "GoldSeparator"
	_vbox.add_child(sep)

func _line(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var l := Label.new()
	l.theme_type_variation = "BodyLabel"
	l.text = label
	# Theme defaults to 18 px which is unreadable at typical viewing
	# distances on phone or large monitor; bump to 24 for the stats
	# screen specifically without changing the global theme.
	l.add_theme_font_size_override("font_size", 24)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)

	var v := Label.new()
	v.theme_type_variation = "ValueLabel"
	v.text = value
	v.add_theme_font_size_override("font_size", 26)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	_vbox.add_child(row)

# Used for one-off colored lines (errors, warnings) where the body
# variation isn't appropriate. Kept tiny and explicit.
func _make_line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.theme_type_variation = "BodyLabel"
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l

func _format_hms(seconds: float) -> String:
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	var h: int = s / 3600
	@warning_ignore("integer_division")
	var m: int = (s % 3600) / 60
	var sec: int = s % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%d:%02d" % [m, sec]

func _format_time(seconds: float) -> String:
	if seconds == INF:
		return "—"
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]

func _stars_str(n: int) -> String:
	const FULL := "★"
	const EMPTY := "☆"
	var out := ""
	for i in 3:
		out += FULL if i < n else EMPTY
	return out
