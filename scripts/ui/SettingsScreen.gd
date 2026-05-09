extends CanvasLayer

# Accessible from: main menu, pause menu.
# Persists settings to user://settings.json on every change.
# Call open() / close() from outside.
#
# Static layout (panel, tab bar, four pages with their sliders/toggles/
# choice buttons, mobile section, key reset button) lives entirely in
# scenes/ui/SettingsScreen.tscn. This script wires up signals, applies
# the on/off + active styling at runtime, and dynamically generates the
# per-action key rows (one per REBINDABLE_ACTIONS entry).

signal closed

# ── Constants ─────────────────────────────────────────────────────────────────
const SAVE_PATH     := "user://settings.json"
const FADE_DURATION := 0.25

# Audio bus indices (must match Project > Audio Bus Layout)
const BUS_MASTER := "Master"
const BUS_MUSIC  := "Music"
const BUS_SFX    := "SFX"

# Resolution presets: logical (base) size used by the stretch viewport
const RESOLUTIONS := {
	"fhd": Vector2i(1080, 1920),
	"hd":  Vector2i(720,  1280),
}

# ── Defaults ──────────────────────────────────────────────────────────────────
const DEFAULTS := {
	"volume_master":    80,
	"volume_music":     60,
	"volume_sfx":       90,
	"mute_all":         false,
	"language":         "uk",
	"vsync":            true,
	"resolution":       "fhd",
	"haptics":          true,
	"reduce_motion":    false,
}

# ── State ─────────────────────────────────────────────────────────────────────
var _data: Dictionary = {}
var _active_tab: int  = 0

## Actions exposed to rebinding. Order = display order in the Keys tab.
const REBINDABLE_ACTIONS: Array[Dictionary] = [
	{"action": "move_left",  "label": "Вліво"},
	{"action": "move_right", "label": "Вправо"},
	{"action": "jump",       "label": "Стрибок"},
	{"action": "action",     "label": "Посох"},
	{"action": "interact",   "label": "Взаємодія"},
	{"action": "look_down",  "label": "Огляд вниз"},
	{"action": "pray",       "label": "Молитва"},
]
var _key_btns:        Dictionary = {}   # action → Button
var _binding_action:  String     = ""   # non-empty = waiting for next key
var _default_key_events: Dictionary = {}   # action → Array[InputEvent]

# Two-stage reset state for the "↺ Скинути всі" button.
var _reset_armed:      bool   = false
var _reset_disarm_at:  float  = 0.0

# Mobile-layout edit overlay — built at runtime when the player taps
# "Edit positions"; freed when they tap Done.
var _edit_overlay:   CanvasLayer = null

# ── Scene refs ────────────────────────────────────────────────────────────────
@onready var _root:        ColorRect = $Backdrop
@onready var _close_btn:   Button    = $Backdrop/Centerer/Panel/VBox/TitleMargin/TitleBar/CloseButton
@onready var _title_label: Label     = $Backdrop/Centerer/Panel/VBox/TitleMargin/TitleBar/Title

@onready var _tab_sound:    Button = $Backdrop/Centerer/Panel/VBox/TabBar/TabSound
@onready var _tab_language: Button = $Backdrop/Centerer/Panel/VBox/TabBar/TabLanguage
@onready var _tab_graphics: Button = $Backdrop/Centerer/Panel/VBox/TabBar/TabGraphics
@onready var _tab_keys:     Button = $Backdrop/Centerer/Panel/VBox/TabBar/TabKeys

@onready var _page_sound:    Control = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage
@onready var _page_language: Control = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/LanguagePage
@onready var _page_graphics: Control = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/GraphicsPage
@onready var _page_keys:     Control = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage

# Sound page widgets
@onready var _sl_master:  HSlider = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/MasterRow/Slider
@onready var _lbl_master: Label   = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/MasterRow/Value
@onready var _sl_music:   HSlider = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/MusicRow/Slider
@onready var _lbl_music:  Label   = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/MusicRow/Value
@onready var _sl_sfx:     HSlider = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/SfxRow/Slider
@onready var _lbl_sfx:    Label   = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/SfxRow/Value
@onready var _toggle_mute:    Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/MuteRow/Toggle
@onready var _toggle_haptics: Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/SoundPage/HapticsRow/Toggle

