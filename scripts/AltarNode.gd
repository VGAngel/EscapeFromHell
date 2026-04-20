class_name AltarNode
extends Node2D

# AltarNode — mid-altar for vertical levels.
#
# Player walks into range → interact prompt appears ([E]).
# Player presses [E]      → respawn point binds here, altar glows, prompt hides.
# Second press            → ignored (already bound).
#
# Expected scene structure:
#   AltarNode (Node2D) ← this script
#   ├── Area2D           ← interaction detection zone
#   │   └── CollisionShape2D
#   ├── AnimationPlayer  ← "altar_idle" and "altar_activate" clips
#   └── InteractPrompt (Node2D / Label)  ← "[E] Прив'язати"
#
# LevelBase listens for `respawn_bound` and updates its respawn position.

## Emitted when the player successfully binds the respawn point here.
## @param world_position: global position of the altar (use as new spawn).
signal respawn_bound(world_position: Vector2)

## Input action name. Must exist in Project → Input Map; fallback: "ui_accept".
const INTERACT_ACTION := "interact"

# ── State ─────────────────────────────────────────────────────────────────────

## True once the player has bound respawn to this altar.
var _is_active: bool = false

## True while the player's body overlaps _area.
var _player_in_range: bool = false

# ── Child references (all optional — graceful if scene stub is minimal) ───────

@onready var _area:   Area2D         = $Area2D          if has_node("Area2D")          else null
@onready var _anim:   AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var _prompt: Node            = $InteractPrompt  if has_node("InteractPrompt")  else null

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	if _area:
		_area.body_entered.connect(_on_body_entered)
		_area.body_exited.connect(_on_body_exited)
	if _anim:
		_anim.play("altar_idle")
	_update_prompt()

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_range or _is_active:
		return
	var pressed: bool = (
		(InputMap.has_action(INTERACT_ACTION) and event.is_action_pressed(INTERACT_ACTION))
		or event.is_action_pressed("ui_accept")
	)
	if pressed:
		_activate()

# ── Activation ────────────────────────────────────────────────────────────────

func _activate() -> void:
	_is_active = true
	_update_prompt()
	if _anim:
		_anim.play("altar_activate")
	respawn_bound.emit(global_position)

# ── Area callbacks ────────────────────────────────────────────────────────────

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_update_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_update_prompt()

# ── Prompt ────────────────────────────────────────────────────────────────────

func _update_prompt() -> void:
	if not is_instance_valid(_prompt):
		return
	_prompt.visible = _player_in_range and not _is_active

# ── Public API ────────────────────────────────────────────────────────────────

## Returns true if respawn is already bound here.
func is_active() -> bool:
	return _is_active

## Force-bind the altar without player input (used by LevelBase on level restore).
func bind_silently() -> void:
	_is_active = true
	_update_prompt()
	if _anim and not _anim.is_playing():
		_anim.play("altar_activate")
