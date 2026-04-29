extends CanvasLayer

# StatisticsScreen — read-only summary of cumulative player metrics.
# Reads SaveManager.data["statistics"] + level_bests + souls. Built in
# code so the .tscn can stay an empty CanvasLayer that just attaches us.
#
# Open via .open() / closes itself via ✕ button or Esc.

const Palette := preload("res://scripts/ui/Palette.gd")

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

# ── UI roots ──────────────────────────────────────────────────────────────────
var _root:        ColorRect    = null
var _scroll:      ScrollContainer = null
var _vbox:        VBoxContainer = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
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
	_line("Звичайних врятовано", "%d / 100" % SaveManager.get_total_souls())
	_line("Прихованих знайдено", "%d / 20"  % SaveManager.get_total_hidden_souls())

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

# ── UI helpers ────────────────────────────────────────────────────────────────

func _section(title: String) -> void:
	# SectionLabel theme-variation: 24px gold from UITheme.
	var lbl := Label.new()
	lbl.theme_type_variation = "SectionLabel"
	lbl.text = title
	_vbox.add_child(lbl)
	# GoldSeparator variation provides the dim-gold tint by default.
	var sep := HSeparator.new()
	sep.theme_type_variation = "GoldSeparator"
	_vbox.add_child(sep)

func _line(label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.theme_type_variation = "BodyLabel"
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.theme_type_variation = "ValueLabel"
	v.text = value
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

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Palette.BG_DARKER
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vroot := VBoxContainer.new()
	vroot.set_anchors_preset(Control.PRESET_FULL_RECT)
	vroot.add_theme_constant_override("separation", 0)
	_root.add_child(vroot)

	_build_header(vroot)
	_build_body(vroot)

func _build_header(parent: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  24)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top",   14)
	margin.add_theme_constant_override("margin_bottom", 6)
	parent.add_child(margin)

	var hdr := HBoxContainer.new()
	hdr.custom_minimum_size.y = 80
	hdr.add_theme_constant_override("separation", 18)
	margin.add_child(hdr)

	# DisplayLabel: 48px, TEXT_DISPLAY (theme handles the styling).
	var title := Label.new()
	title.theme_type_variation = "DisplayLabel"
	title.text = "📊  Статистика"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(title)

	# IconButton variation: empty StyleBoxes + muted/primary colours.
	var btn_close := Button.new()
	btn_close.theme_type_variation = "IconButton"
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(72, 72)
	btn_close.pressed.connect(close)
	hdr.add_child(btn_close)

func _build_body(parent: VBoxContainer) -> void:
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(_scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left",  24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top",    8)
	margin.add_theme_constant_override("margin_bottom", 90)
	_scroll.add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(_vbox)
