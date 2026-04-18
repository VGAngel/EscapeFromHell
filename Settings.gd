extends Control

@onready var notice_label: Label = %NoticeLabel

func _ready() -> void:
	notice_label.text = ""

func _apply_resolution(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	await get_tree().process_frame
	if DisplayServer.window_get_size() == size:
		var screen := DisplayServer.screen_get_size()
		DisplayServer.window_set_position((screen - size) / 2)
		notice_label.add_theme_color_override("font_color", Color(0.4, 1, 0.4, 1))
		notice_label.text = "Applied: %d x %d" % [size.x, size.y]
	else:
		notice_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3, 1))
		notice_label.text = "Embedded mode: запусти гру окремим вікном\n(Editor Settings > Run > Window Placement)"

func _on_mobile_portrait_pressed() -> void:
	_apply_resolution(Vector2i(720, 1280))

func _on_mobile_fhd_pressed() -> void:
	_apply_resolution(Vector2i(1080, 1920))

func _on_pc_hd_pressed() -> void:
	_apply_resolution(Vector2i(1280, 720))

func _on_pc_fhd_pressed() -> void:
	_apply_resolution(Vector2i(1920, 1080))

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu.tscn")
