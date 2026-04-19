extends Node

# Autoload: GameManager
# Central orchestrator — level loading, death, sin, progression, transitions.

# ── Signals ───────────────────────────────────────────────────────────────────
signal level_started(level_id: int)
signal level_completed(level_id: int, stats: Dictionary)
signal player_died(death_count: int)
signal player_respawned
signal sin_changed(new_value: float)
signal hp_changed(hp: int, max_hp: int)
signal soul_collected_in_level(found: int, total: int)
signal game_over  # reserved for future hard-fail states

# ── Scene paths ───────────────────────────────────────────────────────────────
const SCENE_LEVEL      := "res://scenes/Level.tscn"
const SCENE_BOSS_LEVEL := "res://scenes/BossLevel.tscn"
const SCENE_HUB        := "res://scenes/Hub.tscn"
const SCENE_MAIN_MENU  := "res://MainMenu.tscn"

# ── Death config constants ────────────────────────────────────────────────────
const SIN_ON_DEATH         := 5.0
const SIN_ON_SOFT_EXTRA    := 5.0
const SCREEN_DARKEN_DURATION := 0.6

# ── Death limits per level type ───────────────────────────────────────────────
const DEATH_LIMITS := {
	"vertical":  3,
	"labyrinth": 3,
	"void":      5,
	"escape":    3,
	"boss":      -1,  # unlimited
	"platformer": -1,
}

# ── Runtime state ─────────────────────────────────────────────────────────────
var current_level_id:   int   = 1
var current_circle:     int   = 1

var _hp:           int   = 3
var _max_hp:       int   = 3
var _sin_at_level_start: float = 0.0

var _deaths_this_level:    int  = 0
var _souls_found_this_level: int = 0
var _souls_total_this_level: int = 0
var _level_start_time:     float = 0.0

var _forgiveness_used: bool = false  # once per level
var _is_transitioning: bool = false

# HUD reference (set by level scene after instantiation)
var _hud: Node = null

# ── Ready ─────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_sync_from_save()

func _sync_from_save() -> void:
	if not SaveManager:
		return
	current_level_id = SaveManager.get_current_level()
	current_circle   = SaveManager.get_current_circle()
	_hp    = _base_max_hp()
	_max_hp = _hp

# ── Public API ────────────────────────────────────────────────────────────────

# Called by the level scene once it finishes loading its nodes.
func register_hud(hud: Node) -> void:
	_hud = hud

# Called by Level.gd _ready() to kick off in-level bookkeeping.
func begin_level(level_id: int, souls_total: int) -> void:
	current_level_id = level_id
	current_circle   = ceili(float(level_id) / 10.0)

	_deaths_this_level = 0
	_souls_found_this_level = 0
	_souls_total_this_level = souls_total
	_forgiveness_used = false
	_level_start_time = Time.get_ticks_msec() / 1000.0

	_sin_at_level_start = SaveManager.get_sin() if SaveManager else 0.0
	_max_hp = _base_max_hp()
	_hp     = _max_hp

	if _hud:
		_hud.setup(current_circle, current_level_id, _max_hp, souls_total)

	if SaveManager:
		SaveManager.set_current_level(level_id)
		SaveManager.set_current_circle(current_circle)

	level_started.emit(level_id)

# ── HP / Damage ───────────────────────────────────────────────────────────────

func take_damage(amount: int = 1) -> void:
	if _hp <= 0:
		return

	# Forgiveness upgrade: survive with 1 HP once per level
	if _hp - amount <= 0 and not _forgiveness_used:
		if SaveManager and SaveManager.has_upgrade("forgiveness"):
			_forgiveness_used = true
			_set_hp(1)
			return

	_set_hp(_hp - amount)
	if _hp <= 0:
		trigger_death("enemy_hit")

func instant_death(cause: String = "fall") -> void:
	_set_hp(0)
	trigger_death(cause)

func heal(amount: int = 1) -> void:
	_set_hp(mini(_hp + amount, _max_hp))

# Called by LevelBase when Player emits hp_changed (external HP sync)
func set_hp(hp: int, max_hp: int) -> void:
	_max_hp = max_hp
	_hp     = clampi(hp, 0, _max_hp)
	hp_changed.emit(_hp, _max_hp)
	if _hud:
		_hud.set_hp(_hp, _max_hp)

func _set_hp(value: int) -> void:
	_hp = clampi(value, 0, _max_hp)
	hp_changed.emit(_hp, _max_hp)
	if _hud:
		_hud.set_hp(_hp, _max_hp)

# ── Sin ───────────────────────────────────────────────────────────────────────

func add_sin(amount: float) -> void:
	if not SaveManager:
		return
	SaveManager.add_sin(amount)
	var new_sin: float = SaveManager.get_sin()
	sin_changed.emit(new_sin)
	if _hud:
		_hud.set_sin(new_sin)

func reduce_sin(amount: float) -> void:
	if not SaveManager:
		return
	SaveManager.reduce_sin(amount)
	var new_sin: float = SaveManager.get_sin()
	sin_changed.emit(new_sin)
	if _hud:
		_hud.set_sin(new_sin)

# ── Souls ─────────────────────────────────────────────────────────────────────

func collect_soul(soul_id: int) -> void:
	if SaveManager:
		SaveManager.add_soul(soul_id)
	_souls_found_this_level += 1
	soul_collected_in_level.emit(_souls_found_this_level, _souls_total_this_level)
	if _hud:
		_hud.add_soul_found()
		_hud.set_total_souls(SaveManager.get_total_souls() if SaveManager else 0)

