extends CanvasLayer

# Souls-style "CIRCLE 1 — LIMBO" card shown briefly when a level loads.
# Establishes gravitas before the action starts and gives every level
# transition the same beat — a small but powerful onboarding lift.
#
# Layout (centred):
#   ┌────────────────────────────────────┐
#   │           Коло 1                   │   ← TitleLabel
#   │           ЛІМБ                     │   ← DisplayLabel (huge)
#   │         Рівень 1                   │   ← MutedLabel
#   └────────────────────────────────────┘
#
# Lifecycle:
#   • Fade in 0.45 s on _ready
#   • Hold for HOLD_DURATION (or until tap)
#   • Fade out 0.55 s and queue_free
#
# Reduce-motion aware: instant transitions instead of tweens, but the
# card still shows for HOLD_DURATION so readers who want the info get it.
#
# Usage:
#   var card = preload("res://scripts/ui/TitleCard.gd").new()
#   card.setup(circle_id, level_id)
#   add_child(card)

const HOLD_DURATION := 2.4
const FADE_IN_S     := 0.45
const FADE_OUT_S    := 0.55

var _circle: int = 1
var _level: int  = 1
var _root: Control = null
var _t_label: Label = null      # "Коло N"
var _name_label: Label = null   # huge circle name
var _level_label: Label = null  # "Рівень N"
var _hold_t: float = 0.0
var _dismissed: bool = false


# ── Public ────────────────────────────────────────────────────────────────────

func setup(circle: int, level: int) -> void:
	_circle = circle
	_level = level


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 12   # above HUD (10) and TopBar (11)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# If the caller didn't call setup() before adding us, fall back to
	# whatever GameManager has — better than blank.
	if _circle == 1 and _level == 1 and GameManager:
		_circle = int(GameManager.current_circle)
		_level  = int(GameManager.current_level_id)
	_apply_text()
	_root.modulate.a = 0.0
	if _is_reduce_motion():
		_root.modulate.a = 1.0
	else:
		var tw := create_tween()
		tw.tween_property(_root, "modulate:a", 1.0, FADE_IN_S) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if _dismissed:
		return
	_hold_t += delta
	if _hold_t >= HOLD_DURATION:
		_dismiss()


func _unhandled_input(event: InputEvent) -> void:
	if _dismissed:
		return
	# Any tap or pause-tier input dismisses early. We accept ui_accept,
	# ui_cancel, and any "pressed" mouse/touch event.
	var press: bool = (
			event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_cancel")
			or (event is InputEventMouseButton and event.pressed)
			or (event is InputEventScreenTouch and event.pressed))
	if press:
		_dismiss()
		get_viewport().set_input_as_handled()


# ── Internal ──────────────────────────────────────────────────────────────────

func _dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	if _is_reduce_motion():
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT_S) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _apply_text() -> void:
	if _t_label:
		_t_label.text = _t("title_card.circle_format", {"n": _circle},
				"Коло %d" % _circle)
	if _name_label:
		_name_label.text = _circle_name(_circle).to_upper()
	if _level_label:
		_level_label.text = _t("title_card.level_format", {"n": _level},
				"Рівень %d" % _level)


# Per-circle nickname pulled from Loc; the const below is the UA
# fallback used when Loc isn't loaded (headless tests / boot races).
const _FALLBACK_NAMES := {
	1:  "Лімб", 2:  "Хіть", 3:  "Жага",
	4:  "Жадібність", 5:  "Гнів", 6:  "Єресь",
	7:  "Насилля", 8:  "Шахрайство", 9:  "Зрада",
	10: "Трон Люцифера",
}


func _circle_name(c: int) -> String:
	var fallback: String = String(_FALLBACK_NAMES.get(c, ""))
	return _t("title_card.circles." + str(c), {}, fallback)


func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key


func _is_reduce_motion() -> bool:
	var ms: Node = get_node_or_null("/root/MotionSettings")
	return ms and ms.has_method("is_enabled") and ms.is_enabled()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Dim the world so the card reads cleanly.
	_root = ColorRect.new()
	_root.color = Color(0.02, 0.01, 0.03, 0.78)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(centerer)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	v.custom_minimum_size = Vector2(800, 0)
	centerer.add_child(v)

	# "Коло N" — small accent
	_t_label = Label.new()
	_t_label.theme_type_variation = "TitleLabel"
	_t_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_t_label)

	# Big circle name
	_name_label = Label.new()
	_name_label.theme_type_variation = "DisplayLabel"
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Letter-spacing nudge for engraved feel — UITheme already adds an
	# outline at this size; we just ensure the text isn't cramped.
	_name_label.add_theme_constant_override("outline_size", 8)
	v.add_child(_name_label)

	# Spacer
	var sep := HSeparator.new()
	sep.theme_type_variation = "GoldSeparator"
	sep.custom_minimum_size = Vector2(180, 0)
	v.add_child(sep)

	# "Рівень N"
	_level_label = Label.new()
	_level_label.theme_type_variation = "MutedLabel"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_level_label)
