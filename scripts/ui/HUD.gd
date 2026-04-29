extends CanvasLayer

# Attach to a CanvasLayer node (layer = 1) inside the level scene.
# Call setup() once after level loads, then use the public API during play.

# ── Signals ───────────────────────────────────────────────────────────────────
signal pause_requested

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_HEARTS      := 6
const LEVEL_INFO_TIME := 3.0

const SIN_COLORS := [
	Color("#FFFFFF"),   # 0–29
	Color("#FFAA00"),   # 30–59
	Color("#FF4400"),   # 60–84
	Color("#AA0000"),   # 85–100
]
const SIN_THRESHOLDS := [0, 30, 60, 85]

# ── Layout roots ──────────────────────────────────────────────────────────────
var _root:         Control          = null

# Top row
var _hearts:       HBoxContainer    = null
var _level_label:  Label            = null
var _souls_total:  Label            = null
var _light_label:  Label            = null
var _timer_label:  Label            = null

# Bottom row
var _ability_row:  HBoxContainer    = null
var _bonus_row:    HBoxContainer    = null
var _souls_level:  Label            = null
# "Carried soul slots" indicator — only visible when capacity > 1 (i.e. the
# soul_echo upgrade has been bought). Shows current/max carried souls.
var _carry_label:  Label            = null

# Sin bar
var _sin_bar:      ColorRect        = null
var _sin_bar_bg:   ColorRect        = null

# Bottom row (kept as a field so _apply_safe_area can reposition it)
var _bottom_row:   HBoxContainer    = null

# Escape timer bar (escape levels only)
var _escape_bar:   ColorRect        = null
var _escape_bg:    ColorRect        = null

# Pause button (on-screen companion to the Esc key binding)
var _pause_btn:    Button           = null

# Mobile on-screen controls (Android)
var _mobile_controls: Control       = null

# ── Runtime state ─────────────────────────────────────────────────────────────
var _hp:           int   = 3
var _max_hp:       int   = 3
var _sin:          float = 0.0
var _souls_found:  int   = 0
var _souls_total_int: int = 0
var _level_info_timer: float = 0.0
var _sin_pulse_timer:  float = 0.0
var _play_time:        float = 0.0
var _timer_running:    bool  = false
var _escape_duration:  float = 0.0
var _escape_elapsed:   float = 0.0
var _escape_active:    bool  = false
var _sin_was_high:     bool  = false

# Bonus slots: bonus_id → { icon_node, timer_label, tween, time_left, duration }
var _active_bonuses: Dictionary = {}

# Ability slots: upgrade_id → { container, used }
var _ability_slots: Dictionary = {}

# Shake tween for hearts
var _hearts_tween: Tween = null

# ── Sin-source toast (S1) ────────────────────────────────────────────────────
# Stack of pop-ups in the bottom-left that show "+1% гріх ⚔ Посох" each
# time GameManager.sin_added fires. Capped + per-cause throttled so per-
# frame ticks (sin_platform, sin_aura) don't spam the screen.
var _sin_toast_box: VBoxContainer = null
const _SIN_TOAST_MAX:           int   = 3
const _SIN_TOAST_FADE_IN:       float = 0.15
const _SIN_TOAST_HOLD:          float = 1.20
const _SIN_TOAST_FADE_OUT:      float = 0.35
const _SIN_TOAST_THROTTLE_SEC:  float = 4.0   # min gap between same-cause toasts
# Pending accumulator per cause so throttled ticks still report the totals
# (e.g. "+6% гріх 🟥 Гріховна платформа" instead of one-tick crumbs).
var _sin_toast_last_t: Dictionary = {}   # cause → seconds-since-startup
var _sin_toast_pending: Dictionary = {}  # cause → accumulated amount
const _SIN_CAUSE_ICONS: Dictionary = {
	"staff":         "⚔",
	"death":         "💀",
	"sin_platform":  "🟥",
	"demon_deal":    "👹",
	"sin_aura":      "🔥",
	"corrupt_soul":  "👻",
	"extra_attempt": "🩸",
	"cleansing":     "✨",
	"confession":    "🙏",
	"unknown":       "❓",
}
const _SIN_CAUSE_LABELS: Dictionary = {
	"staff":         "Посох",
	"death":         "Смерть",
	"sin_platform":  "Гріховна платформа",
	"demon_deal":    "Угода з демоном",
	"sin_aura":      "Аура Люцифера",
	"corrupt_soul":  "Зламана душа",
	"extra_attempt": "Зайва спроба",
	"cleansing":     "Очищення",
	"confession":    "Сповідь",
	"unknown":       "Інше",
}

