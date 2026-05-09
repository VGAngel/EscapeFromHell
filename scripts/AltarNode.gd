class_name AltarNode
extends Node2D

# AltarNode — top-of-level altar (respawn bind + soul delivery).
#
# Two interactions depending on what the player carries:
#   • No soul  → [E] binds respawn point here (one-time).
#   • Carrying soul → [E] delivers the soul: plays light-pillar animation,
#     calls player.deliver_soul(), emits soul_delivered_here.
#
# Expected scene structure (all children optional — graceful fallback):
#   AltarNode (Node2D)
#   ├── Area2D / CollisionShape2D
#   ├── Sprite2D
#   └── InteractPrompt (Label or Node with .text)

signal respawn_bound(world_position: Vector2)

## Emitted after the delivery animation starts (LevelBase listens to show popup).
signal soul_delivered_here(soul_id: String)

const INTERACT_ACTION := "interact"
const PRAY_ACTION     := "pray"

const TEXT_BIND    := "[E] Прив'язати"
const TEXT_DELIVER := "[E] Доставити душу"

# ── State ──────────────────────────────────────────────────────────────────────

var _is_active:       bool                   = false
var _player_in_range: bool                   = false
var _player_node:     CharacterBody2D        = null
var _ritual:          Node                   = null   # DeliveryRitual instance, lazy-built

@onready var _area:   Area2D          = $Area2D          if has_node("Area2D")          else null
@onready var _anim:   AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var _prompt: Node            = $InteractPrompt  if has_node("InteractPrompt")  else null

# ── Init ───────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if _area:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	if _anim:
		_anim.play("altar_idle")
	_update_prompt()

# ── Input ──────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range:
		return
	var pressed: bool = (
		(InputMap.has_action(INTERACT_ACTION) and event.is_action_pressed(INTERACT_ACTION))
		or (InputMap.has_action(PRAY_ACTION)     and event.is_action_pressed(PRAY_ACTION))
		or event.is_action_pressed("ui_accept")
	)
	if not pressed:
		return

	if _player_is_carrying_soul():
		_deliver_soul()
		# Mark the [E] press as consumed. Without this, the same press
		# would then be picked up by Soul._unhandled_input on a soul whose
		# Area2D the player hasn't yet exited — credit a phantom unnamed
		# soul that the player never intentionally collected.
		get_viewport().set_input_as_handled()
	elif not _is_active:
		_activate()
		get_viewport().set_input_as_handled()

# ── Respawn bind ───────────────────────────────────────────────────────────────

func _activate() -> void:
	if _is_active:
		return
	_is_active = true
	_update_prompt()
	if _anim:
		_anim.play("altar_activate")
	respawn_bound.emit(global_position)

# ── Soul delivery ──────────────────────────────────────────────────────────────

func _deliver_soul() -> void:
	if not is_instance_valid(_player_node):
		return
	if not _player_is_carrying_soul():
		return

	# Snapshot the carried list BEFORE deliver_soul() clears it. With the
	# soul_echo upgrade the player can hand in two souls in one tap; we
	# emit our own per-soul signal so listeners (LevelBase reveal popup)
	# can chain the announcements.
	var ids: Array = _player_carried_ids()

	# Bind respawn at the same time if not yet done.
	if not _is_active:
		_activate()

	_player_node.deliver_soul()
	_play_light_pillar()
	for sid in ids:
		soul_delivered_here.emit(String(sid))
	# Release the ritual with a quick snap-back so the light pillar
	# reads as the climactic beat, not a dragged-out fade.
	_exit_ritual(true)

