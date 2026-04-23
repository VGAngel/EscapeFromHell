extends Node

# Autoload: DisplaySettings
#
# Single source of truth for the current design resolution.
# SettingsScreen applies the resolution via content_scale_size; this autoload
# reads it back so any script can call DisplaySettings.viewport_width() /
# DisplaySettings.viewport_height() instead of hardcoding pixel values.
#
# Also boots the saved resolution on startup (before SettingsScreen opens).

const SAVE_PATH := "user://settings.json"

const RESOLUTIONS := {
	"fhd": Vector2i(1080, 1920),
	"hd":  Vector2i(720,  1280),
}
const DEFAULT_PRESET := "fhd"

# ── Init ──────────────────────────────────────────────────────────────────────

func _ready() -> void:
	apply_saved()

# ── Public API ────────────────────────────────────────────────────────────────

func viewport_width() -> int:
	return get_tree().root.content_scale_size.x

func viewport_height() -> int:
	return get_tree().root.content_scale_size.y

func current_preset() -> String:
	var saved: String = _load_preset()
	return saved if saved in RESOLUTIONS else DEFAULT_PRESET

## Apply the resolution stored in settings.json (call once at startup).
func apply_saved() -> void:
	var preset: String = current_preset()
	_apply(preset)

## Change to a named preset and persist it.
func set_preset(preset: String) -> void:
	if preset not in RESOLUTIONS:
		return
	_apply(preset)
	_save_preset(preset)

# ── Internal ──────────────────────────────────────────────────────────────────

func _apply(preset: String) -> void:
	var size: Vector2i = RESOLUTIONS.get(preset, RESOLUTIONS[DEFAULT_PRESET])
	get_tree().root.content_scale_size = size

func _load_preset() -> String:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return DEFAULT_PRESET
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return str(parsed.get("resolution", DEFAULT_PRESET))
	return DEFAULT_PRESET

func _save_preset(preset: String) -> void:
	# Merge into existing settings file so other keys are preserved.
	var data: Dictionary = {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			data = parsed
	data["resolution"] = preset
	file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