# ── Init ──────────────────────────────────────────────────────────────────────

# Loc.t() with fallback so headless tests / boot without Loc still render.
func _t(key: String, params: Dictionary = {}, fallback: String = "") -> String:
	var loc: Node = get_node_or_null("/root/Loc")
	if loc and loc.has_method("t"):
		return String(loc.t(key, params))
	return fallback if not fallback.is_empty() else key


func _ready() -> void:
	add_to_group("hud")
	_build_ui()
	# Poison-veins vignette — diegetic full-screen sin indicator that
	# overlays the existing UI without hiding it.
	_install_sin_vignette()
	# Sin-source toast pipeline. GameManager emits sin_added(amount, cause)
	# whenever sin moves; we render a transient pop in the bottom-left so
	# the player can connect each delta to its source.
	if GameManager and GameManager.has_signal("sin_added"):
		GameManager.sin_added.connect(_on_sin_added)


# Add a SinVignette as a non-interactive overlay sibling. Built in code
# so HUD.tscn doesn't change. Sits just above the regular HUD content
# so the veins are visible but the HUD's text/icons remain on top by
# z-order if added to a higher layer; here we add it below interactive
# controls so taps still go through.
func _install_sin_vignette() -> void:
	var v := preload("res://scripts/ui/SinVignette.gd").new()
	v.name = "SinVignette"
	# Insert at index 0 of the HUD so it draws BEHIND the icons and bars
	# but ABOVE the game viewport.
	add_child(v)
	move_child(v, 0)

func setup(circle: int, level: int, max_hp: int, souls_total: int) -> void:
	_max_hp     = max_hp
	_hp         = max_hp
	_souls_found = 0
	_souls_total_int = souls_total

	_set_hearts(_hp, _max_hp)
	_set_sin(SaveManager.get_sin() if SaveManager else 0.0)
	_set_souls_total(SaveManager.get_total_souls() if SaveManager else 0)
	_set_souls_level(0, souls_total)
	_set_light(SaveManager.get_light() if SaveManager else 0)

	_level_label.text = _t("hud.level_info_format",
			{"circle": circle, "level": level},
			"Коло %d • Рівень %d" % [circle, level])
	_level_label.modulate.a = 1.0
	_level_info_timer = LEVEL_INFO_TIME

	_play_time = 0.0
	_timer_running = true
	if _timer_label:
		_timer_label.text = "00:00"
		_timer_label.modulate.a = 0.0

	_refresh_ability_slots()

# ── Public API ────────────────────────────────────────────────────────────────

func set_hp(hp: int, max_hp: int) -> void:
	var damaged := hp < _hp
	var healed  := hp > _hp
	_hp     = hp
	_max_hp = max_hp
	_set_hearts(hp, max_hp)
	if damaged:
		_animate_hearts_shake()
		_flash_screen(Color(1.0, 0.25, 0.25, 0.35), 0.15)
	elif healed:
		_animate_hearts_pulse()

func set_sin(value: float) -> void:
	_set_sin(value)

func add_soul_found() -> void:
	_souls_found += 1
	_set_souls_level(_souls_found, _souls_total_int)
	_pulse_node(_souls_level, 0.3)

func set_total_souls(total: int) -> void:
	_set_souls_total(total)
	_pulse_node(_souls_total, 0.3)

## Update the carried-soul slot indicator. Hidden when capacity <= 1
## (no upgrade) — pre-soul_echo players don't need to know they can hold
## "0/1" of a soul.
func set_carry_state(carried: int, capacity: int) -> void:
	if not _carry_label:
		return
	if capacity <= 1:
		_carry_label.visible = false
		return
	_carry_label.visible = true
	_carry_label.text = "✋ %d/%d" % [carried, capacity]
	_pulse_node(_carry_label, 0.25)

func set_light(amount: int) -> void:
	_set_light(amount)
	if _light_label:
		_pulse_node(_light_label, 0.3)

func start_bonus(bonus_id: String, icon_char: String, duration: float) -> void:
	if _active_bonuses.has(bonus_id):
		_active_bonuses[bonus_id]["time_left"] = duration
		return
	_spawn_bonus_icon(bonus_id, icon_char, duration)

func remove_bonus(bonus_id: String) -> void:
	_despawn_bonus_icon(bonus_id)

