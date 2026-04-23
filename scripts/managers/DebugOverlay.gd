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
	Level.INFO:  Color(0.30, 0.45, 0.65, 0.95),
	Level.WARN:  Color(0.65, 0.50, 0.15, 0.95),
	Level.ERROR: Color(0.70, 0.20, 0.20, 0.96),
}
const LEVEL_PREFIX := {
	Level.INFO:  "ℹ",
	Level.WARN:  "⚠",
	Level.ERROR: "✖",
}

# Colours for each difficulty zone tier.
const ZONE_COLORS := {
	"easy":    Color(0.15, 0.55, 0.25, 0.95),   # green
	"medium":  Color(0.60, 0.55, 0.10, 0.95),   # amber
	"hard":    Color(0.65, 0.35, 0.10, 0.95),   # orange
	"extreme": Color(0.65, 0.12, 0.12, 0.96),   # red
}

var _overlay_visible: bool          = true
var _layer:           CanvasLayer   = null
var _stack:           VBoxContainer = null
var _zone_card:       Control       = null   # persistent zone widget (top-center)
# Cached zone state so we can rebuild the card when room_index changes.
var _zone_state := {
	"level_id":       0,
	"tier":           "",
	"spacing":        0.0,
	"platform_type":  "",
	"platform_width": 0.0,
	"room_index":     -1,
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Release builds: log to stdout only, skip UI.
	if OS.has_feature("release"):
		_overlay_visible = false
		return
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	# F3 toggles the entire overlay (zone card + log stack).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			set_visible_overlay(not _overlay_visible)
			get_viewport().set_input_as_handled()

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

## Show (or update) a persistent zone card in the top-left corner.
## Call once per level load with the GeneratedLevel zone data.
##   level_id      : current level number
##   tier          : "easy" | "medium" | "hard" | "extreme"
##   spacing       : vertical platform spacing in px (from VERTICAL_SPACING)
##   platform_type : preferred platform type string (e.g. "moving_horizontal")
##   platform_width: preferred platform width in px
func show_zone(level_id: int, tier: String, spacing: float,
		platform_type: String, platform_width: float) -> void:
	_zone_state.level_id       = level_id
	_zone_state.tier           = tier
	_zone_state.spacing        = spacing
	_zone_state.platform_type  = platform_type
	_zone_state.platform_width = platform_width
	_zone_state.room_index     = -1
	_rebuild_zone_card()

## Update the room_index suffix on the seed line as the player crosses rooms.
## Called from PlaceholderRoom whenever a room becomes the player's current one.
func set_active_room(room_index: int) -> void:
	if _zone_state.room_index == room_index:
		return
	_zone_state.room_index = room_index
	_rebuild_zone_card()

func _rebuild_zone_card() -> void:
	if not _overlay_visible or not _layer:
		return
	if _zone_state.level_id <= 0:
		return
	if is_instance_valid(_zone_card):
		_zone_card.queue_free()
	_zone_card = _build_zone_card(
		int(_zone_state.level_id),
		String(_zone_state.tier),
		float(_zone_state.spacing),
		String(_zone_state.platform_type),
		float(_zone_state.platform_width),
		int(_zone_state.room_index),
	)
	_layer.add_child(_zone_card)

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

func _build_zone_card(level_id: int, tier: String, spacing: float,
		platform_type: String, platform_width: float, room_index: int = -1) -> Control:
	const W: float = 280.0
	# CenterContainer pins the panel to the top-middle of the viewport without
	# the panel itself stretching to full screen width.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 8
	center.offset_left = 0
	center.offset_right = 0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(W, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	center.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = ZONE_COLORS.get(tier, Color(0.2, 0.2, 0.2, 0.9))
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 8)
	style.content_margin_left   = 10.0
	style.content_margin_right  = 10.0
	style.content_margin_top    = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var lines: Array = [
		"Lvl %d  |  zone: %s" % [level_id, tier.to_upper()],
		"spacing  %d px" % int(spacing),
		"platform %s  %d px" % [platform_type, int(platform_width)],
	]
	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)

	# Seed row — clickable Button styled flat to look like a label.
	# Format: "seed  <level>#<room>  📋" — knowing both reproduces the exact
	# room (Markov layout uses hash(level_id*1000 + room_index) as RNG seed).
	var seed_str: String
	if room_index >= 0:
		seed_str = "%d#%d" % [level_id, room_index]
	else:
		seed_str = str(level_id)
	var seed_btn := Button.new()
	seed_btn.text = "seed  %s  📋" % seed_str
	seed_btn.flat = true
	seed_btn.focus_mode = Control.FOCUS_NONE
	seed_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	seed_btn.add_theme_font_size_override("font_size", 11)
	seed_btn.add_theme_color_override("font_color",         Color(1, 1, 1, 0.95))
	seed_btn.add_theme_color_override("font_hover_color",   Color(1, 1, 0.6, 1.0))
	seed_btn.add_theme_color_override("font_pressed_color", Color(0.7, 1, 0.7, 1.0))
	seed_btn.pressed.connect(_on_seed_pressed.bind(seed_btn, seed_str))
	vbox.add_child(seed_btn)

	return center

func _on_seed_pressed(btn: Button, seed_value: String) -> void:
	DisplayServer.clipboard_set(seed_value)
	var original: String = "seed  %s  📋" % seed_value
	btn.text = "seed  %s  ✓ copied" % seed_value
	# Restore label after a short beat so the user sees the confirmation.
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(btn):
			btn.text = original)

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
