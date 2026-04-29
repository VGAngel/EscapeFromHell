extends Node

# Single source of truth for the player's "reduce motion" preference.
#
# Why a dedicated autoload (instead of just reading SettingsScreen's
# settings.json directly):
#   • Settings is an overlay — it comes and goes; subscribers need a
#     persistent signal source.
#   • Motion-aware components (MenuAmbient, SinVignette, HeroCard
#     breathing, future damage shake, etc.) live across multiple
#     scenes — they all need a single, consistent toggle.
#   • Tests can pass a stub autoload without touching disk.
#
# The actual persistence still happens in SettingsScreen's settings.json
# (key: `reduce_motion`). On boot SettingsScreen calls `set_enabled()`
# which loads the value here; MotionSettings just rebroadcasts via its
# `changed` signal.

signal changed(reduce_motion: bool)

var _enabled: bool = false


# ── Public API ────────────────────────────────────────────────────────────────

func is_enabled() -> bool:
	return _enabled


# Setter that emits `changed` only when the value actually flipped, so
# subscribers don't re-render on no-op apply_all() calls.
func set_enabled(value: bool) -> void:
	value = bool(value)
	if value == _enabled:
		return
	_enabled = value
	changed.emit(_enabled)
