extends CanvasLayer

# Persistent header that appears whenever UIRouter has at least one
# overlay open. Layout (left → right):
#
#   [🔙]   <Screen title>     💡 N    👻 X/100    😈 Y%
#
# • Visibility is bound to UIRouter.stack_changed — fades in when
#   depth >= 1 and out when stack empties.
# • Title text comes from `UIRouter.top().router_title()` if the
#   topmost screen implements it; otherwise blank.
# • Resources poll SaveManager (no signal API yet) on every router
#   change + once per second while visible — cheap and good enough.
# • 🔙 button calls UIRouter.pop().
#
# Built in code so callers just `add_child(top_bar)` — no .tscn needed.

# Preload rather than rely on the editor-registered class_name —
# headless GUT runs don't always have global classes scanned in time.
const PAL := preload("res://scripts/ui/PAL.gd")

const FADE := 0.18
const POLL_INTERVAL := 1.0
const BAR_HEIGHT := 80

# ── Node refs ─────────────────────────────────────────────────────────────────
var _root: Control = null
var _bar: Control = null
var _btn_back: Button = null
var _title_lbl: Label = null
var _light_lbl: Label = null
var _souls_lbl: Label = null
var _sin_lbl: Label = null

# ── State ─────────────────────────────────────────────────────────────────────
var _router: Node = null
var _poll_t: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 11  # above overlays (which are layer 10)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_router = get_node_or_null("/root/UIRouter")
	if _router and _router.has_signal("stack_changed"):
		_router.stack_changed.connect(_on_stack_changed)
		_router.screen_pushed.connect(_on_screen_pushed)
	# Start hidden (no overlay open yet).
	_root.modulate.a = 0.0
	_root.visible = false
	_refresh_resources()
	# Re-position when SafeArea changes (notch / status-bar).
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and sa.has_signal("changed"):
		sa.changed.connect(_apply_safe_area)
	_apply_safe_area()


func _process(delta: float) -> void:
	if not _root.visible:
		return
	_poll_t += delta
	if _poll_t >= POLL_INTERVAL:
		_poll_t = 0.0
		_refresh_resources()


# ── Router signal handlers ────────────────────────────────────────────────────

func _on_stack_changed(depth: int) -> void:
	if depth > 0:
		_show()
	else:
		_hide()
	_refresh_title()
	_refresh_resources()


# Push fires before stack_changed listeners typically — but we want
# the title to update as soon as the new top is in place. Hook both.
func _on_screen_pushed(_screen: Node) -> void:
	_refresh_title()


# ── Visibility ────────────────────────────────────────────────────────────────

func _show() -> void:
	_root.visible = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE)


func _hide() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE)
	tw.tween_callback(func() -> void: _root.visible = false)


# ── Title ─────────────────────────────────────────────────────────────────────

func _refresh_title() -> void:
	if _router == null:
		_title_lbl.text = ""
		return
	var top: Node = _router.top()
	if top == null:
		_title_lbl.text = ""
		return
	if top.has_method("router_title"):
		_title_lbl.text = String(top.router_title())
	else:
		_title_lbl.text = ""


# ── Resource readout ──────────────────────────────────────────────────────────

func _refresh_resources() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	if sm.has_method("get_light"):
		_light_lbl.text = "💡 %d" % int(sm.get_light())
	if sm.has_method("get_total_souls"):
		_souls_lbl.text = "👻 %d/100" % int(sm.get_total_souls())
	if sm.has_method("get_sin"):
		_sin_lbl.text = "😈 %d%%" % int(sm.get_sin())


# ── Safe-area inset ───────────────────────────────────────────────────────────

func _apply_safe_area() -> void:
	if _bar == null:
		return
	var top_inset: int = 0
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and "top_reserved" in sa:
		top_inset = int(sa.top_reserved)
	_bar.offset_top = float(top_inset)
	_bar.offset_bottom = float(top_inset + BAR_HEIGHT)


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Bar background — anchored top-wide.
	_bar = Control.new()
	_bar.name = "Bar"
	_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar.offset_bottom = float(BAR_HEIGHT)
	_root.add_child(_bar)

	var bg := ColorRect.new()
	bg.color = PAL.BG_DARKER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # absorb taps so they don't fall through
	_bar.add_child(bg)

	# Bottom border line.
	var border := ColorRect.new()
	border.color = PAL.BORDER_DIM
	border.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	border.offset_top = -1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(border)

	# Horizontal layout: [back] [title (expand)] [resources]
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_bar.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	margin.add_child(hbox)

	# 🔙 back button
	_btn_back = Button.new()
	_btn_back.theme_type_variation = "IconButton"
	_btn_back.text = "🔙"
	_btn_back.custom_minimum_size = Vector2(64, 64)
	_btn_back.pressed.connect(_on_back_pressed)
	hbox.add_child(_btn_back)

	# Title (expand to fill the middle)
	_title_lbl = Label.new()
	_title_lbl.theme_type_variation = "TitleLabel"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.text = ""
	hbox.add_child(_title_lbl)

	# Resource block
	var res_box := HBoxContainer.new()
	res_box.add_theme_constant_override("separation", 14)
	hbox.add_child(res_box)

	_light_lbl = Label.new()
	_light_lbl.theme_type_variation = "BodyLabel"
	_light_lbl.add_theme_color_override("font_color", PAL.GOLD)
	_light_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_box.add_child(_light_lbl)

	_souls_lbl = Label.new()
	_souls_lbl.theme_type_variation = "BodyLabel"
	_souls_lbl.add_theme_color_override("font_color", PAL.ACCENT_BLUE)
	_souls_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_box.add_child(_souls_lbl)

	_sin_lbl = Label.new()
	_sin_lbl.theme_type_variation = "BodyLabel"
	_sin_lbl.add_theme_color_override("font_color", PAL.SIN_RED)
	_sin_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	res_box.add_child(_sin_lbl)


# ── Input ─────────────────────────────────────────────────────────────────────

func _on_back_pressed() -> void:
	if _router and _router.has_method("pop"):
		_router.pop()