# Language page widgets — keyed by code so a future "+ German" tab is one
# extra Button node + one entry in this dict.
@onready var _lang_uk: Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/LanguagePage/LangUk
@onready var _lang_en: Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/LanguagePage/LangEn

# Graphics page widgets
@onready var _toggle_vsync:        Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/GraphicsPage/VsyncRow/Toggle
@onready var _toggle_reduce_motion: Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/GraphicsPage/ReduceMotionRow/Toggle
@onready var _res_fhd: Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/GraphicsPage/ResFhd
@onready var _res_hd:  Button = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/GraphicsPage/ResHd

# Keys page widgets
@onready var _size_slider:      HSlider = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/MobileSection/SizeRow/SizeSlider
@onready var _size_label:       Label   = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/MobileSection/SizeRow/SizeValue
@onready var _btn_edit_mobile:  Button  = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/MobileSection/EditMobileButton
@onready var _btn_reset_mobile: Button  = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/MobileSection/ResetMobileButton
@onready var _key_rows:         VBoxContainer = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/KeyRows
@onready var _reset_btn:        Button  = $Backdrop/Centerer/Panel/VBox/PagesMargin/PagesStack/KeysPage/ResetButton

# Computed at _ready time — keep ordering stable for _switch_tab.
var _tab_btns:     Array = []
var _tab_pages:    Array = []
var _lang_btns:    Dictionary = {}   # code → Button
var _resolution_btns: Dictionary = {}

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_default_keys()   # snapshot project.godot bindings BEFORE any user override
	_load()
	_wire_widgets()
	_apply_all()
	_root.modulate.a = 0.0
	visible    = false


# Loc.t() with fallback so headless tests / boot without Loc still render.
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

## Snapshot the original key events for every rebindable action so the
## "Reset" button can roll back and so we know what the project file
## defines vs what the user customised.
func _capture_default_keys() -> void:
	for entry in REBINDABLE_ACTIONS:
		var action: String = entry.action
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for ev in InputMap.action_get_events(action):
			events.append(ev)
		_default_key_events[action] = events

# ── Persist ───────────────────────────────────────────────────────────────────

func _load() -> void:
	_data = DEFAULTS.duplicate()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		for key in parsed:
			_data[key] = parsed[key]

func _save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("SettingsScreen: cannot write " + SAVE_PATH)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()

# ── Public ────────────────────────────────────────────────────────────────────

func router_title() -> String:
	if Loc and Loc.has_method("t"):
		return String(Loc.t("router_title.settings"))
	return "Налаштування"

func open() -> void:
	visible = true
	_refresh_widgets()
	_switch_tab(0)
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, FADE_DURATION)

func close() -> void:
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_DURATION)
	tw.tween_callback(func() -> void:
		visible = false
		closed.emit()
	)

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ── Apply all settings on startup ─────────────────────────────────────────────

func _apply_all() -> void:
	_apply_volume(BUS_MASTER, _data.get("volume_master", 80))
	_apply_volume(BUS_MUSIC,  _data.get("volume_music",  60))
	_apply_volume(BUS_SFX,    _data.get("volume_sfx",    90))
	_apply_mute(_data.get("mute_all", false))
	_apply_vsync(_data.get("vsync", true))
	_apply_resolution(_data.get("resolution", "fhd"))
	_apply_keybindings(_data.get("keybindings", {}))
	_apply_haptics(_data.get("haptics", true))
	_apply_language(_data.get("language", "uk"))
	_apply_reduce_motion(_data.get("reduce_motion", false))


func _apply_reduce_motion(enabled: bool) -> void:
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_method("set_enabled"):
		ms.set_enabled(enabled)


func _apply_language(code: String) -> void:
	if Loc and Loc.has_method("set_language"):
		Loc.set_language(code)

# ── Volume helpers ────────────────────────────────────────────────────────────

func _apply_volume(bus_name: String, pct: int) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var db: float = linear_to_db(clampf(pct / 100.0, 0.0, 1.0))
	AudioServer.set_bus_volume_db(idx, db)

