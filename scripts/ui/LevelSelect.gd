extends CanvasLayer

# Player-facing level select.
#
# Unlike LevelDebugMenu (which exposes every level for testing), this
# overlay only reveals levels the player has reached. Each unlocked
# row also shows the player's best summary for the level — stars +
# best time + souls collected — pulled from SaveManager.get_level_best().
# Locked levels render as a muted "🔒" row so the progression silhouette
# stays readable.
#
# Tap an unlocked row → SaveManager.set_current_level(id) and jump
# straight into the level via GameManager.start_level(id), mirroring
# what the Hub's Continue button does.
#
# Built in code; matches the open()/closed contract every other
# MainMenu overlay uses.

signal closed

const PAL := preload("res://scripts/ui/Palette.gd")
const FADE_DURATION := 0.25
const ROW_HEIGHT := 84.0


var _root:    ColorRect      = null
var _scroll:  ScrollContainer = null
var _list:    VBoxContainer  = null
var _header:  Label          = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)


func _on_language_changed(_lang: String) -> void:
	if visible:
		_populate()
		if _header:
			_header.text = _t("level_select.title", {}, "Рівні")


# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	return _t("level_select.title", {}, "Рівні")


func open() -> void:
	visible = true
	_populate()
	_root.modulate.a = 0.0
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


# ── UI build ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.04, 0.03, 0.05, 0.94)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Header bar — title + close
	var header_row := HBoxContainer.new()
	header_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header_row.offset_top = 60.0
	header_row.offset_left = 40.0
	header_row.offset_right = -40.0
	header_row.offset_bottom = 60.0 + 80.0
	header_row.add_theme_constant_override("separation", 16)
	_root.add_child(header_row)

	_header = Label.new()
	_header.text = _t("level_select.title", {}, "Рівні")
	_header.add_theme_font_size_override("font_size", 36)
	_header.add_theme_color_override("font_color", PAL.GOLD)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_row.add_child(_header)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(80, 80)
	btn_close.add_theme_font_size_override("font_size", 32)
	btn_close.pressed.connect(close)
	header_row.add_child(btn_close)

	# Scrollable list
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top    = 160.0
	_scroll.offset_left   = 24.0
	_scroll.offset_right  = -24.0
	_scroll.offset_bottom = -40.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)


# ── Populate rows ─────────────────────────────────────────────────────────────

func _populate() -> void:
	for child in _list.get_children():
		child.queue_free()

	var sm: Node = get_node_or_null("/root/SaveManager")
	var lc: Node = get_node_or_null("/root/LevelConfig")
	var current: int = 1
	if sm and sm.has_method("get_current_level"):
		current = int(sm.get_current_level())

	var ids: Array = []
	if lc and lc.has_method("get_all_level_ids"):
		ids = lc.get_all_level_ids().duplicate()
	if ids.is_empty():
		# Fallback: 100 levels (matches GameManager assumption).
		for i in range(1, 101):
			ids.append(i)
	ids.sort()

	for id_v in ids:
		var id := int(id_v)
		var unlocked: bool = id <= current
		_list.add_child(_make_row(id, unlocked, sm, lc))


func _make_row(id: int, unlocked: bool, sm: Node, lc: Node) -> Control:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_theme_font_size_override("font_size", 22)
	row.disabled = not unlocked

	var name_s: String = "Level %d" % id
	if lc and lc.has_method("get_level_name"):
		var n: String = String(lc.get_level_name(id))
		if not n.is_empty():
			name_s = n

	if not unlocked:
		row.text = "  🔒  #%-3d  %s" % [id, name_s]
		row.add_theme_color_override("font_color", Color(0.45, 0.42, 0.50))
	else:
		var best: Dictionary = {}
		if sm and sm.has_method("get_level_best"):
			best = sm.get_level_best(id)
		var stars: int = int(best.get("stars", 0))
		var best_t: float = float(best.get("time", 0.0))
		var best_souls: int = int(best.get("souls", 0))
		var stars_s := _stars(stars)
		var time_s := _format_time(best_t) if best_t > 0.0 else "—:—"
		row.text = "  #%-3d  %s    ★ %s    ⏱ %s    👤 %d" % [
				id, name_s, stars_s, time_s, best_souls]
		row.add_theme_color_override("font_color", PAL.TEXT_PRIMARY)
		row.pressed.connect(_launch_level.bind(id))

	return row


# ── Actions ───────────────────────────────────────────────────────────────────

func _launch_level(id: int) -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	var gm: Node = get_node_or_null("/root/GameManager")
	if sm and sm.has_method("set_current_level"):
		sm.set_current_level(id)
	visible = false
	if gm and gm.has_method("start_level"):
		gm.start_level(id)
	else:
		get_tree().change_scene_to_file("res://scenes/levels/Level.tscn")


# ── Helpers ───────────────────────────────────────────────────────────────────

func _stars(n: int) -> String:
	n = clamp(n, 0, 3)
	return "★".repeat(n) + "☆".repeat(3 - n)


func _format_time(t: float) -> String:
	if t <= 0.0:
		return "—:—"
	var total := int(t)
	@warning_ignore("integer_division")
	var m: int = total / 60
	var s: int = total % 60
	return "%d:%02d" % [m, s]


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
