extends CanvasLayer

## Debug overlay: scrollable list of all levels with one-click launch.
## Built entirely in code so it works whether the .tscn has children or not.
## Mirrors the open()/closed signal contract used by other MainMenu overlays.

signal closed

const LEVEL_TYPE_COLOR := {
	"vertical":   Color(0.55, 0.85, 0.55),
	"platformer": Color(0.85, 0.85, 0.55),
	"boss":       Color(0.95, 0.45, 0.40),
	"void":       Color(0.70, 0.55, 0.95),
}

var _root:        ColorRect    = null
var _scroll:      ScrollContainer = null
var _list:        VBoxContainer = null
var _filter_edit: LineEdit     = null
var _all_ids:     Array        = []


func _ready() -> void:
	visible = false
	_build_ui()
	_populate()


func router_title() -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t("router_title.level_debug"))
	return "Рівні (debug)"

func open() -> void:
	visible = true
	if _filter_edit:
		_filter_edit.text = ""
		_apply_filter("")
	# Re-grab focus so back gestures route to us.
	if _filter_edit:
		_filter_edit.grab_focus()


func _close() -> void:
	visible = false
	closed.emit()


# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.04, 0.03, 0.06, 0.94)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var vp_size := get_viewport().get_visible_rect().size

	# Header bar with title + close button
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_top = 60.0
	header.offset_left = 40.0
	header.offset_right = -40.0
	header.offset_bottom = 60.0 + 80.0
	header.add_theme_constant_override("separation", 16)
	_root.add_child(header)

	var title := Label.new()
	title.text = "Levels (debug)"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#FF8866"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)

	var btn_close := Button.new()
	btn_close.text = "✕"
	btn_close.custom_minimum_size = Vector2(80, 80)
	btn_close.add_theme_font_size_override("font_size", 32)
	btn_close.pressed.connect(_close)
	header.add_child(btn_close)

	# Filter input
	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "Фільтр (id, назва, type, circle)"
	_filter_edit.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_filter_edit.offset_top = 160.0
	_filter_edit.offset_left = 40.0
	_filter_edit.offset_right = -40.0
	_filter_edit.offset_bottom = 220.0
	_filter_edit.add_theme_font_size_override("font_size", 24)
	_filter_edit.text_changed.connect(_apply_filter)
	_root.add_child(_filter_edit)

	# Scroll
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_top    = 240.0
	_scroll.offset_left   = 24.0
	_scroll.offset_right  = -24.0
	_scroll.offset_bottom = -40.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)

	# Position scroll within viewport bounds (referenced for tests/sanity).
	if vp_size.y > 0.0:
		_scroll.offset_bottom = -40.0


func _populate() -> void:
	if not LevelConfig:
		var lbl := Label.new()
		lbl.text = "LevelConfig autoload not available"
		_list.add_child(lbl)
		return

	_all_ids = LevelConfig.get_all_level_ids().duplicate()
	_all_ids.sort()
	for id in _all_ids:
		_list.add_child(_make_row(int(id)))


func _make_row(id: int) -> Control:
	var lvl: Dictionary = LevelConfig.get_level(id)
	var lvl_type: String = lvl.get("type", "platformer")
	var circle: int = int(lvl.get("circle", 1))
	var diff:   int = int(lvl.get("difficulty", 1))
	var name_s: String = String(lvl.get("name", "Level %d" % id))

	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 78)
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.text = "  #%-3d  C%d  D%d  [%s]   %s" % [id, circle, diff, lvl_type, name_s]
	row.add_theme_font_size_override("font_size", 22)

	var col: Color = LEVEL_TYPE_COLOR.get(lvl_type, Color(0.78, 0.76, 0.82))
	row.add_theme_color_override("font_color", col)

	# Stash searchable text in metadata for the filter.
	row.set_meta(&"search_text", ("%d %s %s c%d d%d" % [id, name_s, lvl_type, circle, diff]).to_lower())

	row.pressed.connect(_launch_level.bind(id))
	return row


func _apply_filter(text: String) -> void:
	var needle: String = text.strip_edges().to_lower()
	for child in _list.get_children():
		if not child is Control:
			continue
		if needle.is_empty():
			child.visible = true
			continue
		var hay: String = String(child.get_meta(&"search_text", ""))
		child.visible = hay.find(needle) != -1


func _launch_level(id: int) -> void:
	if not GameManager:
		push_warning("LevelDebugMenu: GameManager autoload missing")
		return
	# Hide overlay immediately so the fade-out reads cleanly.
	visible = false
	GameManager.start_level(id)