func collect_hidden_soul(soul_id: String) -> void:
	if SaveManager:
		SaveManager.add_hidden_soul(soul_id)
	if _hud:
		_hud.set_total_souls(SaveManager.get_total_souls() if SaveManager else 0)

# ── Death ─────────────────────────────────────────────────────────────────────

func trigger_death(cause: String = "enemy_hit") -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	_deaths_this_level += 1
	add_sin(SIN_ON_DEATH)
	player_died.emit(_deaths_this_level)

	# Darken screen then respawn
	var tree := get_tree()
	if tree:
		var overlay := _make_overlay()
		overlay.color = Color(0.55, 0.0, 0.0)
		tree.root.add_child(overlay)
		var tw := create_tween()
		tw.tween_property(overlay, "modulate:a", 0.6, 0.12)
		tw.tween_property(overlay, "modulate:a", 0.0, 0.10)
		tw.tween_callback(func() -> void: overlay.color = Color.BLACK)
		tw.tween_property(overlay, "modulate:a", 1.0, SCREEN_DARKEN_DURATION - 0.22)
		tw.tween_callback(func() -> void:
			_do_respawn(overlay)
		)

func _do_respawn(overlay: ColorRect) -> void:
	_check_death_limit()
	_set_hp(_max_hp)

	# Fade back in
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 0.0, SCREEN_DARKEN_DURATION * 0.7)
	tw.tween_callback(overlay.queue_free)

	_is_transitioning = false
	player_respawned.emit()

func _check_death_limit() -> void:
	var level_type: String = LevelConfig.get_level_type(current_level_id) if LevelConfig else "platformer"
	var limit: int = DEATH_LIMITS.get(level_type, -1)
	if limit < 0:
		return  # unlimited
	if _deaths_this_level >= limit:
		# Soft limit: +1 extra attempt for +5% sin
		add_sin(SIN_ON_SOFT_EXTRA)

# ── Level complete ────────────────────────────────────────────────────────────

# Called by Level.gd when exit is reached and all required souls are collected.
func complete_level() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _level_start_time
	var sin_now: float = SaveManager.get_sin() if SaveManager else 0.0
	var sin_delta: float = sin_now - _sin_at_level_start
	var light_earned: int = _calc_light(_souls_found_this_level, _souls_total_this_level, _deaths_this_level)

	if SaveManager:
		SaveManager.add_light(light_earned)
		SaveManager.set_current_level(current_level_id + 1)
		SaveManager.save_after_level()

	var stats := {
		"level_id":    current_level_id,
		"circle":      current_circle,
		"souls_found": _souls_found_this_level,
		"souls_total": _souls_total_this_level,
		"deaths":      _deaths_this_level,
		"sin_delta":   sin_delta,
		"sin_total":   sin_now,
		"light_earned": light_earned,
		"time_seconds": elapsed,
		"stars":        _calc_stars(_souls_found_this_level, _souls_total_this_level, _deaths_this_level),
	}

	level_completed.emit(current_level_id, stats)

	# Show interstitial ad between levels
	if AdsManager and AdsManager.has_method("show_interstitial"):
		AdsManager.show_interstitial()

# ── Scene transitions ─────────────────────────────────────────────────────────

func load_next_level() -> void:
	_is_transitioning = false
	var next_id: int = current_level_id + 1
	if next_id > 100:
		load_main_menu()
		return
	_change_scene_to_level(next_id)

func restart_level() -> void:
	_is_transitioning = false
	_change_scene_to_level(current_level_id)

func load_hub() -> void:
	_is_transitioning = false
	get_tree().change_scene_to_file(SCENE_HUB)

func load_main_menu() -> void:
	_is_transitioning = false
	get_tree().change_scene_to_file(SCENE_MAIN_MENU)

func _change_scene_to_level(level_id: int) -> void:
	# Set current_level_id BEFORE scene change so LevelBase._ready() can read it.
	# LevelBase uses GameManager.current_level_id when its own export is default (1).
	current_level_id = level_id
	var level_type: String = LevelConfig.get_level_type(level_id) if LevelConfig else "platformer"
	var scene_path: String = SCENE_BOSS_LEVEL if level_type == "boss" else SCENE_LEVEL
	get_tree().change_scene_to_file(scene_path)

# ── Bonus / Ability tracking ──────────────────────────────────────────────────

func activate_bonus(bonus_id: String, icon: String, duration: float) -> void:
	if _hud:
		_hud.start_bonus(bonus_id, icon, duration)

func use_ability(upgrade_id: String) -> void:
	if _hud:
		_hud.use_ability(upgrade_id)

func start_escape_timer(duration: float) -> void:
	if _hud:
		_hud.start_escape_timer(duration)

# ── Helpers ───────────────────────────────────────────────────────────────────

func _base_max_hp() -> int:
	var base := 3
	if SaveManager:
		base += SaveManager.get_upgrade_level("vitality")   # vitality: up to +3 (max 6 HP)
	return clampi(base, 1, 6)

func _calc_stars(found: int, total: int, deaths: int) -> int:
	var all_souls := found >= total
	if all_souls and deaths == 0:
		return 3
	if all_souls and deaths <= 2:
		return 2
	return 1

func _calc_light(found: int, total: int, deaths: int) -> int:
	var base := 10
	if found >= total:
		base += 5
	base -= deaths * 2
	return maxi(base, 1)

func _make_overlay() -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.modulate.a = 0.0
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.z_index = 100
	return rect
