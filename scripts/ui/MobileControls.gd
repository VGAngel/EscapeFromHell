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

# ── Customisation (C5) ────────────────────────────────────────────────────────
# Per-button position offsets from the default anchor — populated by
# SaveManager.get_mobile_layout(). Keyed by action string for stability
# across button refactors.
var _btn_offsets: Dictionary = {}      # action → Vector2
# Global size multiplier (0.6..1.4). Applied to every button's size.
var _size_scale: float = 1.0
# When true, buttons get a glowing border and react to drags instead of
# firing input. Toggled by Settings → "Edit layout".
var _edit_mode: bool = false
var _edit_drag_btn: Panel = null
var _edit_drag_start: Vector2 = Vector2.ZERO

signal layout_changed

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# We dispatch touches manually; Control children must not eat them.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	_build()
	_load_saved_layout()
	_apply_safe_area()
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and sa.has_signal("changed"):
		sa.changed.connect(_apply_safe_area)

func _load_saved_layout() -> void:
	if not SaveManager:
		return
	var layout: Dictionary = SaveManager.get_mobile_layout()
	if layout.is_empty():
		return
	_size_scale = clampf(float(layout.get("size_scale", 1.0)), 0.5, 1.6)
	for action in layout.get("offsets", {}).keys():
		var v: Variant = layout["offsets"][action]
		if v is Vector2:
			_btn_offsets[action] = v
		elif v is Dictionary:
			# JSON loses Vector2 type — survive a {x:..,y:..} round-trip.
			_btn_offsets[action] = Vector2(float(v.get("x", 0.0)), float(v.get("y", 0.0)))

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

	# Resize buttons first — every position math below assumes the scaled
	# size, otherwise saved offsets would drift each time scale changes.
	_apply_size_scale()

	var size_small:  Vector2 = SIZE_SMALL  * _size_scale
	var size_medium: Vector2 = SIZE_MEDIUM * _size_scale
	var size_large:  Vector2 = SIZE_LARGE  * _size_scale

	# Bottom of the usable area (above sin bar + HUD bottom row + banner).
	var floor_y: float = vp.y - float(banner) - 6.0 - 36.0 - 8.0 - MARGIN_BOTTOM

	# Default left cluster: ← then →
	var lx: float = MARGIN_SIDE
	_set_default(btn_left,  "move_left",
		Vector2(lx, floor_y - size_small.y))
	_set_default(btn_right, "move_right",
		Vector2(lx + size_small.x + GAP_MOVE, floor_y - size_small.y))

	# Default right cluster: JUMP / STAFF / PICKUP|PRAY
	var rx: float = vp.x - MARGIN_SIDE - size_large.x
	_set_default(btn_jump,  "jump",
		Vector2(rx, floor_y - size_large.y))
	_set_default(btn_staff, "action",
		Vector2(rx - size_medium.x - GAP, floor_y - size_medium.y))
	var third_x: float = rx - size_medium.x - GAP - size_medium.x - GAP
	_set_default(btn_pickup, "interact",
		Vector2(third_x, floor_y - size_medium.y))
	_set_default(btn_pray,   "pray",
		Vector2(third_x, floor_y - size_medium.y))

## Apply default-position-plus-saved-offset for a button. Pulled out so
## the offset application lives in one place.
func _set_default(btn: Panel, action: String, default_pos: Vector2) -> void:
	if not btn:
		return
	var off: Vector2 = _btn_offsets.get(action, Vector2.ZERO)
	btn.position = default_pos + off

func _apply_size_scale() -> void:
	if not btn_left:
		return
	var s_small:  Vector2 = SIZE_SMALL  * _size_scale
	var s_medium: Vector2 = SIZE_MEDIUM * _size_scale
	var s_large:  Vector2 = SIZE_LARGE  * _size_scale
	btn_left.size   = s_small;   btn_left.custom_minimum_size  = s_small
	btn_right.size  = s_small;   btn_right.custom_minimum_size = s_small
	btn_jump.size   = s_large;   btn_jump.custom_minimum_size  = s_large
	btn_staff.size  = s_medium;  btn_staff.custom_minimum_size = s_medium
	btn_pickup.size = s_medium;  btn_pickup.custom_minimum_size= s_medium
	btn_pray.size   = s_medium;  btn_pray.custom_minimum_size  = s_medium
	# Refresh corner radii (they're tied to btn width in _make_btn).
	for btn in _btn_actions.keys():
		_refresh_btn_style(btn as Panel)

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
	# Edit mode swallows touches: drag = move button, no game input fires.
	if _edit_mode:
		_handle_edit_input(event)
		return
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

