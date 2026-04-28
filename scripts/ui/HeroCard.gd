extends PanelContainer

# Hero card on the main menu — shows the player's snapshot at a glance
# so the menu feels like "continue your descent" rather than a cold list
# of buttons.
#
# Layout:
#   ┌────────────────────────────────────────┐
#   │ <profile name>                  Коло X │
#   │                                Рівень Y│
#   │ 👻 Souls 23/100 · ✦ 4/20 · 💡 120      │
#   │ 🏆 Найкращий: 0:42 ★★★ (рівень 7)      │
#   │ 😈 Гріх 18%                            │
#   └────────────────────────────────────────┘
#
# Pure-code (no .tscn) so MainMenu can drop it in via add_child + setup.
# Refresh is cheap — call .refresh() after returning from any overlay.

const Palette := preload("res://scripts/ui/Palette.gd")

const REFRESH_INTERVAL := 1.0   # poll-based refresh while visible

var _name_lbl: Label = null
var _circle_lbl: Label = null
var _level_lbl: Label = null
var _souls_lbl: Label = null
var _best_lbl: Label = null
var _sin_lbl: Label = null
var _poll_t: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	theme_type_variation = "DarkPanel"
	custom_minimum_size = Vector2(0, 220)
	_build()
	refresh()


func _process(delta: float) -> void:
	# Cheap to refresh — saves don't change every frame, but this keeps
	# the card live if the player buys an upgrade from a deep overlay.
	_poll_t += delta
	if _poll_t >= REFRESH_INTERVAL:
		_poll_t = 0.0
		refresh()


# ── Public ────────────────────────────────────────────────────────────────────

func refresh() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		_set_text(_name_lbl,   "—")
		_set_text(_circle_lbl, "")
		_set_text(_level_lbl,  "")
		_set_text(_souls_lbl,  "SaveManager не доступний")
		_set_text(_best_lbl,   "")
		_set_text(_sin_lbl,    "")
		return

	# Name
	var name_text: String = "Невідомий"
	if sm.has_method("get_profile_name"):
		var pn: String = String(sm.get_profile_name())
		if not pn.is_empty():
			name_text = pn
	_set_text(_name_lbl, name_text)

	# Progress
	var current_level: int = int(sm.get_current_level()) if sm.has_method("get_current_level") else 1
	var current_circle: int = int(sm.get_current_circle()) if sm.has_method("get_current_circle") else 1
	_set_text(_circle_lbl, "Коло %d" % current_circle)
	_set_text(_level_lbl,  "Рівень %d" % current_level)

	# Souls / hidden / light
	var souls: int = int(sm.get_total_souls()) if sm.has_method("get_total_souls") else 0
	var hidden: int = int(sm.get_total_hidden_souls()) if sm.has_method("get_total_hidden_souls") else 0
	var light: int = int(sm.get_light()) if sm.has_method("get_light") else 0
	_set_text(_souls_lbl,
			"👻 %d/100  ·  ✦ %d/20  ·  💡 %d" % [souls, hidden, light])

	# Best level — search 1..100, max stars then min time tiebreaker.
	_set_text(_best_lbl, _format_best(sm))

	# Sin
	if sm.has_method("get_sin"):
		var sin_pct: int = int(sm.get_sin())
		_sin_lbl.add_theme_color_override("font_color", _sin_color(sin_pct))
		_set_text(_sin_lbl, "😈 Гріх %d%%" % sin_pct)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _format_best(sm: Node) -> String:
	if not sm.has_method("get_level_best"):
		return ""
	var best_id: int = -1
	var best_time: float = INF
	var best_stars: int = 0
	for lid in range(1, 101):
		var b: Dictionary = sm.get_level_best(lid)
		if b.is_empty():
			continue
		var s: int = int(b.get("stars", 0))
		var t: float = float(b.get("time", INF))
		if s > best_stars or (s == best_stars and t < best_time):
			best_stars = s
			best_time = t
			best_id = lid
	if best_id < 0:
		return "🏆 Найкращий: —"
	return "🏆 Найкращий: %s %s (рівень %d)" % [
		_format_time(best_time), _stars(best_stars), best_id,
	]


func _format_time(seconds: float) -> String:
	if seconds == INF:
		return "—"
	var s: int = int(seconds)
	@warning_ignore("integer_division")
	return "%d:%02d" % [s / 60, s % 60]


func _stars(n: int) -> String:
	const FULL := "★"
	const EMPTY := "☆"
	var out := ""
	for i in 3:
		out += FULL if i < n else EMPTY
	return out


# Sin color goes from green → yellow → red as % climbs. Keeps the
# card readable: 0% green, 50% yellow, 100% red.
func _sin_color(pct: int) -> Color:
	var p: float = clamp(float(pct) / 100.0, 0.0, 1.0)
	if p < 0.5:
		return Palette.SUCCESS.lerp(Palette.WARNING, p * 2.0)
	return Palette.WARNING.lerp(Palette.SIN_RED, (p - 0.5) * 2.0)


func _set_text(lbl: Label, text: String) -> void:
	if lbl != null:
		lbl.text = text


# ── Build ─────────────────────────────────────────────────────────────────────

func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)

	# Top row: profile name | Circle/Level (right-aligned)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)

	_name_lbl = Label.new()
	_name_lbl.theme_type_variation = "TitleLabel"
	_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name_lbl)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(stack)

	_circle_lbl = Label.new()
	_circle_lbl.theme_type_variation = "BodyLabel"
	_circle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_circle_lbl)

	_level_lbl = Label.new()
	_level_lbl.theme_type_variation = "BodyLabel"
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stack.add_child(_level_lbl)

	# Separator
	var sep := HSeparator.new()
	sep.theme_type_variation = "GoldSeparator"
	v.add_child(sep)

	# Souls / hidden / light row
	_souls_lbl = Label.new()
	_souls_lbl.theme_type_variation = "ValueLabel"
	v.add_child(_souls_lbl)

	# Best run
	_best_lbl = Label.new()
	_best_lbl.theme_type_variation = "BodyLabel"
	v.add_child(_best_lbl)

	# Sin
	_sin_lbl = Label.new()
	_sin_lbl.theme_type_variation = "BodyLabel"
	v.add_child(_sin_lbl)
