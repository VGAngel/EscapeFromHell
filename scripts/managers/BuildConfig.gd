extends Node

# Single source of truth for "is this a debug build?" decisions.
#
# Used by every UI surface that should disappear in shipped release
# builds: the Levels (debug) row, the Seed row, the on-screen
# DebugOverlay, dev-only cheats, etc. Without one shared check those
# would drift out of sync — some hidden, some still leaking through.
#
# Resolution order (first match wins):
#
#   1. ProjectSettings  application/config/debug_ui_mode
#        "force_on"   → debug UI always visible
#        "force_off"  → debug UI always hidden
#        "auto" (default) → fall through to step 2
#   2. Export feature flag: OS.has_feature("release")
#        true  → hidden  (a release export was shipped)
#        false → visible (editor / debug export / template)
#
# Packaging tip: set `debug_ui_mode = "force_off"` in the release
# export preset's overrides, OR add a custom feature tag "release"
# (Project → Export → Features) — both paths are honoured.
#
# Tests can flip the runtime flag with `BuildConfig.set_override(...)`
# without touching ProjectSettings.

enum Mode { AUTO, FORCE_ON, FORCE_OFF }

const SETTING_KEY := "application/config/debug_ui_mode"

var _override: int = Mode.AUTO


func _ready() -> void:
	_register_setting()


# Ensure the ProjectSetting exists so it shows up in the editor and
# can be overridden per export preset. Idempotent.
func _register_setting() -> void:
	if not ProjectSettings.has_setting(SETTING_KEY):
		ProjectSettings.set_setting(SETTING_KEY, "auto")
	ProjectSettings.set_initial_value(SETTING_KEY, "auto")
	var hint := {
		"name": SETTING_KEY,
		"type": TYPE_STRING,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "auto,force_on,force_off",
	}
	ProjectSettings.add_property_info(hint)


# ── Public API ────────────────────────────────────────────────────────────────

# True when debug-only UI (Levels(debug), Seed row, DebugOverlay, …)
# should render. False in shipped release builds.
func show_debug_ui() -> bool:
	match _override:
		Mode.FORCE_ON:
			return true
		Mode.FORCE_OFF:
			return false
		_:
			pass
	var raw: String = String(ProjectSettings.get_setting(SETTING_KEY, "auto"))
	match raw:
		"force_on":
			return true
		"force_off":
			return false
		_:
			return not OS.has_feature("release")


# True for dev/editor builds; mirrors `show_debug_ui()` today but kept
# as a separate accessor so we can split UI vs. logic gating later
# (e.g. keep Crashlytics on in release while hiding the debug menu).
func is_debug_build() -> bool:
	return show_debug_ui()


# Test / runtime helper: temporarily force a mode without touching
# ProjectSettings. Pass `Mode.AUTO` to clear the override.
func set_override(mode: int) -> void:
	_override = mode


func clear_override() -> void:
	_override = Mode.AUTO
