extends Node

# Autoload: DebugOverlay
# On-screen error/warn/info log for dev builds. Each call:
#   1. Forwards to the engine logger (push_error / push_warning / print)
#      so stack traces still appear in Output panel.
#   2. Stacks a coloured card on a high-layer CanvasLayer so the player
#      actually sees what's wrong instead of a silent black scene.
#
# In exported release builds (OS.has_feature("release")) the overlay is
# suppressed — only the engine logger runs. Toggle manually with
# DebugOverlay.set_visible_overlay(false).
#
# Usage:
#   DebugOverlay.error("SoundManager: audio not found — %s" % path)
#   DebugOverlay.warn("LevelGenerator: room fallback for circle %d" % c)
#   DebugOverlay.info("Hub: prologue skipped")

enum Level { INFO, WARN, ERROR }

const MAX_CARDS:      int   = 6
const CARD_LIFETIME:  float = 8.0
const CARD_FADE:      float = 0.4
const CARD_WIDTH:     float = 520.0

const LEVEL_COLORS := {
	Level.INFO:  Color(0.30, 0.45, 0.65, 0.95),   # muted blue
	Level.WARN:  Color(0.65, 0.50, 0.15, 0.95),   # amber
	Level.ERROR: Color(0.70, 0.20, 0.20, 0.96),   # red
}
const LEVEL_PREFIX := {
	Level.INFO:  "ℹ",
	Level.WARN:  "⚠",
	Level.ERROR: "✖",
}

var _overlay_visible:    bool        = true
var _layer:              CanvasLayer = null
var _stack:              VBoxContainer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Release builds: log to stdout only, skip UI.
	if OS.has_feature("release"):
		_overlay_visible = false
		return
	_build_ui()

# ── Public API ────────────────────────────────────────────────────────────────

func info(message: String) -> void:
	_log(Level.INFO, message)
	print("[INFO] " + message)

func warn(message: String) -> void:
	_log(Level.WARN, message)
	push_warning(message)

func error(message: String) -> void:
	_log(Level.ERROR, message)
	push_error(message)

## Silence the overlay without affecting console logging.
func set_visible_overlay(v: bool) -> void:
	_overlay_visible = v
	if _layer:
		_layer.visible = v

# ── Internals ─────────────────────────────────────────────────────────────────

func _log(level: int, message: String) -> void:
	if not _overlay_visible or not _stack:
		return
	# Trim the oldest card if we already show MAX_CARDS.
	while _stack.get_child_count() >= MAX_CARDS:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	_stack.add_child(_build_card(level, message))

func _build_card(level: int, message: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = LEVEL_COLORS.get(level, Color.DARK_GRAY)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		style.set("corner_radius_" + corner, 8)
	style.content_margin_left   = 12.0
	style.content_margin_right  = 12.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = "%s  %s" % [LEVEL_PREFIX.get(level, "·"), message]
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size.x = CARD_WIDTH - 24
	panel.add_child(lbl)

	# Lifetime tween: hold, then fade out, then free.
	var tw := create_tween()
	tw.tween_interval(CARD_LIFETIME)
	tw.tween_property(panel, "modulate:a", 0.0, CARD_FADE)
	tw.tween_callback(func() -> void:
		if is_instance_valid(panel):
			panel.queue_free())
	return panel

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)

	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.offset_left   = -CARD_WIDTH - 12
	_stack.offset_top    = 12
	_stack.offset_right  = -12
	_stack.offset_bottom = 12 + 600
	_stack.add_theme_constant_override("separation", 6)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_stack)
