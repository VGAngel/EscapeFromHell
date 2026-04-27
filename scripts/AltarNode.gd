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
	elif not _is_active:
		_activate()

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
	var soul_id: String = str(_player_node.get("carried_soul_id"))
	if soul_id == "" or soul_id == "null":
		return

	# Bind respawn at the same time if not yet done.
	if not _is_active:
		_activate()

	_player_node.deliver_soul()
	_play_light_pillar()
	soul_delivered_here.emit(soul_id)

func _play_light_pillar() -> void:
	# White-gold beam rising from altar center.
	var beam := ColorRect.new()
	beam.color = Color(1.0, 0.96, 0.55, 0.75)
	beam.size  = Vector2(48, 1000)
	# Position: centered on altar, extending upward.
	beam.position = Vector2(-24, -1000)
	add_child(beam)

	# Glow halo at base of beam.
	var halo := ColorRect.new()
	halo.color = Color(1.0, 0.9, 0.4, 0.5)
	halo.size  = Vector2(160, 80)
	halo.position = Vector2(-80, -80)
	add_child(halo)

	var tw := create_tween().set_parallel(true)
	# Beam: fade in quickly, hold, then fade out.
	beam.modulate.a = 0.0
	tw.tween_property(beam,  "modulate:a", 1.0, 0.25)
	tw.tween_property(beam,  "modulate:a", 0.0, 1.0).set_delay(0.5)
	tw.tween_property(halo,  "modulate:a", 0.0, 0.8).set_delay(0.3)
	# Beam grows slightly upward (scale y 1→1.2) for a "shooting upward" feel.
	tw.tween_property(beam,  "scale:y",    1.2, 1.0).set_delay(0.1)

	await get_tree().create_timer(1.6).timeout
	beam.queue_free()
	halo.queue_free()

# ── Area callbacks ─────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_player_node = body as CharacterBody2D
	_update_prompt()
	_set_pray_button(true)

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_player_node = null
	_update_prompt()
	_set_pray_button(false)

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
	var soul_id = _player_node.get("carried_soul_id")
	return soul_id != null and str(soul_id) != ""

func _set_pray_button(value: bool) -> void:
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() else null
	if hud and hud.has_method("show_pray_button"):
		hud.show_pray_button(value)