func _apply_mute(muted: bool) -> void:
	var idx := AudioServer.get_bus_index(BUS_MASTER)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)

func _apply_haptics(enabled: bool) -> void:
	if HapticManager:
		HapticManager.set_enabled(enabled)

func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if enabled else DisplayServer.VSYNC_DISABLED
	)

func _apply_resolution(preset: String) -> void:
	if DisplaySettings:
		DisplaySettings.set_preset(preset)
	else:
		var size: Vector2i = RESOLUTIONS.get(preset, RESOLUTIONS["fhd"])
		get_tree().get_root().content_scale_size = size

# ── Widget callbacks ──────────────────────────────────────────────────────────

func _on_master_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_master"] = pct
	_lbl_master.text = "%d%%" % pct
	_apply_volume(BUS_MASTER, pct)
	_save()

func _on_music_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_music"] = pct
	_lbl_music.text = "%d%%" % pct
	_apply_volume(BUS_MUSIC, pct)
	_save()

func _on_sfx_changed(value: float) -> void:
	var pct := int(value)
	_data["volume_sfx"] = pct
	_lbl_sfx.text = "%d%%" % pct
	_apply_volume(BUS_SFX, pct)
	_save()

func _on_mute_pressed() -> void:
	var muted: bool = not _data.get("mute_all", false)
	_data["mute_all"] = muted
	_apply_mute(muted)
	_update_toggle(_toggle_mute, muted)
	_save()

func _on_haptics_pressed() -> void:
	var enabled: bool = not _data.get("haptics", true)
	_data["haptics"] = enabled
	_apply_haptics(enabled)
	_update_toggle(_toggle_haptics, enabled)
	_save()

func _on_language_pressed(code: String) -> void:
	_data["language"] = code
	for c in _lang_btns:
		_update_toggle(_lang_btns[c], c == code)
	_save()
	# Live language switch — Loc emits language_changed which any
	# subscriber (HeroCard, MainMenu, future TopBar etc.) re-renders on.
	if Loc and Loc.has_method("set_language"):
		Loc.set_language(code)

func _on_vsync_pressed() -> void:
	var enabled: bool = not _data.get("vsync", true)
	_data["vsync"] = enabled
	_apply_vsync(enabled)
	_update_toggle(_toggle_vsync, enabled)
	_save()

func _on_reduce_motion_pressed() -> void:
	var enabled: bool = not _data.get("reduce_motion", false)
	_data["reduce_motion"] = enabled
	_apply_reduce_motion(enabled)
	_update_toggle(_toggle_reduce_motion, enabled)
	_save()

func _on_resolution_pressed(preset: String) -> void:
	_data["resolution"] = preset
	_apply_resolution(preset)
	for p in _resolution_btns:
		_style_choice_btn(_resolution_btns[p], p == preset)
	_save()

# ── Refresh widgets from _data ────────────────────────────────────────────────

func _refresh_widgets() -> void:
	var vm: int  = _data.get("volume_master", 80)
	var vmu: int = _data.get("volume_music",  60)
	var vs: int  = _data.get("volume_sfx",    90)
	var muted: bool = _data.get("mute_all", false)
	var lang: String = _data.get("language", "uk")
	var vsync: bool  = _data.get("vsync", true)
	var res: String  = _data.get("resolution", "fhd")

	_sl_master.value = vm;  _lbl_master.text = "%d%%" % vm
	_sl_music.value  = vmu; _lbl_music.text  = "%d%%" % vmu
	_sl_sfx.value    = vs;  _lbl_sfx.text    = "%d%%" % vs
	_update_toggle(_toggle_mute, muted)
	_update_toggle(_toggle_haptics, _data.get("haptics", true))

	for code in _lang_btns:
		_update_toggle(_lang_btns[code], code == lang)

	_update_toggle(_toggle_vsync, vsync)
	_update_toggle(_toggle_reduce_motion, _data.get("reduce_motion", false))

	for preset in _resolution_btns:
		_style_choice_btn(_resolution_btns[preset], preset == res)

# ── Tab switching ─────────────────────────────────────────────────────────────

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	for i in _tab_btns.size():
		_tab_btns[i].modulate = Color.WHITE if i == idx else Color(0.55, 0.53, 0.62)
	for i in _tab_pages.size():
		_tab_pages[i].visible = i == idx

