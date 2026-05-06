extends CanvasLayer

# Brief panel shown when the player picks up a named soul — shows the
# name, age, and epitaph over a dimmed background. Auto-dismisses after
# AUTO_HIDE seconds or on input.
#
# UI lives in scenes/ui/SoulRevealPanel.tscn — open that file to tweak
# layout, colours, panel sizing. This script only fills the labels at
# runtime and handles the queue / fade timing.

const AUTO_HIDE:     float = 3.2
const FADE_DURATION: float = 0.35

@onready var _root:     ColorRect      = $Backdrop
@onready var _header:   Label          = $Backdrop/Centerer/Panel/VBox/Header
@onready var _lbl_name: Label          = $Backdrop/Centerer/Panel/VBox/Name
@onready var _lbl_age:  Label          = $Backdrop/Centerer/Panel/VBox/Age
@onready var _lbl_text: Label          = $Backdrop/Centerer/Panel/VBox/Epitaph

var _timer:    float = 0.0
var _visible:  bool  = false
# Queue of pending reveals. Player.deliver_soul emits one
# soul_delivered signal per carried soul on the same frame, so two
# show_soul() calls can land back-to-back. Without a queue the
# second overrides the first instantly and the player only ever
# reads the LAST delivered soul. With this, each reveal plays out
# its full AUTO_HIDE before the next one starts.
var _queue:    Array = []   # Array[Dictionary]

func _ready() -> void:
	layer = 15
	_header.text = _t("soul_reveal.header", {}, "Врятована душа")
	visible = false
	_root.modulate.a = 0.0


# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key

func show_soul(data: Dictionary) -> void:
	# Skip nameless / placeholder dicts.
	var soul_name: String = data.get("name", "")
	if soul_name == "":
		return
	# If a reveal is already on screen, queue this one — it will play
	# next when the current one auto-hides. Otherwise show immediately.
	if _visible:
		_queue.append(data)
		return
	_show_now(data)


func _show_now(data: Dictionary) -> void:
	var age:     int    = int(data.get("age", 0))
	var epitaph: String = data.get("epitaph", "")
	_lbl_name.text = data.get("name", "")
	_lbl_age.text  = "%d років" % age if age > 0 else ""
	_lbl_age.visible = age > 0
	_lbl_text.text = epitaph

	visible = true
	_timer = AUTO_HIDE
	_visible = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func _process(delta: float) -> void:
	if not _visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_hide()

func _unhandled_input(event: InputEvent) -> void:
	if not _visible:
		return
	if event is InputEventKey and event.pressed and not event.is_echo():
		_hide()
	elif event is InputEventScreenTouch and event.pressed:
		_hide()
	elif event is InputEventMouseButton and event.pressed:
		_hide()

func _hide() -> void:
	if not _visible:
		return
	_visible = false
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(_on_hidden)


# Called after the fade-out finishes. If another reveal is queued,
# pop it and show it next; otherwise fully hide the layer.
func _on_hidden() -> void:
	if not _queue.is_empty():
		var next_data: Dictionary = _queue.pop_front()
		_show_now(next_data)
		return
	visible = false