# Reapply current style to a button after its size changed.
func _refresh_btn_style(btn: Panel) -> void:
	if not btn:
		return
	var style := _style_normal.duplicate() as StyleBoxFlat
	var r := int(btn.size.x * 0.5)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, r)
	btn.add_theme_stylebox_override("panel", style)
	# Resize the inner label so font scales with the button.
	if btn.get_child_count() > 0 and btn.get_child(0) is Label:
		(btn.get_child(0) as Label).add_theme_font_size_override(
			"font_size", int(btn.size.y * 0.38))

# ── Public API: customisation ────────────────────────────────────────────────

## Toggle edit mode. While ON, buttons stop firing input and instead
## reposition under finger drag. While OFF, normal play.
func set_edit_mode(value: bool) -> void:
	_edit_mode = value
	# Wipe any pressed state when toggling so a stuck "jump" doesn't leak.
	for action in _finger_actions.values():
		_release_action(action)
	_finger_actions.clear()
	# Glow border on each button so the player sees they're draggable.
	for btn in _btn_actions.keys():
		_apply_edit_glow(btn as Panel, value)

func is_edit_mode() -> bool:
	return _edit_mode

## Set global size scale (0.5..1.6) and re-layout immediately. Caller is
## responsible for calling save_layout() when the user commits.
func set_size_scale(value: float) -> void:
	_size_scale = clampf(value, 0.5, 1.6)
	_apply_safe_area()
	layout_changed.emit()

func get_size_scale() -> float:
	return _size_scale

## Snapshot current layout (offsets + scale) into a dict suitable for
## SaveManager.set_mobile_layout().
func get_layout() -> Dictionary:
	# Vector2 doesn't survive JSON round-trip, store as plain dicts.
	var offs: Dictionary = {}
	for action in _btn_offsets.keys():
		var v: Vector2 = _btn_offsets[action]
		offs[action] = {"x": v.x, "y": v.y}
	return {"size_scale": _size_scale, "offsets": offs}

func save_layout() -> void:
	if SaveManager:
		SaveManager.set_mobile_layout(get_layout())

## Wipe overrides + scale and re-layout from defaults. Persists immediately.
func reset_layout() -> void:
	_btn_offsets.clear()
	_size_scale = 1.0
	_apply_safe_area()
	if SaveManager:
		SaveManager.set_mobile_layout({})
	layout_changed.emit()

# ── Edit-mode internals ──────────────────────────────────────────────────────

func _apply_edit_glow(btn: Panel, on: bool) -> void:
	var style := _style_normal.duplicate() as StyleBoxFlat
	if on:
		style.border_color = Color("#FFD700")
		for side in ["left","right","top","bottom"]:
			style.set("border_width_" + side, 4)
	var r := int(btn.size.x * 0.5)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, r)
	btn.add_theme_stylebox_override("panel", style)

func _handle_edit_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			_edit_drag_btn = _hit_test(t.position)
			if _edit_drag_btn:
				_edit_drag_start = t.position - _edit_drag_btn.position
		else:
			if _edit_drag_btn:
				_commit_drag(_edit_drag_btn)
				_edit_drag_btn = null
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if _edit_drag_btn:
			var new_pos: Vector2 = d.position - _edit_drag_start
			_edit_drag_btn.position = _clamp_to_viewport(_edit_drag_btn, new_pos)

func _commit_drag(btn: Panel) -> void:
	# Convert the new on-screen position into an offset from the default
	# anchor — so a future viewport / safe-area / scale change still
	# applies the right delta instead of locking absolute pixels.
	var action: String = _btn_actions.get(btn, "")
	if action == "":
		return
	# Snapshot final position, recompute defaults without this entry.
	var dropped_pos: Vector2 = btn.position
	_btn_offsets.erase(action)
	_apply_safe_area()
	var default_pos: Vector2 = btn.position
	_btn_offsets[action] = dropped_pos - default_pos
	_apply_safe_area()
	layout_changed.emit()

func _clamp_to_viewport(btn: Panel, pos: Vector2) -> Vector2:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(
		clampf(pos.x, 0.0, vp.x - btn.size.x),
		clampf(pos.y, 0.0, vp.y - btn.size.y)
	)
