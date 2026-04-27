extends Node

# Autoload: HapticManager
#
# Thin wrapper around Input.vibrate_handheld() for mobile haptic feedback.
# Calls are no-ops on desktop (OS.has_feature("mobile") check) and when the
# user disables haptics in Settings → Accessibility.
#
# Per-event helpers below pick sensible duration/amplitude pairs based on
# what feels good on Android (short subtle for routine actions like jump,
# longer punchier for death/hit). Tune via the constants — every event
# routes through _vibrate() so a global mute/scale change lives in one
# place.

const SAVE_PATH := "user://settings.json"

# Event presets — (duration_ms, amplitude 0..1).
const _PRESET_HIT:        Array = [80,   0.55]
const _PRESET_JUMP:       Array = [25,   0.20]
const _PRESET_PICKUP:     Array = [55,   0.45]
const _PRESET_DEATH:      Array = [220,  0.85]
const _PRESET_BOSS_STUN:  Array = [40,   0.55]   # fired three times in sequence
const _PRESET_DELIVER:    Array = [70,   0.40]

var _enabled: bool = true
var _is_mobile: bool = false

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_is_mobile = OS.has_feature("mobile") or OS.has_feature("android")
	_load_setting()

func _load_setting() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_enabled = bool(parsed.get("haptics", true))

# ── Public API ────────────────────────────────────────────────────────────────

## Player-facing toggle. SettingsScreen calls this when the user flips
## the Haptics switch — value is also saved through the existing settings
## persistence path so we don't double-write.
func set_enabled(value: bool) -> void:
	_enabled = value

func is_enabled() -> bool:
	return _enabled

func is_mobile() -> bool:
	return _is_mobile

# ── Event helpers ─────────────────────────────────────────────────────────────

func hit() -> void:
	_vibrate(_PRESET_HIT[0], _PRESET_HIT[1])

func jump() -> void:
	_vibrate(_PRESET_JUMP[0], _PRESET_JUMP[1])

func pickup() -> void:
	_vibrate(_PRESET_PICKUP[0], _PRESET_PICKUP[1])

func death() -> void:
	_vibrate(_PRESET_DEATH[0], _PRESET_DEATH[1])

func deliver() -> void:
	_vibrate(_PRESET_DELIVER[0], _PRESET_DELIVER[1])

## Three-burst pattern fits the "boss is stunned, hit window!" beat better
## than a single long pulse. Total ≈ 200ms.
func boss_stun() -> void:
	_vibrate(_PRESET_BOSS_STUN[0], _PRESET_BOSS_STUN[1])
	get_tree().create_timer(0.07).timeout.connect(
		func() -> void: _vibrate(_PRESET_BOSS_STUN[0], _PRESET_BOSS_STUN[1])
	)
	get_tree().create_timer(0.14).timeout.connect(
		func() -> void: _vibrate(_PRESET_BOSS_STUN[0], _PRESET_BOSS_STUN[1])
	)

# ── Internals ─────────────────────────────────────────────────────────────────

func _vibrate(duration_ms: int, amplitude: float) -> void:
	if not _enabled or not _is_mobile:
		return
	# Input.vibrate_handheld(duration_ms, amplitude). amplitude is Android-
	# only; iOS ignores it. Clamp defensively.
	Input.vibrate_handheld(duration_ms, clampf(amplitude, 0.0, 1.0))
