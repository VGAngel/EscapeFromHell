extends "res://scripts/levels/LevelBase.gd"

# Boss level controller — attach to the root of BossLevel.tscn.
# Always static (no procedural generation).
# Win condition: BossAI.win_condition_met signal, NOT soul collection.
# Souls in the arena are optional bonus light.
#
# Expected scene structure (same as LevelBase + boss additions):
#   BossLevel (Node2D) ← this script
#   ├── HUD          (CanvasLayer)
#   ├── RoomContainer (Node2D)   ← the arena room
#   ├── SpawnPoint   (Marker2D)
#   ├── Exit         (Area2D)   ← locked until boss defeated
#   └── Camera2D

# ── Constants ─────────────────────────────────────────────────────────────────
const INTRO_HOLD_SECONDS  := 2.8
const AUTO_COMPLETE_DELAY := 5.0   # auto-complete if player doesn't walk to exit

# Boss name per boss_id — shown during the intro sequence
const BOSS_NAMES := {
	"boss_01": "Воротар",
	"boss_02": "Вітрогін",
	"boss_03": "Тюремник",
	"boss_04": "Жнець",
	"boss_05": "Бегемот",
	"boss_06": "Хранитель Болот",
	"boss_07": "Дзеркальник",
	"boss_08": "Катюга",
	"boss_09": "Крижаний Суддя",
	"boss_10": "Люцифер",
}

# Phase flavor shown briefly on phase transition
const PHASE_LABELS := [
	"",                            # phase 0 — no label
	"— Друга форма —",
	"— Остання форма —",
]

# ── State ─────────────────────────────────────────────────────────────────────
var _boss:          Node  = null
var _boss_defeated: bool  = false
var _prayer_held:   bool  = false
var _current_phase: int   = 0

# ── UI refs ───────────────────────────────────────────────────────────────────
var _intro_layer:   CanvasLayer = null
var _notify_layer:  CanvasLayer = null
var _notify_label:  Label       = null
var _phase_dots:    Array       = []   # Array[ColorRect]
var _phase_panel:   Control     = null

# Progress bar — filled as the boss's objective advances
# (collectibles / totems / prayer time). Driven by BossAI.progress_updated.
var _progress_bar_bg: ColorRect = null
var _progress_bar_fg: ColorRect = null
var _progress_label:  Label     = null
var _progress_value:  Label     = null
const _PROGRESS_BAR_W: float    = 360.0
const _PROGRESS_BAR_H: float    = 14.0

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	super()   # LevelBase._ready(): spawns player, connects exit/souls, begins level

	_souls_required = 0   # souls are bonus; win condition comes from boss

	_boss = _get_boss()
	if _boss:
		_connect_boss_signals()
		_register_arena_objects()

	_build_notify_layer()
	_build_boss_intro()

# Called from LevelBase._ready() BEFORE the player spawns, so arena walls
# and boss are in place when move_and_slide starts.
func _init_static_level() -> void:
	if not _get_boss():
		_build_procedural_arena()
	super()   # _discover_souls — picks up any souls we placed

# ── Procedural arena ──────────────────────────────────────────────────────────

func _build_procedural_arena() -> void:
	match level_id:
		10:
			_build_arena_boss_01()
		20:
			_build_arena_boss_02()
		30:
			_build_arena_boss_03()
		50:
			_build_arena_boss_05()
		70:
			_build_arena_boss_07()
		100:
			_build_arena_boss_10()
		# Levels 40/60/80/90 are flagged as "boss" in levels_config but their
		# unique scenes/configs aren't authored yet. Fall back to the closest
		# existing boss arena so the level is at least playable instead of
		# softlocking on an empty stage with no exit unlock.
		40:
			_build_arena_boss_03()
		60:
			_build_arena_boss_05()
		80:
			_build_arena_boss_07()
		90:
			_build_arena_boss_10()
		_:
			pass  # other bosses fall back to hand-made scene when authored

