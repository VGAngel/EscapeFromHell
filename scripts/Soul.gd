extends Area2D

const SIZE: float = 80.0   # diameter px; collision radius = SIZE / 2 in Soul.tscn

# Area2D pickup representing a soul in the level.
#
# Pickup is MANUAL — the player must press [E] while in range.
# soul_pickup_started  → emitted when player picks up from the ground;
#                        LevelBase stores soul data for later.
# soul_collected       → kept for compatibility but no longer emitted here;
#                        counting/reveal now happen on altar delivery.

signal soul_pickup_started(soul: Area2D)

const _TEXTURE_PATHS := {
	"innocent": "res://Assets/OurAssets/base_soul.png",
	"sleeping": "res://Assets/OurAssets/sleeping_soul.png",
	"mimic":    "res://Assets/OurAssets/mimic.png",
}

var _base_y:       float               = 0.0
var _time:         float               = 0.0
var _soul_id:      int                 = 0
var _soul_data:    Dictionary          = {}
var _is_hidden:    bool                = false
var _soul_type:    String              = "innocent"
var _pulse_tween:  Tween              = null
var _player_nearby: CharacterBody2D   = null
var _prompt_label: Label              = null

func _ready() -> void:
	_apply_size()
	add_to_group("soul")
	_base_y = position.y
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_start_pulse()
	_build_prompt()

func _apply_size() -> void:
	var col := $CollisionShape2D
	if col and col.shape is CircleShape2D:
		(col.shape as CircleShape2D).radius = SIZE / 2.0
	$Sprite2D.scale = Vector2.ONE * (SIZE / 1024.0)

## Sets the soul type ("innocent" / "sleeping" / "mimic") and updates texture + pulse.
func set_soul_type(type: String) -> void:
	_soul_type = type
	var path: String = _TEXTURE_PATHS.get(type, _TEXTURE_PATHS["innocent"])
	if ResourceLoader.exists(path):
		$Sprite2D.texture = load(path)
	_start_pulse()

func _start_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops()
	match _soul_type:
		"innocent":
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 0.6, 0.8)
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 1.0, 0.8)
		"sleeping":
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 0.4, 1.8)
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 0.9, 1.8)
		"mimic":
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 0.7, 0.15)
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 1.0, 0.40)
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 0.85, 0.60)
			_pulse_tween.tween_property($Sprite2D, "modulate:a", 1.0, 0.20)

func _build_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.text = "[E] Підібрати"
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_size_override("font_size", 14)
	_prompt_label.add_theme_color_override("font_color", Color("#FFE7A3"))
	_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt_label.add_theme_constant_override("outline_size", 3)
	_prompt_label.custom_minimum_size = Vector2(120, 24)
	_prompt_label.position = Vector2(-60, -52)
	_prompt_label.visible = false
	add_child(_prompt_label)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.5) * 10.0
	if _is_hidden:
		_update_hidden_visibility()
	if _soul_type == "mimic":
		_update_mimic_highlight()
	# Manual pickup — player must press [E] while in range.
	if _player_nearby and Input.is_action_just_pressed("interact"):
		_do_pickup()

func _do_pickup() -> void:
	if not is_instance_valid(_player_nearby):
		return
	# Pass a string soul_id so Player.pick_up_soul() can store it.
	var soul_id_str: String = str(_soul_id) if _soul_id != 0 else str(get_instance_id())
	_player_nearby.pick_up_soul(soul_id_str)
	# Notify LevelBase so it can store soul data for the altar delivery reveal.
	soul_pickup_started.emit(self)
	# Visual FX.
	var fx: Node = get_node_or_null("/root/ParticleEffects")
	if fx and fx.has_method("spawn"):
		fx.spawn("soul_pickup", global_position)
	# Stop further interaction.
	_player_nearby = null
	if _prompt_label:
		_prompt_label.visible = false
	set_deferred("monitoring", false)
	# Fade + scale out then free.
	if _pulse_tween:
		_pulse_tween.kill()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.6, 1.6), 0.2)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(queue_free)

func _update_mimic_highlight() -> void:
	var has_recognition := SaveManager and SaveManager.has_upgrade("recognition")
	$Sprite2D.modulate = Color.RED if has_recognition else Color.WHITE

## Hidden souls are nearly invisible unless the player bought the
## `soul_sense` upgrade — then they pulse at full alpha so they're findable.
func _update_hidden_visibility() -> void:
	var has_sense := SaveManager and SaveManager.has_upgrade("soul_sense")
	if has_sense:
		modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_time * 3.0))
	else:
		modulate.a = 0.12

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_nearby = body as CharacterBody2D
	if _prompt_label:
		_prompt_label.visible = true
	var tm: Node = get_node_or_null("/root/TutorialManager")
	if tm and tm.has_method("show_hint"):
		tm.show_hint("soul_pickup")

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_nearby = null
	if _prompt_label:
		_prompt_label.visible = false

# ── Named-soul data ───────────────────────────────────────────────────────────

## Called by LevelBase._mark_primary_soul() to tag this node as a named soul.
func set_soul_data(soul_id: int, data: Dictionary) -> void:
	_soul_id   = soul_id
	_soul_data = data
	set_meta("soul_id", soul_id)

func get_soul_data() -> Dictionary:
	return _soul_data

func get_soul_type() -> String:
	return _soul_type

func has_name() -> bool:
	return _soul_data.has("name") and _soul_data["name"] != ""

## Mark this soul as a hidden-placement pickup.
func set_hidden(is_hidden_soul: bool) -> void:
	_is_hidden = is_hidden_soul
	if is_hidden_soul:
		modulate.a = 0.12

# ── Floating name label ───────────────────────────────────────────────────────

func _spawn_name_label() -> void:
	if not has_name():
		return
	var lbl := Label.new()
	lbl.text = _soul_data.get("name", "")
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color("#FFE7A3"))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var parent := get_parent()
	if not parent:
		return
	var mover := Node2D.new()
	mover.position = position - Vector2(40, 20)
	parent.add_child(mover)
	lbl.custom_minimum_size = Vector2(80, 24)
	lbl.position = Vector2.ZERO
	mover.add_child(lbl)
	var tw := mover.create_tween()
	tw.parallel().tween_property(mover, "position:y", mover.position.y - 40.0, 1.0)
	tw.parallel().tween_property(lbl,    "modulate:a", 0.0, 1.0).set_delay(0.35)
	tw.tween_callback(mover.queue_free)
