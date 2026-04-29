extends Node

# Autoload: add to Project > Project Settings > Autoload as "Loc"
# Usage: Loc.t("ui.button.continue")
#        Loc.t("hud.level_info_format", { "circle": 3, "level": 24 })
#
# UI screens connect to `language_changed` and re-render themselves to
# swap labels live without a scene reload.

signal language_changed(new_language: String)

const LOCALIZATION_DIR := "res://localization/"
const DEFAULT_LANGUAGE := "uk"

var _current_language: String = DEFAULT_LANGUAGE
var _strings: Dictionary = {}
var _fallback: Dictionary = {}

func _ready() -> void:
	_load_language(DEFAULT_LANGUAGE)

func set_language(lang: String) -> void:
	if lang == _current_language:
		return
	_load_language(lang)

func get_language() -> String:
	return _current_language

func t(key: String, params: Dictionary = {}) -> String:
	var value := _resolve(key)
	if params.is_empty():
		return value
	return _format(value, params)

# Resolves dot-notation key: "ui.button.continue" -> "Далі →"
func _resolve(key: String) -> String:
	var parts := key.split(".")
	var node: Variant = _strings
	for part in parts:
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return _resolve_fallback(key)
	if node is String:
		return node
	return _resolve_fallback(key)

func _resolve_fallback(key: String) -> String:
	var parts := key.split(".")
	var node: Variant = _fallback
	for part in parts:
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			push_warning("Loc: missing key '%s' in '%s' and fallback '%s'" % [key, _current_language, DEFAULT_LANGUAGE])
			return key
	if node is String:
		return node
	return key

func _format(template: String, params: Dictionary) -> String:
	var result := template
	for key in params:
		result = result.replace("{%s}" % key, str(params[key]))
	return result

func _load_language(lang: String) -> void:
	var path := LOCALIZATION_DIR + lang + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Loc: cannot load language file: " + path)
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary:
		push_error("Loc: invalid JSON in " + path)
		return
	if lang == DEFAULT_LANGUAGE:
		_fallback = data
	_strings = data
	_current_language = lang
	print("Loc: loaded '%s'" % lang)
	language_changed.emit(lang)