func _play_light_pillar() -> void:
	# White-gold beam rising from altar center.
	var beam := ColorRect.new()
	beam.color = Color(1.0, 0.96, 0.55, 0.75)
	beam.size  = Vector2(48, 1000)
	# Position: centered on altar, extending upward.
	beam.position = Vector2(-24, -1000)
	# LevelBase pauses the tree while the soul-delivered popup plays
	# (~1.8 s). Without PROCESS_MODE_ALWAYS the pillar's tween freezes
	# and only resumes after the popup ends — climax disconnected from
	# the delivery beat.
	beam.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(beam)

	# Glow halo at base of beam.
	var halo := ColorRect.new()
	halo.color = Color(1.0, 0.9, 0.4, 0.5)
	halo.size  = Vector2(160, 80)
	halo.position = Vector2(-80, -80)
	halo.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(halo)

	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Beam: fade in quickly, hold, then fade out.
	beam.modulate.a = 0.0
	tw.tween_property(beam,  "modulate:a", 1.0, 0.25)
	tw.tween_property(beam,  "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_property(halo,  "modulate:a", 0.0, 0.8).set_delay(0.3)
	# Beam grows slightly upward (scale y 1→1.2) for a "shooting upward" feel.
	tw.tween_property(beam,  "scale:y",    1.2, 1.0).set_delay(0.1)

	# `process_always=true` keeps the timer ticking through the popup pause.
	await get_tree().create_timer(1.6, true).timeout
	if is_instance_valid(beam):
		beam.queue_free()
	if is_instance_valid(halo):
		halo.queue_free()

# ── Area callbacks ─────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_player_node = body as CharacterBody2D
	_update_prompt()
	_set_pray_button(true)
	# First-altar discovery hint. Fires once per save (TutorialManager
	# dedupes via SaveManager hint state). Without this, brand-new
	# players who picked up a soul still didn't know that this glowing
	# stone IS the delivery point — the carry_to_exit text says "altar"
	# but the level art doesn't always read as one.
	var tm: Node = TutorialManager
	if tm and tm.has_method("show_hint"):
		# Use the "tutorial." prefix so TutorialManager accepts the id
		# even though there's no entry for "altar" in the legacy
		# tutorial_config.json triggers section. The fallback dict +
		# localization JSON resolve the text directly from the key.
		tm.show_hint("tutorial.altar")
	# Start the ritual ONLY when the player arrives carrying a soul.
	# A soul-less bind interaction stays mundane; the ritual is reserved
	# for the actual delivery moment (the core-loop punctuation).
	if _player_is_carrying_soul():
		_enter_ritual()
	# Edge case: player picks up a soul WHILE already standing on the
	# altar — body_entered won't fire again, so we listen to the signal
	# directly. Disconnected on body_exited.
	if _player_node and _player_node.has_signal("soul_picked_up") \
			and not _player_node.soul_picked_up.is_connected(
					_on_player_picked_up_in_range):
		_player_node.soul_picked_up.connect(_on_player_picked_up_in_range)

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _player_node and _player_node.has_signal("soul_picked_up") \
			and _player_node.soul_picked_up.is_connected(
					_on_player_picked_up_in_range):
		_player_node.soul_picked_up.disconnect(_on_player_picked_up_in_range)
	_player_in_range = false
	_player_node = null
	_update_prompt()
	_set_pray_button(false)
	# Player walked away without delivering — quietly restore.
	_exit_ritual(false)


# Soul picked up while already inside the altar area — kick off the
# ritual now that delivery is possible.
func _on_player_picked_up_in_range(_soul_id: String) -> void:
	if _player_in_range and _player_is_carrying_soul():
		_enter_ritual()


# ── Ritual ─────────────────────────────────────────────────────────────────────

# Lazily instantiate DeliveryRitual on first use so it doesn't sit
# around in altars the player never reaches with a soul in hand.
func _ensure_ritual() -> Node:
	if _ritual == null or not is_instance_valid(_ritual):
		_ritual = preload("res://scripts/DeliveryRitual.gd").new()
		add_child(_ritual)
	return _ritual

func _enter_ritual() -> void:
	_ensure_ritual().enter()

func _exit_ritual(delivered: bool) -> void:
	if _ritual and is_instance_valid(_ritual):
		_ritual.exit(delivered)

# ── Prompt ─────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	var has_soul: bool = _player_is_carrying_soul()
	var visible_now: bool = _player_in_range and (has_soul or not _is_active)
	_prompt.visible = visible_now
	# `if show:` here was reading Node2D.show as a Callable (always truthy).
	# Use visible_now so the prompt text is only refreshed when the prompt
	# is actually shown.
	if visible_now:
		var txt: String = TEXT_DELIVER if has_soul else TEXT_BIND
		if _prompt.has_method("set_text"):
			_prompt.set_text(txt)
		elif "text" in _prompt:
			_prompt.set("text", txt)

# ── Public API ─────────────────────────────────────────────────────────────────

func is_active() -> bool:
	return _is_active

func bind_silently() -> void:
	_is_active = true
	_update_prompt()
	if _anim and not _anim.is_playing():
		_anim.play("altar_activate")

# ── Helpers ────────────────────────────────────────────────────────────────────

func _player_is_carrying_soul() -> bool:
	if not is_instance_valid(_player_node):
		return false
	if _player_node.has_method("is_carrying"):
		return bool(_player_node.is_carrying())
	# Legacy fallback: read whichever carry-state field the Player exposes.
	var ids = _player_node.get("carried_soul_ids")
	if ids is Array:
		return (ids as Array).size() > 0
	var sid = _player_node.get("carried_soul_id")
	return sid != null and str(sid) != ""

func _player_carried_ids() -> Array:
	if not is_instance_valid(_player_node):
		return []
	var ids = _player_node.get("carried_soul_ids")
	if ids is Array:
		return (ids as Array).duplicate()
	var sid = _player_node.get("carried_soul_id")
	if sid != null and str(sid) != "":
		return [str(sid)]
	return []

func _set_pray_button(value: bool) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() else null
	if hud and hud.has_method("show_pray_button"):
		hud.show_pray_button(value)