func _build_arena_boss_01() -> void:
	const W: float = 1600.0
	const H: float = 540.0
	const WALL_T: float = 32.0

	# Room root (kept separate so _room_container holds a tidy single child)
	var room := Node2D.new()
	room.name = "Arena_Boss01"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)

	# Walls (floor / ceiling / left / right)
	_add_static_rect(room, Vector2(W * 0.5, H - WALL_T * 0.5), Vector2(W, WALL_T))
	_add_static_rect(room, Vector2(W * 0.5, WALL_T * 0.5),     Vector2(W, WALL_T))
	_add_static_rect(room, Vector2(WALL_T * 0.5, H * 0.5),     Vector2(WALL_T, H))
	_add_static_rect(room, Vector2(W - WALL_T * 0.5, H * 0.5), Vector2(WALL_T, H))

	# Three mid-platforms for vertical variety
	_add_static_rect(room, Vector2(380.0, 360.0),  Vector2(220.0, WALL_T))
	_add_static_rect(room, Vector2(800.0, 260.0),  Vector2(220.0, WALL_T))
	_add_static_rect(room, Vector2(1220.0, 360.0), Vector2(220.0, WALL_T))

	# Spawn / exit positions for this arena
	_spawn_point.position = Vector2(90.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 80.0)

	# Boss (mid-arena)
	var boss_scene := load("res://scenes/enemies/BossCircle1.tscn") as PackedScene
	if boss_scene:
		var boss_node := boss_scene.instantiate() as Node2D
		boss_node.position = Vector2(W * 0.5, H - WALL_T - 60.0)
		room.add_child(boss_node)

	# Three key fragments scattered at distinct heights
	var frag_scene := load("res://scenes/enemies/KeyFragment.tscn") as PackedScene
	if frag_scene:
		var positions: Array = [
			Vector2(380.0,  330.0),   # on first platform
			Vector2(800.0,  230.0),   # on middle platform
			Vector2(1220.0, 330.0),   # on third platform
		]
		for i in positions.size():
			var frag := frag_scene.instantiate() as Node2D
			frag.position = positions[i]
			if frag.has_method("set"):
				frag.set("fragment_index", i)
			room.add_child(frag)

func _add_static_rect(parent: Node, pos: Vector2, sz: Vector2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.position = pos
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = sz
	cs.shape = rect
	body.add_child(cs)
	parent.add_child(body)

# ── Arena helpers ─────────────────────────────────────────────────────────────

func _add_arena_walls(room: Node, w: float, h: float, wall_t: float) -> void:
	_add_static_rect(room, Vector2(w * 0.5, h - wall_t * 0.5), Vector2(w, wall_t))
	_add_static_rect(room, Vector2(w * 0.5, wall_t * 0.5),     Vector2(w, wall_t))
	_add_static_rect(room, Vector2(wall_t * 0.5, h * 0.5),     Vector2(wall_t, h))
	_add_static_rect(room, Vector2(w - wall_t * 0.5, h * 0.5), Vector2(wall_t, h))

func _spawn_boss_at(room: Node, scene_path: String, pos: Vector2) -> void:
	var scene := load(scene_path) as PackedScene
	if not scene:
		return
	var boss_node := scene.instantiate() as Node2D
	if not boss_node:
		return
	boss_node.position = pos
	room.add_child(boss_node)

func _spawn_collectible(room: Node, scene_path: String, pos: Vector2, index: int) -> void:
	var scene := load(scene_path) as PackedScene
	if not scene:
		return
	var node := scene.instantiate() as Node2D
	if not node:
		return
	node.position = pos
	if "fragment_index" in node:
		node.fragment_index = index
	if "totem_index" in node:
		node.totem_index = index
	room.add_child(node)

# ── Boss 02 — Хранитель Вітрів (activate_in_sequence, flying) ─────────────────
func _build_arena_boss_02() -> void:
	const W: float = 900.0
	const H: float = 700.0
	const WALL_T: float = 32.0
	var room := Node2D.new()
	room.name = "Arena_Boss02"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)
	_add_arena_walls(room, W, H, WALL_T)

	# Vertical stack of platforms (totems sit on them)
	_add_static_rect(room, Vector2(180.0, 540.0), Vector2(180.0, WALL_T))
	_add_static_rect(room, Vector2(W * 0.5, 400.0), Vector2(180.0, WALL_T))
	_add_static_rect(room, Vector2(W - 180.0, 260.0), Vector2(180.0, WALL_T))

	_spawn_point.position = Vector2(90.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 60.0)

	_spawn_boss_at(room, "res://scenes/enemies/BossCircle2.tscn",
				   Vector2(W * 0.5, 180.0))

	var totem_path := "res://scenes/enemies/Totem.tscn"
	_spawn_collectible(room, totem_path, Vector2(180.0,   520.0), 0)
	_spawn_collectible(room, totem_path, Vector2(W * 0.5, 380.0), 1)
	_spawn_collectible(room, totem_path, Vector2(W - 180.0, 240.0), 2)

