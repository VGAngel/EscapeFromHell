extends Node

# Autoload: TutorialManager
# Використання: TutorialManager.show_hint("move")

signal hint_shown(hint_id: String)
signal hint_dismissed(hint_id: String)

const CONFIG_PATH := "res://tutorial_config.json"

var _cfg: Dictionary = {}
var _triggers: Dictionary = {}
var _settings: Dictionary = {}

var _active_hint_id: String = ""
var _hint_ui: CanvasLayer = null
var _hint_label: Label = null
var _hint_tween: Tween = null
var _dismiss_timer: float = 0.0
var _is_showing: bool = false

func _ready() -> void:
	_load_config()
	_build_hint_ui()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("TutorialManager: tutorial_config.json not found")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("TutorialManager: failed to parse tutorial_config.json")
		return
	_cfg = json.get_data()
	_settings = _cfg.get("settings", {})
	_triggers = _cfg.get("triggers", {})

# ── Public API ────────────────────────────────────────────────────────────────

func show_hint(hint_id: String) -> void:
	if not _triggers.has(hint_id):
		return
	if _is_seen(hint_id) and not _is_always_show(hint_id):
		return
	if _is_showing:
		_dismiss_current()
	_display_hint(hint_id)
	_mark_seen(hint_id)
	hint_shown.emit(hint_id)

func dismiss_current() -> void:
	if _is_showing:
		_dismiss_current()

func is_hint_seen(hint_id: String) -> bool:
	return _is_seen(hint_id)

func reset_all() -> void:
	if SaveManager:
		SaveManager.clear_all_hints()

# ── Display ───────────────────────────────────────────────────────────────────

func _display_hint(hint_id: String) -> void:
	var trigger: Dictionary = _triggers[hint_id]
	var text_key: String = trigger.get("text_key", "")
	var text: String = Loc.t(text_key) if Loc else text_key

	_active_hint_id = hint_id
	_is_showing = true
	_hint_label.text = text
	_hint_ui.visible = true

	var duration: float = _settings.get("hint_display_duration", 4.0)
	var fade_in: float  = _settings.get("hint_fade_in", 0.3)
	var fade_out: float = _settings.get("hint_fade_out", 0.5)

	# Для minigame_hint — коротша тривалість
	var exceptions: Dictionary = _settings.get("exceptions", {})
	if hint_id in exceptions:
		duration = exceptions[hint_id].get("duration", duration)

	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_ui, "modulate:a", 1.0, fade_in)
	_hint_tween.tween_interval(duration)
	_hint_tween.tween_property(_hint_ui, "modulate:a", 0.0, fade_out)
	_hint_tween.tween_callback(_on_hint_finished)

func _dismiss_current() -> void:
	if not _is_showing:
		return
	var fade_out: float = _settings.get("hint_fade_out", 0.5)
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_property(_hint_ui, "modulate:a", 0.0, fade_out)
	_hint_tween.tween_callback(_on_hint_finished)

func _on_hint_finished() -> void:
	_hint_ui.visible = false
	_hint_ui.modulate.a = 0.0
	var finished_id := _active_hint_id
	_active_hint_id = ""
	_is_showing = false
	hint_dismissed.emit(finished_id)

# ── Input: скип будь-якою кнопкою ────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_showing:
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right") \
	or event.is_action_pressed("jump") or event.is_action_pressed("action"):
		_dismiss_current()
		get_viewport().set_input_as_handled()

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_seen(hint_id: String) -> bool:
	if SaveManager:
		return SaveManager.is_hint_seen(hint_id)
	return false

func _is_always_show(hint_id: String) -> bool:
	var exceptions: Dictionary = _settings.get("exceptions", {})
	return exceptions.get(hint_id, {}).get("show_every_time", false)

func _mark_seen(hint_id: String) -> void:
	if _is_always_show(hint_id):
		return
	if SaveManager:
		SaveManager.mark_hint_seen(hint_id)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_hint_ui() -> void:
	_hint_ui = CanvasLayer.new()
	_hint_ui.layer = 10
	_hint_ui.modulate.a = 0.0
	_hint_ui.visible = false
	add_child(_hint_ui)

	# Контейнер — bottom center з відступом від банера реклами
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.set_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.offset_bottom = -70  # відступ від банера реклами (60px) + 10px
	_hint_ui.add_child(anchor)

	# Панель-пілюля
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.85)
	style.corner_radius_top_left    = 20
	style.corner_radius_top_right   = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	style.content_margin_left   = 20.0
	style.content_margin_right  = 20.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	anchor.add_child(panel)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85, 1.0))
	panel.add_child(_hint_label)
