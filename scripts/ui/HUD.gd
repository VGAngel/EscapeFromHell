extends CanvasLayer

# Attach to a CanvasLayer node (layer = 1) inside the level scene.
# Call setup() once after level loads, then use the public API during play.

# ── Signals ───────────────────────────────────────────────────────────────────
signal pause_requested

# ── Constants ─────────────────────────────────────────────────────────────────
const MAX_HEARTS      := 6
const LEVEL_INFO_TIME := 3.0
const AD_BANNER_H     := 60  # px reserved at bottom for ad banner

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

# Sin bar
var _sin_bar:      ColorRect        = null
var _sin_bar_bg:   ColorRect        = null

# Escape timer bar (escape levels only)
var _escape_bar:   ColorRect        = null
var _escape_bg:    ColorRect        = null

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

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_ui()

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

	_level_label.text = "Коло %d • Рівень %d" % [circle, level]
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
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(icon_lbl)

	var timer_lbl: Label = null
	if duration > 0.0:
		timer_lbl = Label.new()
		timer_lbl.text = "%.0f" % duration
		timer_lbl.add_theme_font_size_override("font_size", 11)
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
		lbl.add_theme_font_size_override("font_size", 22)
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
	_escape_bar.size = Vector2(720, 8)
	_escape_bar.color = Color("#00FF88")
	_escape_bar.visible = false
	_escape_bg.add_child(_escape_bar)

func _build_top_row() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("separation", 0)
	top.offset_left   =  8.0
	top.offset_right  = -8.0
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
		h.add_theme_font_size_override("font_size", 18)
		h.add_theme_color_override("font_color", Color("#FF6666"))
		_hearts.add_child(h)

	# Level info (center)
	_level_label = Label.new()
	_level_label.text = ""
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.add_theme_font_size_override("font_size", 14)
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
	_souls_total.add_theme_font_size_override("font_size", 14)
	right_col.add_child(_souls_total)

	_light_label = Label.new()
	_light_label.text = "💡 0"
	_light_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_light_label.add_theme_font_size_override("font_size", 13)
	_light_label.add_theme_color_override("font_color", Color("#FFD060"))
	right_col.add_child(_light_label)

	# Play timer (centered under level label, fades in after level info fades out)
	_timer_label = Label.new()
	_timer_label.text = "00:00"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", 14)
	_timer_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75, 0.85))
	_timer_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_timer_label.offset_top    = 46.0
	_timer_label.offset_bottom = 66.0
	_timer_label.modulate.a = 0.0
	_root.add_child(_timer_label)

func _build_bottom_row() -> void:
	var bottom_y: float = 1280 - AD_BANNER_H - 6 - 36 - 8  # above sin bar + ad banner

	var bottom := HBoxContainer.new()
	bottom.position = Vector2(8, bottom_y)
	bottom.size = Vector2(704, 36)
	bottom.add_theme_constant_override("separation", 6)
	_root.add_child(bottom)

	# Ability slots (left)
	_ability_row = HBoxContainer.new()
	_ability_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_row.add_theme_constant_override("separation", 4)
	bottom.add_child(_ability_row)

	# Active bonuses (center)
	_bonus_row = HBoxContainer.new()
	_bonus_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bonus_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bonus_row.add_theme_constant_override("separation", 4)
	bottom.add_child(_bonus_row)

	# Level souls counter (right)
	_souls_level = Label.new()
	_souls_level.text = "👻 0 / 0"
	_souls_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_souls_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_souls_level.add_theme_font_size_override("font_size", 14)
	bottom.add_child(_souls_level)

func _build_sin_bar() -> void:
	var bar_y: float = 1280 - AD_BANNER_H - 6

	_sin_bar_bg = ColorRect.new()
	_sin_bar_bg.position = Vector2(0, bar_y)
	_sin_bar_bg.size = Vector2(720, 6)
	_sin_bar_bg.color = Color(0.12, 0.12, 0.12)
	_root.add_child(_sin_bar_bg)

	_sin_bar = ColorRect.new()
	_sin_bar.position = Vector2.ZERO
	_sin_bar.size = Vector2(0, 6)
	_sin_bar.color = Color.WHITE
	_sin_bar_bg.add_child(_sin_bar)