# ── Boss 03 — Вогняний Колос (lure_into_trap, multi-tier) ─────────────────────
func _build_arena_boss_03() -> void:
	const W: float = 1000.0
	const H: float = 600.0
	const WALL_T: float = 32.0
	var room := Node2D.new()
	room.name = "Arena_Boss03"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)
	_add_arena_walls(room, W, H, WALL_T)

	# Upper-tier platforms where fire crystals sit
	_add_static_rect(room, Vector2(220.0, 380.0), Vector2(200.0, WALL_T))
	_add_static_rect(room, Vector2(W * 0.5, 260.0), Vector2(200.0, WALL_T))
	_add_static_rect(room, Vector2(W - 220.0, 380.0), Vector2(200.0, WALL_T))

	_spawn_point.position = Vector2(80.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 60.0)

	_spawn_boss_at(room, "res://scenes/enemies/BossCircle3.tscn",
				   Vector2(W * 0.5, H - WALL_T - 80.0))

	var frag_path := "res://scenes/enemies/KeyFragment.tscn"
	_spawn_collectible(room, frag_path, Vector2(220.0,    350.0), 0)
	_spawn_collectible(room, frag_path, Vector2(W * 0.5,  230.0), 1)
	_spawn_collectible(room, frag_path, Vector2(W - 220.0, 350.0), 2)

# ── Boss 07 — Зрадник (identify_and_evade, 3 copies) ──────────────────────────
func _build_arena_boss_07() -> void:
	const W: float = 1100.0
	const H: float = 600.0
	const WALL_T: float = 32.0
	var room := Node2D.new()
	room.name = "Arena_Boss07"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)
	_add_arena_walls(room, W, H, WALL_T)

	# Labyrinth-ish platforms — copies scatter across the arena
	_add_static_rect(room, Vector2(260.0, 400.0),   Vector2(200.0, WALL_T))
	_add_static_rect(room, Vector2(W - 260.0, 400.0), Vector2(200.0, WALL_T))
	_add_static_rect(room, Vector2(W * 0.5, 280.0), Vector2(240.0, WALL_T))

	_spawn_point.position = Vector2(80.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 60.0)

	_spawn_boss_at(room, "res://scenes/enemies/BossCircle7.tscn",
				   Vector2(W * 0.5, H - WALL_T - 80.0))

	# Spawn 3 copies — BossAI.spawn_copies wires setup_as_copy so only
	# the real one takes staff hits.
	var boss_node: Node = _get_boss()
	var copy_scene := load("res://scenes/enemies/BossCircle7.tscn") as PackedScene
	if boss_node and boss_node.has_method("spawn_copies") and copy_scene:
		boss_node.spawn_copies(copy_scene, 3)

