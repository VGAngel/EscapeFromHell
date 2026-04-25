extends Control

## On-screen touch controls for Android.
## Positioned above the HUD bottom row, adjusted for the SafeArea banner.
## Emits real InputEventAction events so Player.gd input polling works unchanged.

# ── Constants ─────────────────────────────────────────────────────────────────
const BTN_ALPHA   := 0.55
const BTN_ALPHA_PRESSED := 0.75

const SIZE_LARGE  := Vector2(190, 190)  # Jump
const SIZE_MEDIUM := Vector2(150, 150)  # Staff / Pray
const SIZE_SMALL  := Vector2(170, 170)  # Movement (thumb-sized)

const GAP_MOVE := 36.0                 # extra space between ← and →
const GAP := 18.0
const MARGIN_SIDE   := 32.0
const MARGIN_BOTTOM := 24.0            # gap above sin bar

# ── Public nodes (exposed for tests) ─────────────────────────────────────────
var btn_left:  Button = null
var btn_right: Button = null
var btn_jump:  Button = null
var btn_staff: Button = null
var btn_pray:  Button = null

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_apply_safe_area()
	var sa: Node = get_node_or_null("/root/SafeArea")
	if sa and sa.has_signal("changed"):
		sa.changed.connect(_apply_safe_area)

func _build() -> void:
	btn_left  = _make_btn("←",  "move_left",  SIZE_SMALL)
	btn_right = _make_btn("→",  "move_right", SIZE_SMALL)
	btn_jump  = _make_btn("↑",  "jump",       SIZE_LARGE)
	btn_staff = _make_btn("⚔",  "action",     SIZE_MEDIUM)
	btn_pray  = _make_btn("🙏", "pray",       SIZE_MEDIUM)
	btn_pray.visible = false

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

	# Right cluster: PRAY ← STAFF ← JUMP (right-to-left)
	var rx: float = vp.x - MARGIN_SIDE - SIZE_LARGE.x
	btn_jump.position  = Vector2(rx, floor_y - SIZE_LARGE.y)
	btn_staff.position = Vector2(rx - SIZE_MEDIUM.x - GAP, floor_y - SIZE_MEDIUM.y)
	btn_pray.position  = Vector2(rx - SIZE_MEDIUM.x - GAP - SIZE_MEDIUM.x - GAP,
								 floor_y - SIZE_MEDIUM.y)

# ── Public API ────────────────────────────────────────────────────────────────
func show_pray_button(value: bool) -> void:
	if btn_pray:
		btn_pray.visible = value

# ── Factory ───────────────────────────────────────────────────────────────────
func _make_btn(label: String, action: String, btn_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = btn_size
	btn.size = btn_size
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", int(btn_size.y * 0.38))

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, BTN_ALPHA)
	var r := int(btn_size.x * 0.5)
	style.corner_radius_top_left     = r
	style.corner_radius_top_right    = r
	style.corner_radius_bottom_left  = r
	style.corner_radius_bottom_right = r
	btn.add_theme_stylebox_override("normal", style)

	var style_pressed := style.duplicate()
	style_pressed.bg_color = Color(0.25, 0.25, 0.25, BTN_ALPHA_PRESSED)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.button_down.connect(_fire_action.bind(action, true))
	btn.button_up.connect(_fire_action.bind(action, false))

	add_child(btn)
	return btn

func _fire_action(action: String, pressed: bool) -> void:
	if not InputMap.has_action(action):
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