# ── Wire up scene widgets ─────────────────────────────────────────────────────

func _wire_widgets() -> void:
	_close_btn.pressed.connect(close)

	# Tabs — ordered to match _switch_tab indices.
	_tab_btns = [_tab_sound, _tab_language, _tab_graphics, _tab_keys]
	_tab_pages = [_page_sound, _page_language, _page_graphics, _page_keys]
	for i in _tab_btns.size():
		var idx := i
		_tab_btns[i].pressed.connect(func() -> void: _switch_tab(idx))
	# On narrow viewports drop the text label and keep just the emoji so all
	# four tabs fit comfortably without truncating.
	var compact: bool = get_viewport().get_visible_rect().size.x < 600.0
	if compact:
		_tab_sound.text    = "🔊"
		_tab_language.text = "🌐"
		_tab_graphics.text = "🖥"
		_tab_keys.text     = "⌨"
		for btn: Button in _tab_btns:
			btn.add_theme_font_size_override("font_size", 32)

	# Sound page
	_sl_master.value_changed.connect(_on_master_changed)
	_sl_music.value_changed.connect(_on_music_changed)
	_sl_sfx.value_changed.connect(_on_sfx_changed)
	_toggle_mute.pressed.connect(_on_mute_pressed)
	_toggle_haptics.pressed.connect(_on_haptics_pressed)

	# Language page
	_lang_btns = {"uk": _lang_uk, "en": _lang_en}
	_lang_uk.pressed.connect(_on_language_pressed.bind("uk"))
	_lang_en.pressed.connect(_on_language_pressed.bind("en"))

	# Graphics page
	_toggle_vsync.pressed.connect(_on_vsync_pressed)
	_toggle_reduce_motion.pressed.connect(_on_reduce_motion_pressed)
	_resolution_btns = {"fhd": _res_fhd, "hd": _res_hd}
	_res_fhd.pressed.connect(_on_resolution_pressed.bind("fhd"))
	_res_hd.pressed.connect(_on_resolution_pressed.bind("hd"))

	# Keys page — mobile section
	_size_slider.value_changed.connect(_on_mobile_size_changed)
	_btn_edit_mobile.pressed.connect(_on_edit_mobile_pressed)
	_btn_reset_mobile.pressed.connect(_on_reset_mobile_pressed)

	# Mirror MobileControls' current size if a level is up; otherwise the
	# slider stays at 1.0 from the .tscn until the player drags it.
	var mc: Node = _find_mobile_controls()
	if mc and mc.has_method("get_size_scale"):
		_size_slider.value = float(mc.get_size_scale())
		_size_label.text = "%d%%" % int(_size_slider.value * 100.0)

	# Keys page — per-action rebind rows
	for entry in REBINDABLE_ACTIONS:
		var action: String = entry.action
		# Pull localised label; UA value in REBINDABLE_ACTIONS is the fallback.
		var label: String  = _t(
				"settings.key_label." + action, {}, String(entry.label))
		_key_rows.add_child(_build_key_row(action, label))
	_reset_btn.pressed.connect(_on_reset_keys_pressed)

# ── Toggle / choice button styling ────────────────────────────────────────────

func _update_toggle(btn: Button, active: bool) -> void:
	_style_toggle(btn, active)

func _style_toggle(btn: Button, active: bool) -> void:
	btn.text = _t("settings.toggle_on", {}, "ВКЛ") if active else _t("settings.toggle_off", {}, "ВИКЛ")
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.28, 0.18, 0.42) if active else Color(0.15, 0.14, 0.20)
	s.corner_radius_top_left    = 8
	s.corner_radius_top_right   = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.border_width_left   = 1
	s.border_width_right  = 1
	s.border_width_top    = 1
	s.border_width_bottom = 1
	s.border_color = Color(0.55, 0.35, 0.75) if active else Color(0.28, 0.26, 0.35)
	for state in ["normal","hover","pressed","focus"]:
		btn.add_theme_stylebox_override(state, s)
	btn.add_theme_color_override("font_color",
		Color(0.88, 0.75, 1.00) if active else Color(0.48, 0.46, 0.55))
	btn.add_theme_font_size_override("font_size", 22)