func use_ability(upgrade_id: String) -> void:
	if _ability_slots.has(upgrade_id):
		_ability_slots[upgrade_id]["container"].modulate.a = 0.4
		_ability_slots[upgrade_id]["used"] = true

func start_escape_timer(duration: float) -> void:
	_escape_duration = duration
	_escape_elapsed  = 0.0
	_escape_active   = true
	_escape_bg.visible = true
	_escape_bar.visible = true

func stop_escape_timer() -> void:
	_escape_active = false
	_escape_bg.visible  = false
	_escape_bar.visible = false

func stop_play_timer() -> void:
	_timer_running = false

func get_play_time() -> float:
	return _play_time

# ── Process ───────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	# Level info fade out, then fade in play timer
	if _level_info_timer > 0.0:
		_level_info_timer -= delta
		if _level_info_timer <= 0.0:
			var tw := create_tween()
			tw.tween_property(_level_label, "modulate:a", 0.0, 0.5)
			if _timer_label:
				tw.parallel().tween_property(_timer_label, "modulate:a", 1.0, 0.5)

	# Play timer (level stopwatch)
	if _timer_running:
		_play_time += delta
		if _timer_label:
			var total_s: int = int(_play_time)
			@warning_ignore("integer_division")
			var minutes: int = total_s / 60
			_timer_label.text = "%02d:%02d" % [minutes, total_s % 60]

	# Sin pulse at >= 85%
	if _sin >= 85.0:
		_sin_pulse_timer += delta
		var alpha := 0.35 + 0.65 * sin(_sin_pulse_timer * TAU * 1.2)
		_sin_bar.modulate.a = alpha
	else:
		_sin_bar.modulate.a = 1.0
		_sin_pulse_timer = 0.0

	# Bonus timers
	for bid in _active_bonuses.keys():
		var slot: Dictionary = _active_bonuses[bid]
		slot["time_left"] -= delta
		var tl: float = slot["time_left"]
		var lbl: Label = slot["timer_label"]
		if lbl:
			lbl.text = "%.0f" % maxf(tl, 0.0)
			if tl <= 3.0:
				lbl.add_theme_color_override("font_color", Color("#FF4444"))
		if tl <= 0.0:
			_despawn_bonus_icon(bid)

	# Escape timer
	if _escape_active and _escape_duration > 0.0:
		_escape_elapsed += delta
		var ratio: float = clampf(1.0 - _escape_elapsed / _escape_duration, 0.0, 1.0)
		_escape_bar.size.x = _escape_bg.size.x * ratio
		_escape_bar.color = Color("#00FF88").lerp(Color("#FF0000"), 1.0 - ratio)
		if ratio <= 0.0:
			stop_escape_timer()

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		pause_requested.emit()
		get_viewport().set_input_as_handled()

# ── Internal setters ──────────────────────────────────────────────────────────

func _set_hearts(hp: int, max_hp: int) -> void:
	var i := 0
	for child in _hearts.get_children():
		child.text = "♥" if i < hp else "♡"
		child.visible = i < max_hp
		i += 1

func _set_sin(value: float) -> void:
	_sin = clampf(value, 0.0, 100.0)
	var ratio := _sin / 100.0
	_sin_bar.size.x = _sin_bar_bg.size.x * ratio
	_sin_bar.color = _sin_color(_sin)
	if _sin >= 85.0 and not _sin_was_high:
		_sin_was_high = true
		var tw := create_tween()
		tw.tween_property(_sin_bar, "color", Color.WHITE, 0.1)
		tw.tween_property(_sin_bar, "color", _sin_color(_sin), 0.25)
	elif _sin < 85.0:
		_sin_was_high = false

func _set_souls_total(total: int) -> void:
	_souls_total.text = "👻 %d / 100" % total

func _set_souls_level(found: int, total: int) -> void:
	_souls_level.text = "👻 %d / %d" % [found, total]

func _set_light(amount: int) -> void:
	if _light_label:
		_light_label.text = "💡 %d" % amount

func _sin_color(sin_val: float) -> Color:
	var col := SIN_COLORS[0]
	for i in SIN_THRESHOLDS.size():
		if sin_val >= SIN_THRESHOLDS[i]:
			col = SIN_COLORS[i]
	return col

# ── Animations ────────────────────────────────────────────────────────────────

func _animate_hearts_shake() -> void:
	if _hearts_tween:
		_hearts_tween.kill()
	_hearts_tween = create_tween()
	var origin := _hearts.position
	for _i in 4:
		_hearts_tween.tween_property(_hearts, "position", origin + Vector2(randf_range(-4, 4), 0), 0.06)
	_hearts_tween.tween_property(_hearts, "position", origin, 0.05)

