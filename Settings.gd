extends Control

func _apply_resolution(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	var screen_size := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen_size - size) / 2)

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