func _style_choice_btn(btn: Button, active: bool) -> void:
	var n := StyleBoxFlat.new()
	var h := StyleBoxFlat.new()
	n.bg_color = Color(0.22, 0.18, 0.32) if active else Color(0.12, 0.11, 0.16)
	h.bg_color = Color(0.28, 0.24, 0.38)
	n.border_color = Color(0.55, 0.38, 0.78) if active else Color(0.24, 0.22, 0.30)
	h.border_color = Color(0.65, 0.48, 0.88)
	for s in [n, h]:
		s.border_width_left   = 1
		s.border_width_right  = 1
		s.border_width_top    = 1
		s.border_width_bottom = 1
		s.corner_radius_top_left    = 10
		s.corner_radius_top_right   = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", n)
	btn.add_theme_stylebox_override("focus",   n)
	btn.add_theme_color_override("font_color",
		Color(0.92, 0.82, 1.00) if active else Color(0.72, 0.70, 0.78))

# ── Keys page rows ────────────────────────────────────────────────────────────

func _build_key_row(action: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 26)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.83, 0.90))
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = _key_label_for_action(action)
	btn.custom_minimum_size = Vector2(220, 56)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 22)
	_style_choice_btn(btn, false)
	btn.pressed.connect(_on_rebind_pressed.bind(action))
	row.add_child(btn)
	_key_btns[action] = btn
	return row

# ── Keybinding logic ──────────────────────────────────────────────────────────