func _animate_hearts_pulse() -> void:
	var tw := create_tween()
	tw.tween_property(_hearts, "modulate", Color(0.6, 1.0, 0.6), 0.15)
	tw.tween_property(_hearts, "modulate", Color.WHITE, 0.25)

func _pulse_node(node: Control, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2(1.25, 1.25), duration * 0.4)
	tw.tween_property(node, "scale", Vector2.ONE, duration * 0.6)

func _flash_screen(color: Color, duration: float) -> void:
	if not _root:
		return
	var flash := ColorRect.new()
	flash.color = color
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 50
	_root.add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, duration)
	tw.tween_callback(flash.queue_free)

# ── Bonus icons ───────────────────────────────────────────────────────────────

func _spawn_bonus_icon(bid: String, icon_char: String, duration: float) -> void:
	var container := VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_lbl := Label.new()
	icon_lbl.text = icon_char
	icon_lbl.add_theme_font_size_override("font_size", 33)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(icon_lbl)

	var timer_lbl: Label = null
	if duration > 0.0:
		timer_lbl = Label.new()
		timer_lbl.text = "%.0f" % duration
		timer_lbl.add_theme_font_size_override("font_size", 16)
		timer_lbl.add_theme_color_override("font_color", Color.WHITE)
		timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		container.add_child(timer_lbl)

	_bonus_row.add_child(container)
	_active_bonuses[bid] = {
		"container":   container,
		"timer_label": timer_lbl,
		"time_left":   duration,
		"duration":    duration,
	}

func _despawn_bonus_icon(bid: String) -> void:
	if not _active_bonuses.has(bid):
		return
	var slot: Dictionary = _active_bonuses[bid]
	_active_bonuses.erase(bid)
	var container: Control = slot["container"]
	var tw := create_tween()
	tw.tween_property(container, "modulate:a", 0.0, 0.3)
	tw.tween_callback(container.queue_free)

# ── Ability slots ─────────────────────────────────────────────────────────────

func _refresh_ability_slots() -> void:
	for child in _ability_row.get_children():
		child.queue_free()
	_ability_slots.clear()

	var ability_ids: Array[String] = ["invisibility", "distraction", "decoy"]
	var icons: Array[String]       = ["👁", "🔔", "🌑"]
	for i in ability_ids.size():
		var aid: String = ability_ids[i]
		if SaveManager and not SaveManager.has_upgrade(aid):
			continue
		var container := Control.new()
		container.custom_minimum_size = Vector2(36, 36)

		var lbl := Label.new()
		lbl.text = icons[i]
		lbl.add_theme_font_size_override("font_size", 33)
		lbl.set_anchors_preset(Control.PRESET_CENTER)
		container.add_child(lbl)

		_ability_row.add_child(container)
		_ability_slots[aid] = {"container": container, "used": false}

# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	layer = 1

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	_build_escape_bar()
	_build_top_row()
	_build_bottom_row()
	_build_sin_bar()
	_build_sin_toast_box()
	_build_pause_button()
	_build_mobile_controls()

	_apply_safe_area()
	if Engine.has_singleton("SafeArea") or get_node_or_null("/root/SafeArea"):
		SafeArea.changed.connect(_apply_safe_area)

## Reposition edge-anchored HUD pieces so the ad banner never covers
## them. Delegated to SafeArea so "no_ads" purchase reclaims the space
## automatically.
func _apply_safe_area() -> void:
	var sa: Node = get_node_or_null("/root/SafeArea")
	var banner: int = int(sa.bottom_reserved) if sa else 0
	var vp := get_viewport().get_visible_rect().size

	if _sin_bar_bg:
		_sin_bar_bg.position.y = vp.y - float(banner) - 6.0
		_sin_bar_bg.size.x = vp.x
	if _bottom_row:
		_bottom_row.position.y = vp.y - float(banner) - 6.0 - 36.0 - 8.0
		_bottom_row.size.x = vp.x - 16.0

func _build_escape_bar() -> void:
	_escape_bg = ColorRect.new()
	_escape_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# Only offset_bottom controls height — anchors already fix width to viewport.
	_escape_bg.offset_bottom = 8.0
	_escape_bg.color = Color(0.15, 0.15, 0.15)
	_escape_bg.visible = false
	_root.add_child(_escape_bg)

	_escape_bar = ColorRect.new()
	_escape_bar.position = Vector2.ZERO
	_escape_bar.size = Vector2(0, 8)
	_escape_bar.color = Color("#00FF88")
	_escape_bar.visible = false
	_escape_bg.add_child(_escape_bar)

