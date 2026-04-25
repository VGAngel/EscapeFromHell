extends Control

## On-screen touch controls for Android.
##
## Supports multi-touch — pressing ← + ↑ together (or → + ↑) works because
## input is dispatched via _input(InputEventScreenTouch) with finger_index
## tracking. Standard Godot Button widgets only see one touch at a time
## and consume it, which is why we don't bind to button_down / button_up.
##
## Each visual is still a Control rect with the same styling; we just
## drive their visual "pressed" state from our own dispatcher.

# ── Constants ─────────────────────────────────────────────────────────────────
const BTN_ALPHA   := 0.55
const BTN_ALPHA_PRESSED := 0.75

const SIZE_LARGE  := Vector2(190, 190)  # Jump + Movement (same size)
const SIZE_MEDIUM := Vector2(150, 150)  # Staff / Pray / Pickup
const SIZE_SMALL  := Vector2(190, 190)  # Movement — matches jump

const GAP_MOVE := 36.0
const GAP := 18.0
const MARGIN_SIDE   := 32.0
const MARGIN_BOTTOM := 24.0

# ── Public nodes (exposed for tests) ─────────────────────────────────────────
var btn_left:   Panel = null
var btn_right:  Panel = null
var btn_jump:   Panel = null
var btn_staff:  Panel = null
var btn_pray:   Panel = null
var btn_pickup: Panel = null

# ── Internal ──────────────────────────────────────────────────────────────────
# Map finger_index → action currently held by that finger.
var _finger_actions: Dictionary = {}
# Map button Panel → action string, for hit-testing.
var _btn_actions: Dictionary = {}
# Cache style boxes so we can swap normal/pressed visuals fast.
var _style_normal:  StyleBoxFlat = null
var _style_pressed: StyleBoxFlat = null

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# We dispatch touches manually; Control children must not eat them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	_build()
	_apply_safe_area()
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and sa.has_signal("changed"):
		sa.changed.connect(_apply_safe_area)

func _build_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.1, 0.1, 0.1, BTN_ALPHA)
	_style_pressed = StyleBoxFlat.new()
	_style_pressed.bg_color = Color(0.25, 0.25, 0.25, BTN_ALPHA_PRESSED)

func _build() -> void:
	btn_left   = _make_btn("←",  "move_left",  SIZE_SMALL)
	btn_right  = _make_btn("→",  "move_right", SIZE_SMALL)
	btn_jump   = _make_btn("↑",  "jump",       SIZE_LARGE)
	btn_staff  = _make_btn("⚔",  "action",     SIZE_MEDIUM)
	btn_pickup = _make_btn("✋", "interact",   SIZE_MEDIUM)
	btn_pray   = _make_btn("🙏", "pray",       SIZE_MEDIUM)
	btn_pickup.visible = false
	btn_pray.visible   = false

# ── Layout ────────────────────────────────────────────────────────────────────
func _apply_safe_area() -> void:
	var sa: Node    = get_node_or_null("/root/SafeArea")
	var banner: int = int(sa.bottom_reserved) if sa else 0
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# Bottom of the usable area (above sin bar + HUD bottom row + banner).
	var floor_y: float = vp.y - float(banner) - 6.0 - 36.0 - 8.0 - MARGIN_BOTTOM

	# Left cluster: ← then →
	var lx: float = MARGIN_SIDE
	btn_left.position  = Vector2(lx, floor_y - SIZE_SMALL.y)
	btn_right.position = Vector2(lx + SIZE_SMALL.x + GAP_MOVE, floor_y - SIZE_SMALL.y)

	# Right cluster (right→left): JUMP ← STAFF ← PICKUP/PRAY
	# Pickup and pray share the leftmost slot (only one shown at a time).
	var rx: float = vp.x - MARGIN_SIDE - SIZE_LARGE.x
	btn_jump.position  = Vector2(rx, floor_y - SIZE_LARGE.y)
	btn_staff.position = Vector2(rx - SIZE_MEDIUM.x - GAP, floor_y - SIZE_MEDIUM.y)
	var third_x: float = rx - SIZE_MEDIUM.x - GAP - SIZE_MEDIUM.x - GAP
	btn_pickup.position = Vector2(third_x, floor_y - SIZE_MEDIUM.y)
	btn_pray.position   = Vector2(third_x, floor_y - SIZE_MEDIUM.y)

# ── Public API ────────────────────────────────────────────────────────────────
func show_pray_button(value: bool) -> void:
	if btn_pray:
		btn_pray.visible = value
		if value and btn_pickup:
			btn_pickup.visible = false

func show_pickup_button(value: bool) -> void:
	if btn_pickup:
		btn_pickup.visible = value
		if value and btn_pray:
			btn_pray.visible = false

# ── Factory ───────────────────────────────────────────────────────────────────
func _make_btn(label: String, action: String, btn_size: Vector2) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = btn_size
	p.size = btn_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE  # we hit-test manually
	# Per-button rounded style (corner radius depends on size).
	var style := _style_normal.duplicate() as StyleBoxFlat
	var r := int(btn_size.x * 0.5)
	style.corner_radius_top_left     = r
	style.corner_radius_top_right    = r
	style.corner_radius_bottom_left  = r
	style.corner_radius_bottom_right = r
	p.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = label
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", int(btn_size.y * 0.38))
	p.add_child(lbl)

	add_child(p)
	_btn_actions[p] = action
	return p

# ── Multi-touch dispatcher ────────────────────────────────────────────────────
# Only press / release events are observed. Drag is ignored on purpose:
# many devices fire a tiny ScreenDrag immediately after the initial
# ScreenTouch (sub-pixel finger jitter). Reacting to drag would
# release-then-repress the action, which Player.gd reads as two
# separate "jump" presses → unintended double jump.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_handle_press(t.index, t.position)
		else:
			_handle_release(t.index)

func _handle_press(finger: int, pos: Vector2) -> void:
	var btn: Panel = _hit_test(pos)
	if btn == null:
		return
	var action: String = _btn_actions.get(btn, "")
	if action == "":
		return
	_finger_actions[finger] = action
	_press_action(action)
	_set_visual(btn, true)

func _handle_release(finger: int) -> void:
	if not _finger_actions.has(finger):
		return
	var action: String = _finger_actions[finger]
	_finger_actions.erase(finger)
	# Only release the action if no other finger is still on the same button.
	if not _action_still_held(action):
		_release_action(action)
	_refresh_visuals()

func _hit_test(pos: Vector2) -> Panel:
	for btn in _btn_actions.keys():
		var p: Panel = btn
		if not p.visible:
			continue
		if Rect2(p.global_position, p.size).has_point(pos):
			return p
	return null

func _action_still_held(action: String) -> bool:
	for held in _finger_actions.values():
		if held == action:
			return true
	return false

func _press_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_press(action)

func _release_action(action: String) -> void:
	if InputMap.has_action(action):
		Input.action_release(action)

func _set_visual(btn: Panel, pressed: bool) -> void:
	var style := (_style_pressed if pressed else _style_normal).duplicate() as StyleBoxFlat
	var r := int(btn.size.x * 0.5)
	style.corner_radius_top_left     = r
	style.corner_radius_top_right    = r
	style.corner_radius_bottom_left  = r
	style.corner_radius_bottom_right = r
	btn.add_theme_stylebox_override("panel", style)

func _refresh_visuals() -> void:
	# Recompute pressed state for every button from current finger holds.
	var held_actions: Dictionary = {}
	for action in _finger_actions.values():
		held_actions[action] = true
	for btn in _btn_actions.keys():
		var action: String = _btn_actions[btn]
		_set_visual(btn, held_actions.has(action))
