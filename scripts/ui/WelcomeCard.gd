extends CanvasLayer

# Pre-prologue welcome moment shown on the very first time a player
# enters the Hub. Bigger and longer than TitleCard — establishes the
# game identity before the dialogue with God starts.
#
# Layout:
#   ┌──────────────────────────────────────┐
#   │                                      │
#   │        ESCAPE FROM HELL              │   ← Display, huge, gold
#   │                                      │
#   │      Священник падає в Лімб.         │   ← Body italic-ish dim
#   │                                      │
#   │       Натисни щоб почати             │   ← Caption, pulses
#   │                                      │
#   └──────────────────────────────────────┘
#
# Lifecycle:
#   • Fade in title 0.8 s
#   • After title visible 0.5 s, tagline fades in 0.6 s
#   • After tagline visible 0.6 s, press-to-start pulse appears
#   • Any tap dismisses (fade out 0.5 s, then `dismissed` signal)
#   • Auto-dismiss timer: 6.0 s of total visibility — caps the welcome
#     so players who go AFK don't sit in limbo forever
#
# Reduce-motion aware: instant transitions instead of staggered fades,
# but the auto-dismiss timer still runs.

signal dismissed

const TITLE_FADE_S    := 0.8
const TAGLINE_DELAY   := 0.5
const TAGLINE_FADE_S  := 0.6
const PRESS_DELAY     := 0.6
const AUTO_DISMISS_S  := 6.0
const FADE_OUT_S      := 0.5

var _root: Control = null
var _title_lbl: Label = null
var _tagline_lbl: Label = null
var _press_lbl: Label = null
var _press_tween: Tween = null
var _dismissed: bool = false
var _t: float = 0.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 14   # above HUD/TopBar/TitleCard so the welcome is the topmost beat
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_run_intro_sequence()


func _process(delta: float) -> void:
	if _dismissed:
		return
	_t += delta
	if _t >= AUTO_DISMISS_S:
		_dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	# Don't dismiss in the first 0.4 s — accidental taps from the
	# previous screen (clicked "Грати" button) would otherwise eat
	# the welcome immediately.
	if _t < 0.4:
		return
	var press: bool = (
			event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_cancel")
			or (event is InputEventMouseButton and event.pressed)
			or (event is InputEventScreenTouch and event.pressed))
	if press:
		_dismiss()
		get_viewport().set_input_as_handled()


# ── Intro sequence ────────────────────────────────────────────────────────────

func _run_intro_sequence() -> void:
	if _is_reduce_motion():
		# Skip staggered fades — show everything immediately, but keep
		# the auto-dismiss timer so the card eventually clears.
		_title_lbl.modulate.a   = 1.0
		_tagline_lbl.modulate.a = 1.0
		_press_lbl.modulate.a   = 1.0
		return
	# Title fades in first.
	var tw := create_tween()
	tw.tween_property(_title_lbl, "modulate:a", 1.0, TITLE_FADE_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Tagline waits, then fades.
	tw.tween_property(_tagline_lbl, "modulate:a", 1.0, TAGLINE_FADE_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT) \
		.set_delay(TAGLINE_DELAY)
	# Press-to-start joins last and pulses indefinitely.
	tw.tween_callback(_start_press_pulse).set_delay(PRESS_DELAY)


# Looped alpha pulse on the press-to-start label so it draws the eye.
func _start_press_pulse() -> void:
	_press_lbl.modulate.a = 1.0
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = create_tween()
	_press_tween.set_loops()
	_press_tween.tween_property(_press_lbl, "modulate:a", 0.45, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_press_tween.tween_property(_press_lbl, "modulate:a", 1.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ── Dismiss ───────────────────────────────────────────────────────────────────

func _dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	if _is_reduce_motion():
		dismissed.emit()
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		dismissed.emit()
		queue_free())


# ── Helpers ───────────────────────────────────────────────────────────────────

func _t_loc(key: String, fallback: String = "") -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key))
	return fallback if not fallback.is_empty() else key


func _is_reduce_motion() -> bool:
	var ms: Node = get_node_or_null("/root/MotionSettings")
	return ms and ms.has_method("is_enabled") and ms.is_enabled()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.0, 0.0, 0.0, 1.0)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(centerer)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 28)
	v.custom_minimum_size = Vector2(900, 0)
	centerer.add_child(v)

	_title_lbl = Label.new()
	_title_lbl.theme_type_variation = "DisplayLabel"
	_title_lbl.text = _t_loc("welcome_card.title", "ESCAPE FROM HELL")
	_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_constant_override("outline_size", 10)
	_title_lbl.modulate.a = 0.0   # fades in
	v.add_child(_title_lbl)

	_tagline_lbl = Label.new()
	_tagline_lbl.theme_type_variation = "BodyLabel"
	_tagline_lbl.text = _t_loc("welcome_card.tagline",
			"Священник падає в Лімб.")
	_tagline_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tagline_lbl.modulate.a = 0.0
	v.add_child(_tagline_lbl)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 60)
	v.add_child(spacer)

	_press_lbl = Label.new()
	_press_lbl.theme_type_variation = "MutedLabel"
	_press_lbl.text = _t_loc("welcome_card.press_to_start",
			"Натисни щоб почати")
	_press_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_press_lbl.modulate.a = 0.0
	v.add_child(_press_lbl)