func _build_top_row() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 0)
	top.offset_left   =  8.0
	# Leave room on the right edge for the pause button built separately.
	top.offset_right  = -56.0
	top.offset_top    = 12.0
	top.offset_bottom = 44.0
	_root.add_child(top)

	# Hearts (left)
	_hearts = HBoxContainer.new()
	_hearts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_hearts)
	for _i in MAX_HEARTS:
		var h := Label.new()
		h.text = "♡"
		h.add_theme_font_size_override("font_size", 27)
		h.add_theme_color_override("font_color", Color("#FF6666"))
		_hearts.add_child(h)

	# Level info (center)
	_level_label = Label.new()
	_level_label.text = ""
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.add_theme_font_size_override("font_size", 21)
	_level_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.85))
	top.add_child(_level_label)

	# Light + total souls (right, stacked)
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 0)
	top.add_child(right_col)

	_souls_total = Label.new()
	_souls_total.text = "👻 0 / 100"
	_souls_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_souls_total.add_theme_font_size_override("font_size", 21)
	right_col.add_child(_souls_total)

	_light_label = Label.new()
	_light_label.text = "💡 0"
	_light_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_light_label.add_theme_font_size_override("font_size", 20)
	_light_label.add_theme_color_override("font_color", Color("#FFD060"))
	right_col.add_child(_light_label)

	# Play timer (centered under level label, fades in after level info fades out)
	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 21)
	_timer_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.85))
	_timer_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer_label.offset_top    = 46.0
	_timer_label.offset_bottom = 66.0
	_timer_label.modulate.a = 0.0
	_root.add_child(_timer_label)

func _build_bottom_row() -> void:
	# Y position is applied in _apply_safe_area so banner toggles reflow.
	_bottom_row = HBoxContainer.new()
	_bottom_row.position = Vector2(8, 0)
	_bottom_row.size = Vector2(get_viewport().get_visible_rect().size.x - 16.0, 36)
	_bottom_row.add_theme_constant_override("separation", 6)
	_root.add_child(_bottom_row)

	# Ability slots (left)
	_ability_row = HBoxContainer.new()
	_ability_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_row.add_theme_constant_override("separation", 4)
	_bottom_row.add_child(_ability_row)

	# Active bonuses (center)
	_bonus_row = HBoxContainer.new()
	_bonus_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bonus_row.add_theme_constant_override("separation", 4)
	_bottom_row.add_child(_bonus_row)

	# Carry-capacity slots — hidden by default, surfaces when soul_echo
	# upgrade is bought (or otherwise capacity > 1).
	_carry_label = Label.new()
	_carry_label.text = "✋ 0/2"
	_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_carry_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_carry_label.add_theme_font_size_override("font_size", 21)
	_carry_label.add_theme_color_override("font_color", Color("#FFD700"))
	_carry_label.visible = false
	_bottom_row.add_child(_carry_label)

	# Level souls counter (right)
	_souls_level = Label.new()
	_souls_level.text = "👻 0 / 0"
	_souls_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_souls_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_souls_level.add_theme_font_size_override("font_size", 21)
	_bottom_row.add_child(_souls_level)

func _build_pause_button() -> void:
	_pause_btn = Button.new()
	_pause_btn.name = "PauseButton"
	_pause_btn.text = "⏸"
	_pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_btn.offset_left   = -52.0
	_pause_btn.offset_right  = -8.0
	_pause_btn.offset_top    = 8.0
	_pause_btn.offset_bottom = 52.0
	_pause_btn.add_theme_font_size_override("font_size", 33)
	_pause_btn.focus_mode = Control.FOCUS_NONE
	_pause_btn.pressed.connect(_on_pause_btn_pressed)
	_root.add_child(_pause_btn)

func _on_pause_btn_pressed() -> void:
	pause_requested.emit()

func show_pray_button(value: bool) -> void:
	if _mobile_controls:
		_mobile_controls.show_pray_button(value)

func show_pickup_button(value: bool) -> void:
	if _mobile_controls:
		_mobile_controls.show_pickup_button(value)

func _build_mobile_controls() -> void:
	var mc_script: GDScript = preload("res://scripts/ui/MobileControls.gd")
	_mobile_controls = mc_script.new()
	_root.add_child(_mobile_controls)

