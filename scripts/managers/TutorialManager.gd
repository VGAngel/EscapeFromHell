extends Node

# Autoload: TutorialManager  (res://scripts/managers/TutorialManager.gd)
# Usage: TutorialManager.show_hint("first_soul")
#
# Hints are shown once (persisted via SaveManager) unless flagged show_every_time.
# Text is read directly from tutorial_config.json — no Loc dependency.

signal hint_shown(hint_id: String)
signal hint_dismissed(hint_id: String)

const CONFIG_PATH := "res://tutorial_config.json"

# ── Config ────────────────────────────────────────────────────────────────────
var _triggers:  Dictionary = {}   # hint_id → { text, duration?, show_every_time? }
var _settings:  Dictionary = {}

# ── State ─────────────────────────────────────────────────────────────────────
var _active_id: String = ""
var _is_showing: bool  = false
var _queue:      Array = []        # Array[String] — pending hint ids

# ── UI refs ───────────────────────────────────────────────────────────────────
var _layer:    CanvasLayer = null
var _root:     Control     = null   # tweened for modulate (CanvasLayer has none)
var _label:    Label       = null
var _tween:    Tween       = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_load_config()
	_build_ui()

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("TutorialManager: tutorial_config.json not found — hints disabled")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		push_error("TutorialManager: failed to parse tutorial_config.json")
		return
	_settings  = parsed.get("settings",  {})
	_triggers  = parsed.get("triggers",  {})

# ── Public API ────────────────────────────────────────────────────────────────

func show_hint(hint_id: String) -> void:
	# Two valid hint id shapes:
	#   1. Configured trigger (in tutorial_config.json) — uses the
	#      config's text/text_key/duration/icon.
	#   2. Loc-key passthrough — hint_id starts with "tutorial." and
	#      _display() resolves it through Loc.t() + the fallback
	#      dict. Lets DiscoveryHints fire on ad-hoc keys without
	#      requiring a config entry per pickup type.
	if not _triggers.has(hint_id) and not hint_id.begins_with("tutorial."):
		return
	if _is_seen(hint_id) and not _always_show(hint_id):
		return
	if _is_showing:
		# Queue: don't interrupt a contextual hint with another
		if hint_id not in _queue:
			_queue.append(hint_id)
		return
	_display(hint_id)

func dismiss_current() -> void:
	if _is_showing:
		_do_dismiss()

func is_hint_seen(hint_id: String) -> bool:
	return _is_seen(hint_id)

func reset_all() -> void:
	if SaveManager:
		SaveManager.clear_all_hints()

# ── Input: any game action or touch dismisses ─────────────────────────────────

func _input(_event: InputEvent) -> void:
	# Tutorial hints used to dismiss on ANY key/tap, which broke the
	# flow whenever the player was mid-fight or running from enemies
	# — every gameplay input killed the hint they hadn't read yet.
	#
	# We now let hints play out their adaptive duration in full
	# (5-12 s scaled by word count). Code paths that need to force
	# an early hide call `dismiss_current()` directly (e.g. scene
	# transitions, pause overlay opening).
	pass

## UA fallback strings used when Loc.t() returns the key itself
## (= entry missing from localization/uk.json). Keeps the tutorial
## readable even before localisation catches up — and gives the
## player a helpful first-pass explanation of every mechanic.
const _FALLBACK_TEXT := {
	"tutorial.move":          "Тримай ← / → щоб іти",
	"tutorial.jump":          "Натисни ↑ щоб стрибнути",
	"tutorial.variable_jump": "Тримай ↑ довше — стрибнеш вище",
	"tutorial.look_down":     "Затисни ↓ — камера покаже що внизу",
	"tutorial.staff":         "Натисни ⚔ щоб ударити посохом",
	"tutorial.staff_sin":     "Кожен удар посохом додає гріх. Користуйся обережно.",
	"tutorial.sin_bar":       "Гріх — чорна частина тебе. Накопичується від ударів, смертей, угод. Високий гріх змінює кінцівку.",
	"tutorial.soul_pickup":   "Підійди до душі і натисни E щоб підняти",
	"tutorial.carry_to_exit": "Неси душу до вівтаря зверху рівня",
	"tutorial.enemy_avoid":   "Ворог поряд — обходь або бий посохом",
	"tutorial.enemy_gives_up":"Якщо тікаєш достатньо довго — ворог здається",
	"tutorial.one_way":       "Платформа дозволяє стрибнути ВВЕРХ крізь себе. Натисни ↓ щоб впасти крізь.",
	"tutorial.crumbling":     "Ця платформа розкришиться через секунду після приземлення",
	"tutorial.faith_platform":"Тримай 🙏 щоб платформа стала твердою. Витрачає віру.",
	"tutorial.soul_bridge":   "Душа в руках стає мостом. Кинь її щоб перейти прірву.",
	"tutorial.hidden_souls":  "✦ Приховані душі — шукай уважніше у тіні платформ",
	"tutorial.sleeping_soul": "Сплячі душі мають мінігру. Уважно дивись на іконку.",
	"tutorial.minigame_watch_icon": "Дивись на іконку — вона показує коли натиснути",
	"tutorial.mimic_warning": "Не всі душі справжні. Деякі — це міміки.",
	"tutorial.mimic_exorcism":"Бий посохом по міміку щоб вигнати",
	# Bonus pickups — fired by DiscoveryHints when one comes within
	# 150 px of the player for the first time on this save.
	"tutorial.bonus_holy_water":     "💧 Свята вода — невразливість 5 секунд",
	"tutorial.bonus_prayer_stone":   "🪨 Молитовний камінь — заморожує ворогів 8 секунд",
	"tutorial.bonus_angel_feather":  "🪶 Янгольське перо — подвійний стрибок на 30 секунд",
	"tutorial.bonus_manna":          "✨ Манна — відновлює 1 серце",
	"tutorial.bonus_torch":          "🔦 Факел Надії — освітлює темряву",
}