# ── Boss 10 — Люцифер (3 phases, sin_aura, prayer_ritual) ─────────────────────
func _build_arena_boss_10() -> void:
	const W: float = 1280.0
	const H: float = 720.0
	const WALL_T: float = 32.0
	var room := Node2D.new()
	room.name = "Arena_Boss10"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)
	_add_arena_walls(room, W, H, WALL_T)

	# Pedestals where the 5 final souls sit
	_add_static_rect(room, Vector2(220.0,  H - WALL_T - 120.0), Vector2(80.0, 24.0))
	_add_static_rect(room, Vector2(W - 220.0, H - WALL_T - 120.0), Vector2(80.0, 24.0))
	_add_static_rect(room, Vector2(320.0, 300.0), Vector2(80.0, 24.0))
	_add_static_rect(room, Vector2(W - 320.0, 300.0), Vector2(80.0, 24.0))
	_add_static_rect(room, Vector2(W * 0.5, 180.0), Vector2(80.0, 24.0))

	_spawn_point.position = Vector2(80.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 60.0)

	_spawn_boss_at(room, "res://scenes/enemies/BossCircle10.tscn",
				   Vector2(W * 0.5, H - WALL_T - 120.0))

	# Five final souls; BossAI phase transitions trigger at 3 and 5 picks.
	var soul_scene := load("res://scenes/Soul.tscn") as PackedScene
	if soul_scene:
		var positions: Array = [
			Vector2(220.0,  H - WALL_T - 150.0),
			Vector2(W - 220.0, H - WALL_T - 150.0),
			Vector2(320.0, 270.0),
			Vector2(W - 320.0, 270.0),
			Vector2(W * 0.5, 150.0),
		]
		for pos in positions:
			var soul := soul_scene.instantiate() as Node2D
			if soul:
				soul.position = pos
				room.add_child(soul)

# ── Boss 05 — Гнів Втілений (dodge_and_collect, charge/wall-stun) ─────────────
func _build_arena_boss_05() -> void:
	const W: float = 1200.0   # wider so wall charges have room to build up
	const H: float = 500.0
	const WALL_T: float = 32.0
	var room := Node2D.new()
	room.name = "Arena_Boss05"
	room.set_meta("room_width",  W)
	room.set_meta("room_height", H)
	_room_container.add_child(room)
	_add_arena_walls(room, W, H, WALL_T)

	# Two low shelves to add vertical variety but leave long clear lines
	# for the boss's charge mechanic.
	_add_static_rect(room, Vector2(300.0,  340.0), Vector2(160.0, WALL_T))
	_add_static_rect(room, Vector2(W - 300.0, 340.0), Vector2(160.0, WALL_T))

	_spawn_point.position = Vector2(80.0, H - WALL_T - 60.0)
	_exit_area.position   = Vector2(W - 80.0, H - WALL_T - 60.0)

	_spawn_boss_at(room, "res://scenes/enemies/BossCircle5.tscn",
				   Vector2(W * 0.5, H - WALL_T - 80.0))

	# Souls near the walls (boss wall-charges → stuns on impact)
	var frag_path := "res://scenes/enemies/KeyFragment.tscn"
	_spawn_collectible(room, frag_path, Vector2(80.0,      H - WALL_T - 40.0), 0)
	_spawn_collectible(room, frag_path, Vector2(W - 80.0,  H - WALL_T - 40.0), 1)
	_spawn_collectible(room, frag_path, Vector2(W * 0.5,   H - WALL_T - 40.0), 2)

# ── Soul pickup — auto-deliver in boss arenas (no altar) ─────────────────────

## Boss arenas don't have altars. The base flow locks Player.carried_soul_id
## until they reach an altar — meaning the player could only ever pick up
## one soul, blocking phase progression on Boss10. Override the base hook so
## the boss is notified and the carried slot is freed immediately, letting
## the player chain pickups across the arena.
func _on_soul_pickup_started(soul: Node) -> void:
	super(soul)
	if _player and _player.has_method("_drop_soul"):
		_player._drop_soul()