func _build_sin_bar() -> void:
	# Y position is applied in _apply_safe_area so banner toggles reflow.
	_sin_bar_bg = ColorRect.new()
	_sin_bar_bg.position = Vector2(0, 0)
	_sin_bar_bg.size = Vector2(0, 6)
	_sin_bar_bg.color = Color(0.12, 0.12, 0.12)
	_root.add_child(_sin_bar_bg)

	_sin_bar = ColorRect.new()
	_sin_bar.position = Vector2.ZERO
	_sin_bar.size = Vector2(0, 6)
	_sin_bar.color = Color.WHITE
	_sin_bar_bg.add_child(_sin_bar)

# ── Sin-source toast (S1) ────────────────────────────────────────────────────

func _build_sin_toast_box() -> void:
	# Bottom-left, sitting just above the sin bar / mobile controls.
	# Anchor to BOTTOM_LEFT so it stays put as toasts stack upwards.
	_sin_toast_box = VBoxContainer.new()
	_sin_toast_box.name = "SinToastBox"
	_sin_toast_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_sin_toast_box.offset_left   = 24.0
	_sin_toast_box.offset_top    = -380.0   # above mobile controls + sin bar
	_sin_toast_box.offset_right  = 600.0
	_sin_toast_box.offset_bottom = -200.0
	_sin_toast_box.add_theme_constant_override("separation", 6)
	_sin_toast_box.alignment = BoxContainer.ALIGNMENT_END
	_sin_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_sin_toast_box)

func _on_sin_added(amount: float, cause: String) -> void:
	# Skip zero-deltas (defensive — shouldn't fire but guard anyway).
	if absf(amount) < 0.01:
		return
	# Throttle per-cause so per-frame ticks don't flood the screen.
	# Accumulate the suppressed amount and flush it as one toast when the
	# throttle window passes.
	var now: float = Time.get_ticks_msec() / 1000.0
	var last: float = float(_sin_toast_last_t.get(cause, -999.0))
	if now - last < _SIN_TOAST_THROTTLE_SEC:
		_sin_toast_pending[cause] = float(_sin_toast_pending.get(cause, 0.0)) + amount
		return
	# Emit the new amount + any accumulated leftovers from the silent window.
	var total: float = amount + float(_sin_toast_pending.get(cause, 0.0))
	_sin_toast_pending.erase(cause)
	_sin_toast_last_t[cause] = now
	_spawn_sin_toast(total, cause)

func _spawn_sin_toast(amount: float, cause: String) -> void:
	# Cap visible toasts — drop the oldest before adding a new one.
	while _sin_toast_box.get_child_count() >= _SIN_TOAST_MAX:
		_sin_toast_box.get_child(0).queue_free()

	var icon:  String = String(_SIN_CAUSE_ICONS.get(cause, "❓"))
	# Pull cause label from Loc; fall back to the local UA dict if Loc is
	# missing or doesn't have the key for this cause.
	var label: String = _t(
			"hud.sin_cause." + cause, {},
			String(_SIN_CAUSE_LABELS.get(cause, "Інше")))
	var sign_char: String = "+" if amount >= 0.0 else "−"
	var text: String = _t("hud.sin_toast_format",
			{"sign": sign_char,
			 "amount": "%.0f" % absf(amount),
			 "icon": icon,
			 "label": label},
			"%s%.0f%% гріх  %s %s" % [sign_char, absf(amount), icon, label])

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	# Red for sin gain, green tint for cleansing/confession (negative).
	if amount >= 0.0:
		style.bg_color     = Color(0.10, 0.05, 0.06, 0.88)
		style.border_color = Color("#8B0000")
	else:
		style.bg_color     = Color(0.04, 0.10, 0.06, 0.88)
		style.border_color = Color("#3A8A4A")
	for side in ["left", "right", "top", "bottom"]:
		style.set("border_width_" + side, 2)
	for corner in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		style.set("corner_radius_" + corner, 10)
	style.content_margin_left   = 16.0
	style.content_margin_right  = 16.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color",
		Color("#FFE4D0") if amount >= 0.0 else Color("#D6FFE0"))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	panel.add_child(lbl)

	_sin_toast_box.add_child(panel)
	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, _SIN_TOAST_FADE_IN)
	tw.tween_interval(_SIN_TOAST_HOLD)
	tw.tween_property(panel, "modulate:a", 0.0, _SIN_TOAST_FADE_OUT)
	tw.tween_callback(panel.queue_free)
