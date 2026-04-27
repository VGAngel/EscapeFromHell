extends CharacterBody2D

# ── Signals ───────────────────────────────────────────────────────────────────
signal boss_stunned(duration: float)
signal boss_stun_ended
signal phase_changed(phase_index: int)
signal win_condition_met
signal sin_aura_tick(amount: float)

# ── State ─────────────────────────────────────────────────────────────────────
enum BossState { IDLE, PATROL, CHASE, CHARGE_TELEGRAPH, CHARGING, STUNNED, PHASE_TRANSITION }

var state: BossState = BossState.IDLE

# ── Config ────────────────────────────────────────────────────────────────────
const CONFIG_PATH := "res://bosses_config.json"
@export var boss_id: String = "boss_01"

var _cfg:      Dictionary = {}
var _stats:    Dictionary = {}
var _mechanic: Dictionary = {}

# ── Runtime stats ─────────────────────────────────────────────────────────────
var move_speed:      float = 60.0
var detection_range: float = 300.0
var chase_duration:  float = 999.0

# ── Timers ────────────────────────────────────────────────────────────────────
var _stun_timer:          float = 0.0
var _charge_telegraph:    float = 0.0
var _charge_timer:        float = 0.0
var _charge_cooldown:     float = 0.0
var _wind_gust_timer:     float = 0.0
var _copies_respawn_timer: float = 0.0
var _sin_aura_tick_timer: float = 0.0

# ── Phase ─────────────────────────────────────────────────────────────────────
var _current_phase:    int = 0
var _phase_cfg: Array  = []

# ── Mechanic state ────────────────────────────────────────────────────────────
var _collectibles_total:    int = 0
var _collectibles_collected: int = 0
var _totems_activated:      int = 0
var _next_totem_index:      int = 0
var _copies:           Array  = []
var _is_real_boss:     bool   = true
var _charge_dir:       float  = 1.0
var _prayer_progress:  float  = 0.0

# ── References ────────────────────────────────────────────────────────────────
var _player: CharacterBody2D = null
var _arena_objects:    Array  = []  # fragments / totems / crystals / souls

const GRAVITY: float = 900.0
const BOSS_STUN_DURATION := 6.0

# ── Child nodes ───────────────────────────────────────────────────────────────
@onready var _anim:   AnimationPlayer = $AnimationPlayer
@onready var _sprite: Sprite2D        = $Sprite2D

# Created at runtime by _load_sprite_frames_from_map() when the sprite map
# has animation folders for this boss. When non-null, drives all visuals
# and _sprite is hidden.
var _anim_sprite: AnimatedSprite2D = null

# ── Init ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_config()
	_find_player()
	add_to_group("boss")
	_start_phase(0)
	# Try real chibi sprites first; fall back to flat-colour placeholder.
	if not _load_sprite_frames_from_map(boss_id):
		_make_placeholder_sprite_from_config()

## Generate a solid-colour placeholder from bosses_config.json visual section.
## Subclasses that load real SpriteFrames should override or no-op this.
func _make_placeholder_sprite_from_config() -> void:
	if not _sprite:
		return
	if _sprite.texture != null:
		return   # respect any texture already set on the scene
	var visual: Dictionary = _cfg.get("visual", {})
	var col := Color(visual.get("placeholder_color", "#AA3300")) as Color
	var size_arr: Variant = visual.get("size", [64, 96])
	var w: int = 64
	var h: int = 96
	if size_arr is Array and (size_arr as Array).size() == 2:
		w = int((size_arr as Array)[0])
		h = int((size_arr as Array)[1])
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(col)
	_sprite.texture = ImageTexture.create_from_image(img)

func _load_config() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if not file:
		push_error("BossAI: bosses_config.json not found")
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("BossAI: failed to parse bosses_config.json")
		return
	var data: Dictionary = json.get_data()
	for boss in data.get("bosses", []):
		if boss.get("id") == boss_id:
			_cfg = boss
			break
	if _cfg.is_empty():
		push_error("BossAI: boss_id '%s' not found" % boss_id)
		return

	_stats    = _cfg.get("stats", {})
	_mechanic = _cfg.get("mechanic", {})
	_phase_cfg = _cfg.get("phases", [])

	move_speed      = float(_stats.get("move_speed", 60))
	detection_range = float(_stats.get("detection_range", 300))
	chase_duration  = float(_stats.get("chase_duration", 999))

func _find_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody2D

# ── Register arena objects (called by arena scene) ───────────────────────────
# Викликати з арени: boss.register_arena_objects(get_children_in_group("collectible"))
func register_arena_objects(objects: Array) -> void:
	_arena_objects = objects
	_collectibles_total = objects.size()