# ── Process: prayer mechanic ──────────────────────────────────────────────────

func _process(delta: float) -> void:
	if not _boss or _boss_defeated or not _boss.has_method("tick_prayer"):
		return

	var action: StringName = &"pray" if InputMap.has_action(&"pray") else &"ui_accept"
	if Input.is_action_pressed(action):
		if not _prayer_held:
			_prayer_held = true
		_boss.tick_prayer(delta)
	else:
		if _prayer_held:
			_prayer_held = false
			if _boss.has_method("reset_prayer"):
				_boss.reset_prayer()

# ── Exit override — locked until boss is defeated ─────────────────────────────

func _on_exit_body_entered(body: Node2D) -> void:
	if body != _player or _is_complete:
		return
	# Some bosses (e.g. identify_and_evade) only declare victory when the
	# player reaches the exit in the right state — ask the boss first so its
	# win_condition_met signal can flip _boss_defeated before the guard below.
	if _boss and not _boss_defeated and _boss.has_method("on_player_reached_exit"):
		_boss.on_player_reached_exit()
	if not _boss_defeated:
		if TutorialManager:
			TutorialManager.show_hint("defeat_boss_first")
		_flash_notify("Спочатку переможи боса")
		return
	_complete_level()

# ── Boss signal wiring ────────────────────────────────────────────────────────

func _connect_boss_signals() -> void:
	_boss.win_condition_met.connect(_on_boss_win)
	_boss.sin_aura_tick.connect(_on_sin_aura_tick)
	_boss.boss_stunned.connect(_on_boss_stunned)
	_boss.boss_stun_ended.connect(_on_boss_stun_ended)
	_boss.phase_changed.connect(_on_phase_changed)
	if _boss.has_signal("progress_updated"):
		_boss.progress_updated.connect(_on_boss_progress)

func _register_arena_objects() -> void:
	if not _boss.has_method("register_arena_objects"):
		return
	var objects: Array = []
	for group in ["collectible", "totem", "fragment", "crystal"]:
		objects.append_array(get_tree().get_nodes_in_group(group))
	if objects.size() > 0:
		_boss.register_arena_objects(objects)

# ── Boss event handlers ───────────────────────────────────────────────────────

func _on_boss_win() -> void:
	if _boss_defeated:
		return
	_boss_defeated = true
	_shake_camera(0.5, 16.0)
	_flash_notify("Бос переможений!", 3.0, Color("#FFD700"))
	_hide_phase_panel()

	# Give player time to walk to exit; auto-complete as fallback
	await get_tree().create_timer(AUTO_COMPLETE_DELAY).timeout
	if not _is_complete:
		_complete_level()

func _on_sin_aura_tick(amount: float) -> void:
	if GameManager and GameManager.has_method("add_sin"):
		GameManager.add_sin(amount)
	_shake_camera(0.08, 3.0)

func _on_boss_stunned(_duration: float) -> void:
	_shake_camera(0.25, 10.0)
	_flash_notify("ОГЛУШЕНО!", 2.2, Color("#88EEFF"))

func _on_boss_stun_ended() -> void:
	pass

func _on_phase_changed(phase_index: int) -> void:
	_current_phase = phase_index
	_update_phase_dots(phase_index)
	if phase_index > 0 and phase_index < PHASE_LABELS.size():
		var label: String = PHASE_LABELS[phase_index]
		if label != "":
			_shake_camera(0.4, 14.0)
			_flash_notify(label, 3.0, Color("#FF4444"))

# ── Intro overlay ─────────────────────────────────────────────────────────────

