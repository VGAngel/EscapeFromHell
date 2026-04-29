extends Node

# Auto-wires every BaseButton in the scene tree with two pieces of feel:
#   • A tap-grow scale tween on `pressed` (1.00 → 1.10 → 1.00, 0.18s,
#     EASE_OUT BACK so it overshoots slightly — reads as "satisfying").
#   • HapticManager.tap_light() on mobile.
#
# Audio is already covered by SoundManager's own auto-wiring (each
# button's pressed → "ui.button_click" sfx). UIFeedback is the third
# leg of the same trick: subscribe to the SceneTree's child_entered_tree
# once at boot, and any button created later gets feel for free.
#
# Skip cases:
#   • Buttons in the IconButton theme variation (✕ close, 🔙 back) get
#     a smaller, more subtle pulse so the chrome doesn't visually shake
#     every time you back out of a menu.
#   • Buttons that opt out via meta `feel_disabled = true` — useful for
#     in-edit-mode handles (e.g. MobileControls drag-edit overlay).
#   • Disabled buttons skip both haptic and pulse (no false signal).

const PULSE_AMP_DEFAULT := 1.10
const PULSE_AMP_ICON    := 1.06     # smaller for icon-only buttons
const PULSE_DURATION    := 0.18

# Connection registry so we don't double-wire on re-entry.
var _wired: Dictionary = {}    # button instance_id → true


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Catch buttons created later — same trick SoundManager uses.
	get_tree().node_added.connect(_on_node_added)
	# And wire anything already in the tree at boot.
	_wire_existing_buttons(get_tree().root)


# ── Wiring ────────────────────────────────────────────────────────────────────

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire(node)


func _wire_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_wire(node)
	for child in node.get_children():
		_wire_existing_buttons(child)


# Add the feel callback to a button. Idempotent: re-calling on the same
# button is a no-op (registry guard).
func _wire(btn: BaseButton) -> void:
	var id: int = btn.get_instance_id()
	if _wired.has(id):
		return
	_wired[id] = true
	# Drop from the registry when the button frees so the dict doesn't
	# grow forever across scene changes.
	btn.tree_exited.connect(func() -> void: _wired.erase(id))
	btn.pressed.connect(_on_button_pressed.bind(btn))


# ── On-press feedback ─────────────────────────────────────────────────────────

func _on_button_pressed(btn: BaseButton) -> void:
	if btn.disabled:
		return
	if btn.has_meta("feel_disabled") and bool(btn.get_meta("feel_disabled")):
		return
	_pulse(btn)
	_haptic()


# Pure visual: scale-tween the button up and back. Pivot is set to the
# control's centre so the pulse looks symmetric regardless of layout
# anchoring. Killed on each press so rapid taps don't queue up.
func _pulse(ctrl: Control) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	var amp: float = _amp_for(ctrl)
	ctrl.pivot_offset = ctrl.size * 0.5
	# Use a unique tween per button so concurrent presses on different
	# buttons don't fight; killing the previous one keeps memory clean.
	# `get_meta` errors loudly on missing keys, so guard with `has_meta`.
	if ctrl.has_meta("ui_feedback_tween"):
		var prev: Variant = ctrl.get_meta("ui_feedback_tween")
		if prev != null and prev is Tween and (prev as Tween).is_valid():
			(prev as Tween).kill()
	var tw := ctrl.create_tween()
	ctrl.set_meta("ui_feedback_tween", tw)
	tw.tween_property(ctrl, "scale", Vector2(amp, amp), PULSE_DURATION * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ctrl, "scale", Vector2.ONE, PULSE_DURATION * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _amp_for(ctrl: Control) -> float:
	# IconButton variation gets a smaller bounce so chrome buttons (✕, 🔙,
	# ⏸) don't look jumpy.
	if ctrl is BaseButton:
		var v := String((ctrl as BaseButton).theme_type_variation)
		if v == "IconButton":
			return PULSE_AMP_ICON
	return PULSE_AMP_DEFAULT


func _haptic() -> void:
	var hm: Node = get_node_or_null("/root/HapticManager")
	if hm and hm.has_method("tap_light"):
		hm.tap_light()
