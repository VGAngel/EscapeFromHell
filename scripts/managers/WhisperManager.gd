extends Node

# Autoload: WhisperManager
#
# Surfaces narrative whispers from God/the demon when the player crosses a
# sin threshold (30 / 60 / 85). One whisper per tier per level — fired by
# the GameManager.sin_changed signal, reset by GameManager.level_started.
#
# Read texts come from `res://whispers_config.json` keyed by tier name.
# UI is a self-built CanvasLayer with a darkened backdrop panel + Label so
# the line is always crisp regardless of the level background behind it.

const CONFIG_PATH := "res://whispers_config.json"

const FADE_IN:        float = 0.6
const HOLD_DURATION:  float = 3.5
const FADE_OUT:       float = 1.2
const TOTAL_DURATION: float = FADE_IN + HOLD_DURATION + FADE_OUT

# Tier thresholds — checked top-to-bottom so the highest available wins
# when the player jumps several tiers in one frame (e.g. demon deal).
const SIN_TIERS := [
	{"key": "tier_85", "min": 85.0},
	{"key": "tier_60", "min": 60.0},
	{"key": "tier_30", "min": 30.0},
]

# ── State ─────────────────────────────────────────────────────────────────────
var _phrases: Dictionary = {}                 # tier key → Array[String]
var _shown_this_level: Dictionary = {}        # tier key → int (cap 1)
var _last_sin: float = 0.0
var _rng := RandomNumberGenerator.new()

# ── UI ────────────────────────────────────────────────────────────────────────
var _layer:   CanvasLayer    = null
var _root:    Control        = null
var _panel:   PanelContainer = null
var _label:   Label          = null
var _tween:   Tween          = null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_load_config()
	_build_ui()
	# GameManager autoload may finish loading after WhisperManager — defer
	# the connect to next frame so the signals are guaranteed present.
	call_deferred("_connect_game_manager")

func _connect_game_manager() -> void:
	if not GameManager:
		return
	if GameManager.has_signal("sin_changed") and not GameManager.sin_changed.is_connected(_on_sin_changed):
		GameManager.sin_changed.connect(_on_sin_changed)
	if GameManager.has_signal("level_started") and not GameManager.level_started.is_connected(_on_level_started):
		GameManager.level_started.connect(_on_level_started)

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_warning("WhisperManager: %s not found — whispers disabled" % CONFIG_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_phrases = parsed.get("tiers", {})

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_level_started(_level_id: int) -> void:
	_shown_this_level.clear()
	_last_sin = SaveManager.get_sin() if SaveManager else 0.0

func _on_sin_changed(new_sin: float) -> void:
	# Find the highest threshold the player crossed in this delta.
	var crossed: String = ""
	for tier in SIN_TIERS:
		if new_sin >= tier.min and _last_sin < tier.min:
			crossed = tier.key
			break
	_last_sin = new_sin
	if crossed != "":
		show_whisper(crossed)

# ── Public API (also used by tests) ───────────────────────────────────────────

## Force-show a whisper from the given tier. Skips silently if the tier was
## already shown this level (one per tier per level rule) or if the config
## doesn't define any phrases for it.
func show_whisper(tier: String) -> void:
	if int(_shown_this_level.get(tier, 0)) >= 1:
		return
	var lines: Array = _phrases.get(tier, [])
	if lines.is_empty():
		return
	var text: String = String(lines[_rng.randi_range(0, lines.size() - 1)])
	_shown_this_level[tier] = 1
	_display(text)

# ── Display ───────────────────────────────────────────────────────────────────

func _display(text: String) -> void:
	if not _label:
		return
	_label.text = text
	_root.modulate.a = 0.0
	_layer.visible = true

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_property(_root, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD_DURATION)
	_tween.tween_property(_root, "modulate:a", 0.0, FADE_OUT)
	_tween.tween_callback(func() -> void: _layer.visible = false)

# ── Build UI — panel + label, anchored top-center for high readability ───────

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 12
	_layer.visible = false
	add_child(_layer)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	_layer.add_child(_root)

	# Center horizontally via shrink-center; vertical position set explicitly.
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.offset_top = 280.0
	_panel.custom_minimum_size = Vector2(720, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.02, 0.06, 0.88)
	style.border_color = Color("#8B0000")
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 2)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.7)
	style.shadow_size = 12
	style.content_margin_left   = 36.0
	style.content_margin_right  = 36.0
	style.content_margin_top    = 22.0
	style.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_panel)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 36)
	# Warm bone-white drift toward red as sin rises — tier sets colour.
	_label.add_theme_color_override("font_color", Color("#FFE4D0"))
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	_label.add_theme_constant_override("outline_size", 7)
	_label.process_mode = Node.PROCESS_MODE_ALWAYS
	_panel.add_child(_label)