## Read InputMap and return a friendly label for the first key event
## bound to `action` (e.g. "Space", "Z", "← Arrow").
func _key_label_for_action(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var ke: InputEventKey = ev
			var code: int = ke.physical_keycode if ke.physical_keycode != 0 else ke.keycode
			return OS.get_keycode_string(code)
	return "—"

## Click handler — enter "press a key" mode for this action. The next
## key the user presses (caught in _input below) becomes the new binding.
func _on_rebind_pressed(action: String) -> void:
	_binding_action = action
	if _key_btns.has(action):
		_key_btns[action].text = _t("settings.keys_press", {}, "Натисніть клавішу...")
		_key_btns[action].modulate = Color("#FFD700")

func _input(event: InputEvent) -> void:
	if _binding_action == "" or not visible:
		return
	if not (event is InputEventKey):
		return
	var ke: InputEventKey = event
	if not ke.pressed or ke.echo:
		return
	# Esc cancels rebinding without changing anything.
	if ke.physical_keycode == KEY_ESCAPE:
		_refresh_key_btn(_binding_action)
		_binding_action = ""
		get_viewport().set_input_as_handled()
		return
	_set_binding(_binding_action, ke.physical_keycode)
	_binding_action = ""
	get_viewport().set_input_as_handled()

## Replace every key event on `action` with a single new physical_keycode.
## Persists immediately so the new binding survives a restart.
func _set_binding(action: String, physical_keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	# Wipe existing key events; keep non-key events (joypad etc.) untouched
	# by re-adding them after the wipe.
	var keep: Array = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			keep.append(ev)
	InputMap.action_erase_events(action)
	for ev in keep:
		InputMap.action_add_event(action, ev)
	var new_ev := InputEventKey.new()
	new_ev.physical_keycode = physical_keycode as Key
	InputMap.action_add_event(action, new_ev)
	_refresh_key_btn(action)

	# Persist — store the dictionary keyed by action.
	var map: Dictionary = _data.get("keybindings", {})
	map[action] = physical_keycode
	_data["keybindings"] = map
	_save()

func _refresh_key_btn(action: String) -> void:
	if not _key_btns.has(action):
		return
	var btn: Button = _key_btns[action]
	btn.text = _key_label_for_action(action)
	btn.modulate = Color.WHITE

## Apply the saved keybindings dict on startup. Each entry overrides the
## first key event from project.godot for that action; non-key events
## (gamepad / mouse) are preserved.
func _apply_keybindings(map: Dictionary) -> void:
	for action in map.keys():
		if not InputMap.has_action(String(action)):
			continue
		_set_binding_silent(String(action), int(map[action]))

func _set_binding_silent(action: String, physical_keycode: int) -> void:
	# Same logic as _set_binding but without persistence (we ARE the loader).
	var keep: Array = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey):
			keep.append(ev)
	InputMap.action_erase_events(action)
	for ev in keep:
		InputMap.action_add_event(action, ev)
	var new_ev := InputEventKey.new()
	new_ev.physical_keycode = physical_keycode as Key
	InputMap.action_add_event(action, new_ev)


func _on_reset_keys_pressed() -> void:
	# Two-stage flow: first press arms; second press within 4 s commits.
	if not _reset_armed:
		_reset_armed = true
		_reset_disarm_at = Time.get_ticks_msec() / 1000.0 + 4.0
		_reset_btn.text = _t("settings.keys_reset_confirm", {},
			"⚠  Натисни ще раз для підтвердження")
		_reset_btn.add_theme_color_override("font_color", Color("#FFD700"))
		# Schedule disarm — if the player walks away, the button reverts.
		await get_tree().create_timer(4.0, true, false, true).timeout
		var now: float = Time.get_ticks_msec() / 1000.0
		if _reset_armed and now >= _reset_disarm_at - 0.05:
			_reset_armed = false
			_reset_btn.text = _t("settings.keys_reset_all",
				{}, "↺  Скинути всі до стандартних")
			_reset_btn.add_theme_color_override("font_color", Color("#FF8866"))
		return

	# Armed → execute the wipe.
	_reset_armed = false
	_reset_btn.text = _t("settings.keys_reset_all",
		{}, "↺  Скинути всі до стандартних")
	_reset_btn.add_theme_color_override("font_color", Color("#FF8866"))
	for action in _default_key_events.keys():
		InputMap.action_erase_events(action)
		for ev in _default_key_events[action]:
			InputMap.action_add_event(action, ev)
		_refresh_key_btn(String(action))
	_data["keybindings"] = {}
	_save()

# ── Mobile layout (C5) ────────────────────────────────────────────────────────

func _on_mobile_size_changed(value: float) -> void:
	_size_label.text = "%d%%" % int(value * 100.0)
	var mc: Node = _find_mobile_controls()
	if mc and mc.has_method("set_size_scale"):
		mc.set_size_scale(value)
		mc.save_layout()
	else:
		# No active HUD/level — persist size directly via SaveManager so the
		# change takes effect when MobileControls is next instantiated.
		if SaveManager:
			var layout: Dictionary = SaveManager.get_mobile_layout()
			layout["size_scale"] = value
			SaveManager.set_mobile_layout(layout)

func _on_reset_mobile_pressed() -> void:
	var mc: Node = _find_mobile_controls()
	if mc and mc.has_method("reset_layout"):
		mc.reset_layout()
	else:
		if SaveManager:
			SaveManager.set_mobile_layout({})
	_size_slider.value = 1.0   # triggers _on_mobile_size_changed

func _on_edit_mobile_pressed() -> void:
	var mc: Node = _find_mobile_controls()
	var owns_mc: bool = false
	if not mc:
		# No active level/HUD — create a temporary MobileControls for the
		# edit session. It loads the persisted layout itself, lets the player
		# drag buttons around, and saves on Done. Freed when Done is pressed.
		var mc_script: Script = load("res://scripts/ui/MobileControls.gd")
		if not mc_script:
			return
		mc = mc_script.new()
		owns_mc = true
	close()
	# Build the overlay (which also add_child(mc) for the temp case so
	# its `_ready()` runs and the buttons exist) BEFORE flipping edit
	# mode — `set_edit_mode(true)` walks `_btn_actions` to apply the
	# gold-rim glow, and previously the loop ran on an empty dict
	# (mc not yet in tree) so the buttons stayed plain. Players had no
	# visual cue that edit mode was active and assumed nothing happened.
	_show_edit_overlay(mc, owns_mc)
	mc.set_edit_mode(true)

func _show_edit_overlay(mc: Node, owns_mc: bool = false) -> void:
	if _edit_overlay and is_instance_valid(_edit_overlay):
		_edit_overlay.queue_free()
	_edit_overlay = CanvasLayer.new()
	_edit_overlay.layer = 50
	_edit_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(_edit_overlay)

	# Dim the level/menu behind the overlay so it's obvious that edit
	# mode is active and the buttons-being-dragged are the real targets.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_overlay.add_child(dim)

	# Parent the mc into the overlay regardless of who owns it. When the
	# Settings screen is opened from the in-game pause menu, the actual
	# MobileControls lives on HUD's layer=1 — which renders BELOW the
	# pause screen's layer=10 dim. Without reparenting, the player saw
	# the "drag the buttons" hint but the buttons themselves were hidden
	# behind the pause overlay and impossible to grab. We snapshot the
	# original parent + index so _on_edit_done can put it back.
	if mc.has_method("set"):
		mc.set_meta("_edit_origin_parent", mc.get_parent())
		mc.set_meta("_edit_origin_index",  mc.get_index())
	if mc.get_parent() != null:
		mc.get_parent().remove_child(mc)
	_edit_overlay.add_child(mc)
	# Track ownership so _on_edit_done knows whether to free or restore.
	mc.set_meta("_edit_owns_mc", owns_mc)

	var hint := Label.new()
	hint.text = _t("settings.mobile_drag_hint", {}, "Перетягуй кнопки куди зручно. Натисни ✓ коли готовий.")
	hint.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hint.offset_top    = 100.0
	hint.offset_bottom = 200.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 30)
	hint.add_theme_color_override("font_color", Color("#FFD700"))
	hint.add_theme_color_override("font_outline_color", Color(0,0,0,0.85))
	hint.add_theme_constant_override("outline_size", 5)
	_edit_overlay.add_child(hint)

	var done := Button.new()
	done.text = _t("settings.mobile_drag_done", {}, "✓ Готово")
	done.set_anchors_preset(Control.PRESET_CENTER_TOP)
	done.offset_top = 230.0
	done.custom_minimum_size = Vector2(220, 88)
	done.add_theme_font_size_override("font_size", 30)
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.10, 0.18, 0.10)
	ds.border_color = Color("#88DD88")
	for side in ["left","right","top","bottom"]:
		ds.set("border_width_" + side, 2)
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		ds.set("corner_radius_" + c, 10)
	for state in ["normal","hover","pressed","focus"]:
		done.add_theme_stylebox_override(state, ds)
	done.add_theme_color_override("font_color", Color("#88DD88"))
	done.pressed.connect(func() -> void: _on_edit_done(mc))
	_edit_overlay.add_child(done)