func _build_boss_intro() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 20
	add_child(_intro_layer)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_layer.add_child(bg)

	var boss_name: String = _get_boss_name()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 8)
	vbox.offset_left   = -200.0
	vbox.offset_right  =  200.0
	vbox.offset_top    =  -60.0
	vbox.offset_bottom =   60.0
	_intro_layer.add_child(vbox)

	var lbl_chapter := Label.new()
	lbl_chapter.text = "БОС"
	lbl_chapter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_chapter.add_theme_font_size_override("font_size", 14)
	lbl_chapter.add_theme_color_override("font_color", Color(0.55, 0.52, 0.62))
	vbox.add_child(lbl_chapter)

	var lbl_name := Label.new()
	lbl_name.text = boss_name
	lbl_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_name.add_theme_font_size_override("font_size", 36)
	lbl_name.add_theme_color_override("font_color", Color("#CC2222"))
	vbox.add_child(lbl_name)

	# Fade-in → hold → fade-out
	var tw := create_tween()
	tw.tween_property(bg,        "color",      Color(0.0, 0.0, 0.0, 0.75),  0.6)
	tw.parallel().tween_property(vbox, "modulate:a", 1.0, 0.6)
	vbox.modulate.a = 0.0
	tw.tween_interval(INTRO_HOLD_SECONDS)
	tw.tween_property(bg,        "color",      Color(0.0, 0.0, 0.0, 0.0),   0.7)
	tw.parallel().tween_property(vbox, "modulate:a", 0.0, 0.7)
	tw.tween_callback(func() -> void:
		_intro_layer.queue_free()
		_intro_layer = null
		_build_phase_panel()
	)

func _get_boss_name() -> String:
	if _boss and _boss.has_method("get") and _boss.get("boss_id") != null:
		return BOSS_NAMES.get(_boss.get("boss_id"), "Невідомий")
	return "Невідомий"

# ── Phase indicator panel ─────────────────────────────────────────────────────

func _build_phase_panel() -> void:
	if not _boss:
		return
	var total_phases: int = _boss.get("_phase_cfg").size() if _boss.get("_phase_cfg") != null else 0
	# Show the panel if the boss has multiple phases OR exposes the
	# progress_updated signal — single-phase bosses (e.g. boss_01 collect-3)
	# still benefit from a progress bar.
	var has_progress: bool = _boss.has_signal("progress_updated")
	if total_phases <= 1 and not has_progress:
		return

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_phase_panel = Control.new()
	_phase_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_phase_panel.custom_minimum_size = Vector2(0, 70)
	layer.add_child(_phase_panel)

	# Phase dots — only when boss actually has multiple phases.
	if total_phases > 1:
		var dots_row := HBoxContainer.new()
		dots_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
		dots_row.add_theme_constant_override("separation", 10)
		dots_row.offset_top = 8.0
		_phase_panel.add_child(dots_row)

		_phase_dots.clear()
		for i in total_phases:
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(12, 12)
			dot.color = Color("#CC2222") if i == 0 else Color(0.28, 0.26, 0.35)
			dots_row.add_child(dot)
			_phase_dots.append(dot)

	# Progress bar (label + bar + numeric value).
	if has_progress:
		_build_progress_bar(_phase_panel)

func _build_progress_bar(parent: Control) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_TOP)
	holder.offset_top = 30.0
	holder.custom_minimum_size = Vector2(_PROGRESS_BAR_W, 38)
	holder.position = Vector2(-_PROGRESS_BAR_W * 0.5, 30.0)
	parent.add_child(holder)

	_progress_label = Label.new()
	_progress_label.position = Vector2(0, 0)
	_progress_label.size = Vector2(_PROGRESS_BAR_W * 0.7, 18)
	_progress_label.add_theme_font_size_override("font_size", 14)
	_progress_label.add_theme_color_override("font_color", Color(0.92, 0.90, 0.96))
	_progress_label.text = ""
	holder.add_child(_progress_label)

	_progress_value = Label.new()
	_progress_value.position = Vector2(_PROGRESS_BAR_W * 0.7, 0)
	_progress_value.size = Vector2(_PROGRESS_BAR_W * 0.3, 18)
	_progress_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_value.add_theme_font_size_override("font_size", 14)
	_progress_value.add_theme_color_override("font_color", Color("#FFD060"))
	_progress_value.text = ""
	holder.add_child(_progress_value)

	_progress_bar_bg = ColorRect.new()
	_progress_bar_bg.position = Vector2(0, 22)
	_progress_bar_bg.size = Vector2(_PROGRESS_BAR_W, _PROGRESS_BAR_H)
	_progress_bar_bg.color = Color(0.10, 0.08, 0.14, 0.85)
	holder.add_child(_progress_bar_bg)

	_progress_bar_fg = ColorRect.new()
	_progress_bar_fg.position = Vector2.ZERO
	_progress_bar_fg.size = Vector2(0, _PROGRESS_BAR_H)
	_progress_bar_fg.color = Color("#CC2222")
	_progress_bar_bg.add_child(_progress_bar_fg)

