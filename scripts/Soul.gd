extends Area2D

# Area2D pickup representing a soul in the level.
#
# LevelBase discovers souls via the "soul" group, connects to the
# soul_collected signal, increments its counters, forwards to
# GameManager.collect_soul(), and — for named souls — pops a
# SoulRevealPanel with the epitaph.

signal soul_collected(soul: Area2D)

var _base_y:    float      = 0.0
var _time:      float      = 0.0
var _soul_id:   int        = 0
var _soul_data: Dictionary = {}
var _is_hidden: bool       = false   # hidden souls fade unless soul_sense active

func _ready() -> void:
	add_to_group("soul")
	_base_y = global_position.y
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	position.y = _base_y + sin(_time * 2.5) * 10.0
	if _is_hidden:
		_update_hidden_visibility()

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
	_spawn_name_label()
	soul_collected.emit(self)
	# Fade out then free — the signal handler already has what it needs.
	var tw := create_tween()
	tw.parallel().tween_property(self, "scale", Vector2(1.6, 1.6), 0.2)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
	set_deferred("monitoring", false)

# ── Named-soul data ───────────────────────────────────────────────────────────

## Called by LevelBase._mark_primary_soul() to tag this node as a named soul.
func set_soul_data(soul_id: int, data: Dictionary) -> void:
	_soul_id   = soul_id
	_soul_data = data
	set_meta("soul_id", soul_id)

func get_soul_data() -> Dictionary:
	return _soul_data

func has_name() -> bool:
	return _soul_data.has("name") and _soul_data["name"] != ""

## Mark this soul as a hidden-placement pickup. Soul stays nearly invisible
## unless the player bought the `soul_sense` upgrade.
func set_hidden(hidden: bool) -> void:
	_is_hidden = hidden
	if hidden:
		# Start dim right away so level-open is consistent regardless of _process timing.
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
	# Anchor the label around this soul's world position via a separate node
	# so it doesn't get freed when the Soul itself queue_free's.
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