func _on_edit_done(mc: Node) -> void:
	if mc and mc.has_method("set_edit_mode"):
		mc.set_edit_mode(false)
		if mc.has_method("save_layout"):
			mc.save_layout()
	# Restore the mc to its original parent (HUD when in-game) so it
	# keeps driving touch input after the edit session. For the
	# main-menu temp-instance case the original parent is the overlay
	# itself or null — we just free the temp mc instead.
	if mc and is_instance_valid(mc):
		var owns_mc: bool = bool(mc.get_meta("_edit_owns_mc", false))
		var origin_parent: Node = mc.get_meta("_edit_origin_parent", null) as Node
		var origin_index: int = int(mc.get_meta("_edit_origin_index", -1))
		if mc.get_parent() != null:
			mc.get_parent().remove_child(mc)
		if owns_mc or origin_parent == null \
				or not is_instance_valid(origin_parent):
			mc.queue_free()
		else:
			origin_parent.add_child(mc)
			if origin_index >= 0 and origin_index < origin_parent.get_child_count():
				origin_parent.move_child(mc, origin_index)
	if _edit_overlay and is_instance_valid(_edit_overlay):
		_edit_overlay.queue_free()
		_edit_overlay = null

func _find_mobile_controls() -> Node:
	# First look inside the active HUD (in-game context).
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() else null
	if hud:
		for child in hud.get_children():
			if child is Control and child.has_method("set_edit_mode"):
				return child
			# Recurse one level — HUD nests MobileControls inside _root.
			for grand in child.get_children():
				if grand is Control and grand.has_method("set_edit_mode"):
					return grand
	# Not in a level — return null so the caller can spin up a temp instance.
	return null