func _on_boss_progress(label: String, value: float, max_value: float) -> void:
	if not _progress_bar_fg or not is_instance_valid(_progress_bar_fg):
		return
	var ratio: float = 0.0 if max_value <= 0.0 else clampf(value / max_value, 0.0, 1.0)
	_progress_label.text = label
	# Integer counts read better as "3 / 5", floating values as "5.4 / 8.0".
	if _is_integer_like(value, max_value):
		_progress_value.text = "%d / %d" % [int(round(value)), int(round(max_value))]
	else:
		_progress_value.text = "%.1f / %.1f" % [value, max_value]
	# Tween fill so +1 collectible reads as a beat instead of a snap.
	var target_w: float = _PROGRESS_BAR_W * ratio
	var tw := create_tween()
	tw.tween_property(_progress_bar_fg, "size:x", target_w, 0.25) \
		.set_ease(Tween.EASE_OUT)
	# Pulse to gold near completion so the player feels "almost there".
	if ratio >= 0.8:
		_progress_bar_fg.color = Color("#FFD060")
	else:
		_progress_bar_fg.color = Color("#CC2222")

func _is_integer_like(a: float, b: float) -> bool:
	# Picks the nicer formatter — counts (souls, totems) vs prayer seconds.
	return absf(a - round(a)) < 0.05 and absf(b - round(b)) < 0.05

func _update_phase_dots(active_phase: int) -> void:
	for i in _phase_dots.size():
		_phase_dots[i].color = Color("#CC2222") if i <= active_phase else Color(0.28, 0.26, 0.35)

func _hide_phase_panel() -> void:
	if _phase_panel and is_instance_valid(_phase_panel):
		var tw := create_tween()
		tw.tween_property(_phase_panel, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func() -> void:
			if is_instance_valid(_phase_panel):
				_phase_panel.get_parent().queue_free()
		)

# ── Notification flash (stun, phase change, etc.) ─────────────────────────────

func _build_notify_layer() -> void:
	_notify_layer = CanvasLayer.new()
	_notify_layer.layer = 15
	add_child(_notify_layer)

	_notify_label = Label.new()
	_notify_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notify_label.offset_top    =  80.0
	_notify_label.offset_bottom = 120.0
	_notify_label.offset_left   = -200.0
	_notify_label.offset_right  =  200.0
	_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notify_label.add_theme_font_size_override("font_size", 18)
	_notify_label.modulate.a = 0.0
	_notify_layer.add_child(_notify_label)

func _shake_camera(duration: float, intensity: float) -> void:
	var shaker: Node = get_node_or_null("/root/CameraShake")
	if shaker and shaker.has_method("shake"):
		shaker.shake(duration, intensity)

func _flash_notify(text: String, duration: float = 2.0,
		color: Color = Color(0.90, 0.88, 0.96)) -> void:
	if not _notify_label:
		return
	_notify_label.text = text
	_notify_label.add_theme_color_override("font_color", color)

	var tw := create_tween()
	tw.tween_property(_notify_label, "modulate:a", 1.0, 0.25)
	tw.tween_interval(duration)
	tw.tween_property(_notify_label, "modulate:a", 0.0, 0.4)
