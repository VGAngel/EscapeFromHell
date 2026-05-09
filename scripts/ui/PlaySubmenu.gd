extends CanvasLayer

# Play submenu — opens when the player taps "Грати" on the main menu.
#
# Replaces the old "tap Play → jump straight to Hub" flow with a
# small intermediate screen that lets the player choose how they
# want to enter the descent:
#
#   ▶ Продовжити — рівень N    (the default, mirrors the legacy flow)
#   📜 Рівні                   (player-facing LevelSelect — only
#                               unlocked levels, with star + best-time
#                               summary per row)
#   🔧 Levels (debug)          (existing LevelDebugMenu — every level
#                               accessible regardless of progress)
#   👤 Профіль: <name>         (active profile name displayed inline;
#                               opens ProfileScreen on tap)
#   🌱 Seed: <code>            (current world seed inline)
#
# The submenu itself is built in code (no .tscn) and emits one signal
# per option so MainMenu stays the dispatch point. Closes via Esc / ✕.

signal closed
signal continue_pressed
signal levels_pressed
signal levels_debug_pressed
signal profile_pressed
signal seed_pressed


const FADE_DURATION := 0.25
const PAL := preload("res://scripts/ui/Palette.gd")


var _root: ColorRect = null
var _vbox: VBoxContainer = null
var _btn_continue: Button = null
var _btn_levels: Button = null
var _btn_levels_debug: Button = null
var _btn_profile: Button = null
var _btn_seed: Button = null


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_root.modulate.a = 0.0
	visible = false
	# Refresh on language switch so the inline profile/seed labels stay
	# in step with Settings → Language.
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_signal("language_changed"):
		loc.language_changed.connect(_on_language_changed)
	# Refresh on profile switch — Continue label needs the new save's
	# current_level, profile row needs the new name, seed row the new seed.
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm and sm.has_signal("profile_switched"):
		sm.profile_switched.connect(func(_s: int) -> void:
			if visible: _refresh_labels())


func _on_language_changed(_lang: String) -> void:
	_refresh_labels()


# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	return _t("play_submenu.title", {}, "Грати")


func open() -> void:
	visible = true
	_refresh_labels()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)


func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit())


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh_labels() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	# "Продовжити — рівень N" — falls back to "Грати" on first run.
	var lvl: int = 1
	var played: bool = false
	if sm and sm.has_method("get_current_level"):
		lvl = int(sm.get_current_level())
	if sm and sm.has_method("get_stat"):
		played = float(sm.get_stat("total_play_seconds", 0.0)) > 0.0
	if _btn_continue:
		if played and lvl > 1:
			_btn_continue.text = _t("play_submenu.continue_format",
					{"n": lvl}, "▶  Продовжити — рівень %d" % lvl)
		else:
			_btn_continue.text = _t(
					"play_submenu.continue_first", {}, "▶  Грати")
	if _btn_levels:
		_btn_levels.text = _t(
				"play_submenu.levels", {}, "📜  Рівні")
	if _btn_levels_debug:
		_btn_levels_debug.text = _t(
				"play_submenu.levels_debug", {}, "🔧  Levels (debug)")
	# Profile row: shows the active profile name inline.
	if _btn_profile and sm:
		var pname: String = ""
		if sm.has_method("get_profile_name"):
			pname = String(sm.get_profile_name())
		if pname.is_empty():
			pname = _t("play_submenu.profile_unknown", {}, "Невідомий")
		_btn_profile.text = _t("play_submenu.profile_format",
				{"name": pname}, "👤  Профіль: %s" % pname)
	# Seed row: 8-char code or "(авто)" if empty.
	if _btn_seed and sm:
		var seed_s: String = ""
		if sm.has_method("get_world_seed_str"):
			seed_s = String(sm.get_world_seed_str())
		var seed_label: String = (
				seed_s if not seed_s.is_empty()
				else _t("play_submenu.seed_auto", {}, "(авто)"))
		_btn_seed.text = _t("play_submenu.seed_format",
				{"seed": seed_label}, "🌱  Seed: %s" % seed_label)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _show_debug_ui() -> bool:
	var bc: Node = get_node_or_null("/root/BuildConfig")
	if bc and bc.has_method("show_debug_ui"):
		return bool(bc.show_debug_ui())
	# Fallback if BuildConfig autoload is missing — mirror its default
	# heuristic so headless tests still get the editor/dev behaviour.
	return not OS.has_feature("release")