# ── Main loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not _is_real_boss:
		_do_copy_behavior(delta)
		return

	_tick_timers(delta)
	_tick_sin_aura(delta)

	if not _player:
		_find_player()
		return

	match state:
		BossState.IDLE:             _do_idle()
		BossState.PATROL:           _do_patrol(delta)
		BossState.CHASE:            _do_chase(delta)
		BossState.CHARGE_TELEGRAPH: _do_charge_telegraph(delta)
		BossState.CHARGING:         _do_charging(delta)
		BossState.STUNNED:          _do_stunned(delta)
		BossState.PHASE_TRANSITION: pass

	_apply_gravity(delta)
	move_and_slide()
	_update_facing()
	_update_animation()
	_check_wall_stun()

# ── Gravity ───────────────────────────────────────────────────────────────────
func _apply_gravity(delta: float) -> void:
	if _stats.get("flight", false):
		velocity.y = move_toward(velocity.y, 0.0, GRAVITY * delta)
		return
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	else:
		velocity.y = 0.0

# ── Timers ────────────────────────────────────────────────────────────────────
func _tick_timers(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			_on_stun_ended()

	if _charge_cooldown > 0.0:
		_charge_cooldown -= delta

	if _charge_telegraph > 0.0:
		_charge_telegraph -= delta
		if _charge_telegraph <= 0.0 and state == BossState.CHARGE_TELEGRAPH:
			_start_charge()

	# _charge_timer is decremented inside _do_charging() directly

	if _wind_gust_timer > 0.0:
		_wind_gust_timer -= delta
		if _wind_gust_timer <= 0.0:
			_do_wind_gust()

	if _copies_respawn_timer > 0.0:
		_copies_respawn_timer -= delta
		if _copies_respawn_timer <= 0.0:
			_respawn_copies()

# ── Sin aura (Люцифер фаза 2) ─────────────────────────────────────────────────
func _tick_sin_aura(delta: float) -> void:
	var phase_data := _get_current_phase_data()
	var aura: Dictionary = phase_data.get("sin_aura", {})
	if aura.is_empty() or not _player:
		return
	var radius: float = float(aura.get("radius", 250))
	if global_position.distance_to(_player.global_position) > radius:
		return
	_sin_aura_tick_timer += delta
	if _sin_aura_tick_timer >= 1.0:
		_sin_aura_tick_timer = 0.0
		var amount: float = float(aura.get("sin_per_second", 3))
		# BossLevel._on_sin_aura_tick → GameManager.add_sin already routes the
		# tick through the canonical sin pipeline (which also notifies HUD).
		# A second direct SaveManager.add_sin here would double-count it.
		sin_aura_tick.emit(amount)

# ── IDLE ──────────────────────────────────────────────────────────────────────
func _do_idle() -> void:
	velocity.x = 0.0
	var phase_data := _get_current_phase_data()
	var behavior: String = phase_data.get("behavior", _cfg.get("behavior", "chase"))
	if behavior == "stationary_observer" or behavior == "stationary_final":
		return
	if _player and global_position.distance_to(_player.global_position) <= detection_range:
		state = BossState.CHASE

# ── PATROL ────────────────────────────────────────────────────────────────────
var _patrol_dir: float = 1.0

func _do_patrol(_delta: float) -> void:
	var phase_data := _get_current_phase_data()
	var behavior: String = phase_data.get("behavior", "")
	if behavior == "slow_patrol":
		velocity.x = move_speed * 0.4 * _patrol_dir
	else:
		velocity.x = move_speed * _patrol_dir
	if is_on_wall():
		_patrol_dir *= -1.0

# ── CHASE ─────────────────────────────────────────────────────────────────────
func _do_chase(_delta: float) -> void:
	if not _player:
		state = BossState.PATROL
		return

	var mechanic_type: String = _mechanic.get("type", "")

	# boss_05: charge mechanic
	if mechanic_type == "dodge_and_collect" and _charge_cooldown <= 0.0:
		_begin_charge_telegraph()
		return

	var dir: float = sign(_player.global_position.x - global_position.x)
	velocity.x = move_speed * dir

	if _stats.get("flight", false):
		var vdir: float = sign(_player.global_position.y - global_position.y)
		velocity.y = move_speed * 0.7 * vdir
		_do_wind_gust_check()

# ── CHARGE (boss_05) ──────────────────────────────────────────────────────────
func _begin_charge_telegraph() -> void:
	state = BossState.CHARGE_TELEGRAPH
	velocity.x = 0.0
	var cfg: Dictionary = _mechanic.get("charge_cycle", {})
	_charge_telegraph = float(cfg.get("telegraph_duration", 1.2))
	_charge_dir = sign(_player.global_position.x - global_position.x) if _player else 1.0

func _do_charge_telegraph(_delta: float) -> void:
	velocity.x = 0.0

func _start_charge() -> void:
	state = BossState.CHARGING
	var cfg: Dictionary = _mechanic.get("charge_cycle", {})
	_charge_timer = float(cfg.get("charge_duration", 0.8))
	velocity.x = float(_stats.get("charge_speed", 450)) * _charge_dir

func _do_charging(delta: float) -> void:
	_charge_timer -= delta
	if _charge_timer <= 0.0:
		var cfg: Dictionary = _mechanic.get("charge_cycle", {})
		_charge_cooldown = float(cfg.get("cooldown_after_charge", 2.5))
		state = BossState.CHASE

func _check_wall_stun() -> void:
	if state != BossState.CHARGING:
		return
	if is_on_wall():
		var cfg: Dictionary = _mechanic.get("charge_cycle", {})
		var stun: float = float(cfg.get("wall_stun_duration", 4.0))
		receive_knockback(Vector2.ZERO, stun)

# ── WIND GUST (boss_02) ───────────────────────────────────────────────────────
func _do_wind_gust_check() -> void:
	if _wind_gust_timer > 0.0:
		return
	var hazard: Dictionary = _mechanic.get("wind_hazard", {})
	if not hazard.get("enabled", false):
		return
	_wind_gust_timer = float(hazard.get("gusts_interval", 4.0))

func _do_wind_gust() -> void:
	if not _player:
		return
	var hazard: Dictionary = _mechanic.get("wind_hazard", {})
	var force: float = float(hazard.get("push_force", 200))
	var dir: Vector2 = (_player.global_position - global_position).normalized()
	_player.velocity += dir * force
	_wind_gust_timer = float(hazard.get("gusts_interval", 4.0))

# ── STUNNED ───────────────────────────────────────────────────────────────────
func _do_stunned(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 800.0 * delta)

func _on_stun_ended() -> void:
	state = BossState.CHASE
	boss_stun_ended.emit()
	# boss_07: копії зникають коли оглушено справжнього
	if _mechanic.get("type") == "identify_and_evade":
		_destroy_copies()
		var respawn_delay: float = float(_mechanic.get("copies_respawn", {}).get("delay", 10.0))
		_copies_respawn_timer = respawn_delay

# ── Receive knockback (staff hit) ─────────────────────────────────────────────
func receive_knockback(direction: Vector2, stun_duration: float = BOSS_STUN_DURATION) -> void:
	if state == BossState.STUNNED:
		return
	state = BossState.STUNNED
	_stun_timer = stun_duration
	if direction != Vector2.ZERO:
		velocity = direction
	boss_stunned.emit(stun_duration)

# ── Phases (Люцифер boss_10) ──────────────────────────────────────────────────
func _start_phase(index: int) -> void:
	if index >= _phase_cfg.size() and _phase_cfg.size() > 0:
		return
	_current_phase = index
	var phase_data := _get_current_phase_data()
	var behavior: String = phase_data.get("behavior", "chase")
	match behavior:
		"stationary_observer", "stationary_final":
			state = BossState.IDLE
		"slow_patrol":
			state = BossState.PATROL
		_:
			state = BossState.CHASE
	phase_changed.emit(index)

func _get_current_phase_data() -> Dictionary:
	if _phase_cfg.is_empty():
		return {}
	if _current_phase < _phase_cfg.size():
		return _phase_cfg[_current_phase]
	return {}

# Викликати з арени коли зібрані N душ (Люцифер)
func advance_phase() -> void:
	_start_phase(_current_phase + 1)

# ── Collectible tracking ──────────────────────────────────────────────────────
# Викликати з арени коли гравець підбирає уламок/кристал/душу
func on_collectible_picked() -> void:
	_collectibles_collected += 1
	_check_win_condition()

	# Люцифер: 3 зібраних → фаза 2 (slow_patrol + sin_aura),
	#          5 зібраних → фаза 3 (stationary_final + prayer_ritual).
	if boss_id == "boss_10":
		if _collectibles_collected == 3:
			advance_phase()
		elif _collectibles_collected == 5:
			advance_phase()

# Викликати з арени коли гравець активував тотем (boss_02)
func on_totem_activated(totem_index: int) -> void:
	if totem_index != _next_totem_index:
		return
	_totems_activated += 1
	_next_totem_index += 1
	_check_win_condition()

# ── Win condition ─────────────────────────────────────────────────────────────
func _check_win_condition() -> void:
	var mechanic_type: String = _mechanic.get("type", "")
	match mechanic_type:
		"collect_and_escape", "lure_into_trap", "dodge_and_collect":
			if _collectibles_collected >= _collectibles_total:
				win_condition_met.emit()
		"activate_in_sequence":
			var count: int = _mechanic.get("totems", {}).get("count", 3)
			if _totems_activated >= count:
				win_condition_met.emit()
		"identify_and_evade":
			pass  # перемога коли оглушено і вийшли — відстежує арена
		"prayer_ritual":
			pass  # відстежує _tick_prayer

# Викликати з арени коли гравець досяг виходу
func on_player_reached_exit() -> void:
	var mechanic_type: String = _mechanic.get("type", "")
	if mechanic_type in ["collect_and_escape", "lure_into_trap", "dodge_and_collect"]:
		if _collectibles_collected >= _collectibles_total:
			win_condition_met.emit()
	elif mechanic_type == "identify_and_evade":
		if state == BossState.STUNNED:
			win_condition_met.emit()

# ── Prayer ritual (boss_10 фаза 3) ────────────────────────────────────────────
# Викликати кожен кадр коли гравець утримує кнопку молитви в центрі арени
func tick_prayer(delta: float) -> void:
	var phase_data := _get_current_phase_data()
	if phase_data.get("mechanic", {}).get("type") != "prayer_ritual":
		return
	var required: float = float(phase_data.get("mechanic", {}).get("hold_duration", 8.0))
	_prayer_progress += delta
	if _prayer_progress >= required:
		win_condition_met.emit()

func reset_prayer() -> void:
	_prayer_progress = 0.0

# ── Copies (boss_07) ──────────────────────────────────────────────────────────
func spawn_copies(copy_scene: PackedScene, count: int = 3) -> void:
	_destroy_copies()
	for i in count:
		var copy: Node = copy_scene.instantiate()
		get_parent().add_child(copy)
		copy.global_position = global_position + Vector2(randf_range(-200, 200), 0)
		if copy.has_method("setup_as_copy"):
			copy.setup_as_copy(self)
		_copies.append(copy)

func setup_as_copy(_original: Node) -> void:
	_is_real_boss = false
	modulate = Color(0.85, 0.85, 0.85, 0.9)
	# Stay out of the "boss" lookup group so _get_boss() can't return a copy
	# if tree order ever shifts. Copies still respond to staff via collision
	# layer, just not via group_first lookups that drive win conditions.
	if is_in_group("boss"):
		remove_from_group("boss")

func _do_copy_behavior(delta: float) -> void:
	if not _player:
		return
	var dir: float = sign(_player.global_position.x - global_position.x)
	velocity.x = move_speed * dir * 0.8
	_apply_gravity(delta)
	move_and_slide()
	_update_facing()

func _destroy_copies() -> void:
	for copy in _copies:
		if is_instance_valid(copy):
			copy.queue_free()
	_copies.clear()

func _respawn_copies() -> void:
	pass  # арена відповідає за спавн копій

# ── Totem proximity block (boss_02) ───────────────────────────────────────────
func is_blocking_totem(totem_position: Vector2) -> bool:
	var block_range: float = float(_mechanic.get("totems", {}).get("blocked_when_boss_within", 120))
	return global_position.distance_to(totem_position) <= block_range

# ── Facing & animation ────────────────────────────────────────────────────────
func _update_facing() -> void:
	var face_right: bool
	if velocity.x > 10.0:
		face_right = true
	elif velocity.x < -10.0:
		face_right = false
	else:
		return
	if _anim_sprite:
		_anim_sprite.flip_h = not face_right
	if _sprite:
		_sprite.flip_h = not face_right

var _missing_anims_logged: Dictionary = {}

func _update_animation() -> void:
	var anim := _get_anim_name()

	# Prefer AnimatedSprite2D loaded from enemy_sprite_map.json.
	if _anim_sprite and _anim_sprite.sprite_frames \
			and _anim_sprite.sprite_frames.has_animation(anim):
		if _anim_sprite.animation != anim:
			_anim_sprite.play(anim)
		return

	# Fall back to AnimationPlayer (hand-authored clips, if present).
	if not _anim:
		return
	if not _anim.has_animation(anim):
		# Boss animations are still a todo (doc/animations.md). Log each
		# missing clip exactly once per instance so the issue stays
		# visible without spamming every physics tick.
		if not _missing_anims_logged.has(anim):
			_missing_anims_logged[anim] = true
			push_error("BossAI[%s]: missing animation '%s'" % [boss_id, anim])
		return
	if _anim.current_animation != anim:
		_anim.play(anim)

func _get_anim_name() -> String:
	match state:
		BossState.IDLE:             return "boss_idle"
		BossState.PATROL:           return "boss_walk"
		BossState.CHASE:            return "boss_walk"
		BossState.CHARGE_TELEGRAPH: return "boss_charge_telegraph"
		BossState.CHARGING:         return "boss_charge"
		BossState.STUNNED:          return "boss_stun"
		BossState.PHASE_TRANSITION: return "boss_idle"
	return "boss_idle"

# ── Sprite loading ────────────────────────────────────────────────────────────

const SPRITE_MAP_PATH: String = "res://enemy_sprite_map.json"
const BOSS_SPRITE_SCALE: float = 0.18    # chibi canvases ~900×900 → ~162 px tall
const BOSS_SPRITE_FEET_PX: float = 54.0  # 300 (canvas feet offset) × scale

## Build a SpriteFrames from PNG sequences referenced in enemy_sprite_map.json
## under "bosses" → <id>. Returns true if at least one animation was loaded
## and an AnimatedSprite2D was attached.
func _load_sprite_frames_from_map(id: String) -> bool:
	var map_file := FileAccess.open(SPRITE_MAP_PATH, FileAccess.READ)
	if not map_file:
		return false
	var map: Variant = JSON.parse_string(map_file.get_as_text())
	map_file.close()
	if not (map is Dictionary):
		return false

	var base_path:    String = map.get("base_path", "res://Assets/enemies/")
	var anim_subpath: String = map.get("anim_subpath", "PNG/PNG Sequences/")
	var entry: Dictionary = map.get("bosses", {}).get(id, {})
	if entry.is_empty():
		return false

	var pack:      String     = entry.get("pack", "")
	var character: String     = entry.get("character", "")
	var anims:     Dictionary = entry.get("animations", {})
	if pack == "" or character == "" or anims.is_empty():
		return false

	var sf := SpriteFrames.new()
	var any_loaded := false
	for anim_name in anims.keys():
		var folder: String = anims[anim_name]
		var full_path: String = "%s%s/%s/%s%s/" % [base_path, pack, character, anim_subpath, folder]
		var frames: Array = _collect_frames_in_dir(full_path)
		if frames.is_empty():
			continue
		sf.add_animation(anim_name)
		sf.set_animation_loop(anim_name, anim_name not in ["boss_charge"])
		sf.set_animation_speed(anim_name, 12.0)
		for tex in frames:
			sf.add_frame(anim_name, tex)
		any_loaded = true

	if not any_loaded:
		return false

	_anim_sprite = AnimatedSprite2D.new()
	_anim_sprite.sprite_frames = sf
	_anim_sprite.scale = Vector2(BOSS_SPRITE_SCALE, BOSS_SPRITE_SCALE)
	# Align sprite feet to the bottom of the collision rectangle.
	var col: CollisionShape2D = get_node_or_null("CollisionShape2D")
	if col and col.shape is RectangleShape2D:
		var half_h: float = (col.shape as RectangleShape2D).size.y / 2.0
		_anim_sprite.position.y = half_h - BOSS_SPRITE_FEET_PX
	add_child(_anim_sprite)

	# Hide the placeholder Sprite2D so it doesn't double-up with the new visuals.
	if _sprite:
		_sprite.visible = false
	return true

func _collect_frames_in_dir(path: String) -> Array:
	var frames: Array = []
	var dir := DirAccess.open(path)
	if not dir:
		return frames
	# Exported builds list .png.import / .png.remap markers instead of raw .png.
	# Accept both, strip the suffix, and dedupe — load() resolves to .ctex anyway.
	var seen := {}
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and not fname.begins_with("."):
			var canonical: String = ""
			if fname.ends_with(".png"):
				canonical = fname
			elif fname.ends_with(".png.import"):
				canonical = fname.substr(0, fname.length() - 7)
			elif fname.ends_with(".png.remap"):
				canonical = fname.substr(0, fname.length() - 6)
			if canonical != "" and not seen.has(canonical):
				seen[canonical] = true
		fname = dir.get_next()
	dir.list_dir_end()
	var files: Array = seen.keys()
	files.sort()
	for f in files:
		var tex: Texture2D = load(path + f) as Texture2D
		if tex:
			frames.append(tex)
	return frames
