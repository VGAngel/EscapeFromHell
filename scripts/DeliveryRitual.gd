extends Node

# "Soul-deliver ritual moment" — turns the routine altar tap into a
# small, ceremonial beat. Activated by AltarNode the instant a
# soul-carrying player enters its area; deactivated on either:
#   • successful deliver (restored quickly with a flourish), or
#   • player leaving the area (restored quietly).
#
# What changes during the ritual:
#   • Engine.time_scale → RITUAL_TIME_SCALE so player movement reads
#     "considered" and the camera-follow lag feels weighty.
#   • Music bus is ducked by RITUAL_MUSIC_DUCK_DB so the world hushes;
#     the altar's own sfx still plays full because it's on SFX bus.
#   • An optional halo glow is brightened/scaled on whatever sprite
#     AltarNode wants to highlight (passed via configure()).
#
# The ritual is reduce-motion aware: if MotionSettings is enabled the
# time-scale change is skipped (audio duck still applies — it's not a
# motion-sickness trigger).

const RITUAL_TIME_SCALE   := 0.72
const RITUAL_MUSIC_DUCK_DB := -6.0
const TIME_FADE_IN_S       := 0.18
const TIME_FADE_OUT_S      := 0.30
const AUDIO_FADE_S         := 0.18

# Snapshot of pre-ritual state so we can restore exactly.
var _orig_time_scale: float = 1.0
var _orig_music_db: float   = 0.0
var _active: bool           = false
var _audio_tween: Tween     = null
var _time_tween:  Tween     = null
var _reduce_motion: bool    = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ms: Node = get_node_or_null("/root/MotionSettings")
	if ms and ms.has_signal("changed"):
		ms.changed.connect(_on_motion_changed)
	_reduce_motion = (
			ms and ms.has_method("is_enabled") and ms.is_enabled())


# Always restore on free in case the altar gets queue_freed mid-ritual
# (scene change, etc) — leaving time_scale at 0.7 forever would be a
# nasty bug to track down.
func _exit_tree() -> void:
	if _active:
		_hard_restore()


# ── Public ────────────────────────────────────────────────────────────────────

# Enter the ritual. No-op if already active so re-triggering on a
# soul-pickup-while-in-range doesn't double up.
func enter() -> void:
	if _active:
		return
	_active = true
	_orig_time_scale = Engine.time_scale
	_orig_music_db = _read_music_db()
	if not _reduce_motion:
		_tween_time_scale(RITUAL_TIME_SCALE, TIME_FADE_IN_S)
	_tween_music_db(_orig_music_db + RITUAL_MUSIC_DUCK_DB, AUDIO_FADE_S)


# Exit the ritual. `delivered` is informational — we restore either way,
# but a successful delivery may want a slightly faster snap-back so the
# light-pillar animation feels "released" rather than dragged.
func exit(delivered: bool = false) -> void:
	if not _active:
		return
	_active = false
	var t_out: float = TIME_FADE_OUT_S if not delivered else TIME_FADE_OUT_S * 0.6
	if not _reduce_motion:
		_tween_time_scale(_orig_time_scale, t_out)
	_tween_music_db(_orig_music_db, AUDIO_FADE_S)


func is_active() -> bool:
	return _active


# ── Tweens ────────────────────────────────────────────────────────────────────

func _tween_time_scale(target: float, duration: float) -> void:
	if _time_tween and _time_tween.is_valid():
		_time_tween.kill()
	_time_tween = create_tween()
	_time_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_time_tween.tween_property(Engine, "time_scale", target, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _tween_music_db(target_db: float, duration: float) -> void:
	if _audio_tween and _audio_tween.is_valid():
		_audio_tween.kill()
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx < 0:
		return
	_audio_tween = create_tween()
	_audio_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_audio_tween.tween_method(
			Callable(self, "_set_music_db_now"),
			_read_music_db(),
			target_db,
			duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_music_db_now(db: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, db)


func _read_music_db() -> float:
	var bus_idx: int = AudioServer.get_bus_index("Music")
	if bus_idx < 0:
		return 0.0
	return AudioServer.get_bus_volume_db(bus_idx)


# Forced instant restore — used on _exit_tree to guarantee state
# doesn't leak across scene changes.
func _hard_restore() -> void:
	if _time_tween and _time_tween.is_valid():
		_time_tween.kill()
	if _audio_tween and _audio_tween.is_valid():
		_audio_tween.kill()
	Engine.time_scale = _orig_time_scale
	_set_music_db_now(_orig_music_db)


# ── Reduce-motion ─────────────────────────────────────────────────────────────

func _on_motion_changed(enabled: bool) -> void:
	_reduce_motion = enabled
	# If we flip on while currently in a ritual, restore the time scale
	# right away so the player isn't stuck at 0.72×.
	if _active and enabled:
		Engine.time_scale = _orig_time_scale