func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	# Use the global `Loc` autoload directly so this resolves correctly
	# from outside the active scene tree (unit tests, scene transitions).
	# The previous get_node_or_null("/root/Loc") form errored "Can't
	# use get_node() with absolute paths from outside the active scene
	# tree" on detached instances and returned null → fell through to
	# the raw key string.
	if Loc and Loc.has_method("t"):
		return String(Loc.t(key, params))
	return fallback if not fallback.is_empty() else key


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_root = ColorRect.new()
	_root.color = Color(0.04, 0.03, 0.05, 0.88)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var centerer := CenterContainer.new()
	centerer.set_anchors_preset(Control.PRESET_FULL_RECT)
	centerer.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(centerer)

	# Card panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.04, 0.08, 0.96)
	style.border_color = Color(1.0, 0.84, 0.30, 0.30)
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + c, 14)
	style.content_margin_left   = 28.0
	style.content_margin_right  = 28.0
	style.content_margin_top    = 24.0
	style.content_margin_bottom = 24.0
	style.shadow_color  = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size   = 8
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	centerer.add_child(panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 14)
	panel.add_child(_vbox)

	# Header
	var header := Label.new()
	header.theme_type_variation = "TitleLabel"
	header.text = _t("play_submenu.title", {}, "Грати")
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(header)

	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = PAL.BORDER_DIM
	sep_style.content_margin_top = 1.0
	sep_style.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", sep_style)
	_vbox.add_child(sep)

	# Continue (primary)
	_btn_continue = _make_row_button()
	_btn_continue.pressed.connect(func() -> void:
		continue_pressed.emit()
		close())
	_vbox.add_child(_btn_continue)

	# Player-facing Levels
	_btn_levels = _make_row_button()
	_btn_levels.pressed.connect(func() -> void: levels_pressed.emit())
	_vbox.add_child(_btn_levels)

	# Levels (debug) — hidden in release builds (BuildConfig.show_debug_ui()).
	_btn_levels_debug = _make_row_button()
	_btn_levels_debug.add_theme_color_override(
			"font_color", Color(1.0, 0.65, 0.35, 1.0))
	_btn_levels_debug.pressed.connect(func() -> void: levels_debug_pressed.emit())
	_vbox.add_child(_btn_levels_debug)
	_btn_levels_debug.visible = _show_debug_ui()

	# Profile (with active marker)
	_btn_profile = _make_row_button()
	_btn_profile.pressed.connect(func() -> void: profile_pressed.emit())
	_vbox.add_child(_btn_profile)

	# Seed — hidden in release builds (devs use it for repro).
	_btn_seed = _make_row_button()
	_btn_seed.pressed.connect(func() -> void: seed_pressed.emit())
	_vbox.add_child(_btn_seed)
	_btn_seed.visible = _show_debug_ui()

	# Spacer + Close button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_vbox.add_child(spacer)
	var btn_close := _make_row_button()
	btn_close.text = _t("play_submenu.back", {}, "✕  Назад")
	btn_close.add_theme_color_override(
			"font_color", Color(0.78, 0.74, 0.84))
	btn_close.pressed.connect(close)
	_vbox.add_child(btn_close)


# Single styled button row used by every option in the submenu so
# they share visual rhythm.
func _make_row_button() -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(640, 70)
	btn.add_theme_font_size_override("font_size", 24)
	var n := _row_box(false)
	var h := _row_box(true)
	for state in ["normal", "focus"]:
		btn.add_theme_stylebox_override(state, n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", n)
	return btn


func _row_box(hover: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = (
			Color(0.10, 0.08, 0.14, 0.95) if not hover
			else Color(0.18, 0.14, 0.22, 0.95))
	s.border_color = PAL.BORDER_NEUTRAL
	for side in ["left", "right", "top", "bottom"]:
		s.set("border_width_" + side, 1)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		s.set("corner_radius_" + c, 10)
	return s