func _fallback_for(key: String) -> String:
	return String(_FALLBACK_TEXT.get(key, key))


# ── Display ───────────────────────────────────────────────────────────────────

func _display(hint_id: String) -> void:
	var cfg: Dictionary = _triggers.get(hint_id, {})
	# Ad-hoc passthrough: if no trigger config exists but the id is
	# a Loc key (starts with "tutorial."), treat the id itself as
	# the text_key so DiscoveryHints / arbitrary callers can show a
	# hint without registering a config entry.
	if cfg.is_empty() and hint_id.begins_with("tutorial."):
		cfg = {"text_key": hint_id}
	# Resolve display text. The config supports two shapes:
	#   • "text"      → direct Ukrainian fallback (legacy)
	#   • "text_key"  → dot-notation Loc key, e.g. "tutorial.move"
	# When a `text_key` is given we MUST call Loc.t() — otherwise the
	# UI ends up rendering the literal key string ("tutorial.move")
	# which is what the player was complaining about (no readable
	# tutorial text at all).
	var text: String = ""
	if cfg.has("text") and not String(cfg["text"]).is_empty():
		text = String(cfg["text"])
	elif cfg.has("text_key") and not String(cfg["text_key"]).is_empty():
		var key: String = String(cfg["text_key"])
		var loc: Node = get_node_or_null("/root/Loc")
		if loc and loc.has_method("t"):
			var resolved: String = String(loc.t(key))
			# Loc.t() returns the key itself when the entry is missing —
			# fall through to a clearer fallback in that case so the
			# player sees something readable instead of a path.
			text = resolved if resolved != key else _fallback_for(key)
		else:
			text = _fallback_for(key)
	else:
		text = hint_id

	# Adaptive duration: longer hints get more reading time. Average
	# reader does ~3 words/sec including comprehension, so a 16-word
	# sin-bar hint needs ~5-6 s, not the legacy 4 s default. Min 5 s
	# even for very short hints so the player has time to look up.
	var base_dur: float = float(cfg.get("duration",
		_settings.get("hint_display_duration", 5.0)))
	var word_count: int = text.split(" ", false).size()
	var reading_dur: float = clamp(float(word_count) * 0.45, 5.0, 12.0)
	var dur: float = maxf(base_dur, reading_dur)
	var fade_in: float  = float(_settings.get("hint_fade_in",  0.3))
	var fade_out: float = float(_settings.get("hint_fade_out", 0.5))

	_active_id  = hint_id
	_is_showing = true
	_label.text = text
	_root.modulate.a = 0.0
	_layer.visible   = true

	_mark_seen(hint_id)
	hint_shown.emit(hint_id)

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, fade_in)
	_tween.tween_interval(dur)
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out)
	_tween.tween_callback(_on_finished)

func _do_dismiss() -> void:
	if not _is_showing:
		return
	var fade_out: float = float(_settings.get("hint_fade_out", 0.5))
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 0.0, fade_out * 0.5)
	_tween.tween_callback(_on_finished)

func _on_finished() -> void:
	_layer.visible = false
	_root.modulate.a = 0.0
	var finished_id := _active_id
	_active_id  = ""
	_is_showing = false
	hint_dismissed.emit(finished_id)

	# Show next queued hint after a short gap
	if _queue.size() > 0:
		var next: String = _queue.pop_front()
		get_tree().create_timer(0.3).timeout.connect(
			func() -> void: show_hint(next), CONNECT_ONE_SHOT
		)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _is_seen(hint_id: String) -> bool:
	return SaveManager.is_hint_seen(hint_id) if SaveManager else false

func _always_show(hint_id: String) -> bool:
	return bool(_triggers.get(hint_id, {}).get("show_every_time", false))

func _mark_seen(hint_id: String) -> void:
	if _always_show(hint_id):
		return
	if SaveManager:
		SaveManager.mark_hint_seen(hint_id)

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer   = 12
	_layer.visible = false
	add_child(_layer)

	# Full-screen root control — this is what we tween for modulate
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate.a   = 0.0
	_layer.add_child(_root)

	# Pill panel — TOP-center, just below the level info row.
	# Bottom placement was hidden behind mobile controls (←↑→) and
	# the sin bar on portrait phones, so the player never read the
	# tutorial. Top-center is the same eye-line they already use for
	# soul/level info, so the hint actually lands.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_top    = 170.0     # below the level info (~y=70-100)
	panel.offset_bottom = 290.0     # ~120 px tall fits 2-3 lines
	panel.offset_left   = 60.0
	panel.offset_right  = -60.0
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.mouse_filter  = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.04, 0.06, 0.90)
	style.corner_radius_top_left     = 18
	style.corner_radius_top_right    = 18
	style.corner_radius_bottom_left  = 18
	style.corner_radius_bottom_right = 18
	style.border_color = Color(0.30, 0.28, 0.40, 0.80)
	for side in ["left","right","top","bottom"]:
		style.set("border_width_" + side, 1)
	style.content_margin_left   = 24.0
	style.content_margin_right  = 24.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	_root.add_child(panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode        = TextServer.AUTOWRAP_WORD_SMART
	# Bumped from 15 → 22 px. The previous size was illegible on the
	# 1080×1920 portrait builds — players literally couldn't read the
	# hint even when they noticed the panel.
	_label.custom_minimum_size  = Vector2(720, 0)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.86))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_label.add_theme_constant_override("outline_size", 4)
	panel.add_child(_label)
