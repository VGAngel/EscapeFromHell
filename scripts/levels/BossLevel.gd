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
	if total_phases <= 1:
		return   # single-phase boss needs no indicator

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	_phase_panel = Control.new()
	_phase_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_phase_panel.custom_minimum_size = Vector2(0, 28)
	layer.add_child(_phase_panel)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hbox.add_theme_constant_override("separation", 10)
	hbox.offset_top = 8.0
	_phase_panel.add_child(hbox)

	_phase_dots.clear()
	for i in total_phases:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.color = Color("#CC2222") if i == 0 else Color(0.28, 0.26, 0.35)
		hbox.add_child(dot)
		_phase_dots.append(dot)

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
